-- ZERO ERP V1: validated customer receipts and supplier payments.
-- payment_type values are exactly 'receipt' (customer funds received) and
-- 'payment' (supplier funds paid). Allocations are validated against posted
-- source invoices and serialized by locking the invoice row.
BEGIN;

CREATE OR REPLACE FUNCTION public.post_payment(p_organization_id uuid,p_payment_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid:=auth.uid();
  v_org_status text;
  v_payment public.payments%ROWTYPE;
  v_account_type text;
  v_settlement_type text;
  v_journal_id uuid:=gen_random_uuid();
  v_alloc record;
  v_doc_contact uuid;
  v_doc_account uuid;
  v_doc_total numeric(20,4);
  v_returned numeric(20,4);
  v_previously_allocated numeric(20,4);
  v_allocated_total numeric(20,4);
  v_alloc_count bigint;
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;

  SELECT o.status INTO v_org_status
    FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Payment posting requires an active organization' USING ERRCODE='23514';
  END IF;

  SELECT p.* INTO v_payment
    FROM public.payments p
   WHERE p.organization_id=p_organization_id AND p.id=p_payment_id
   FOR UPDATE;
  IF NOT FOUND OR v_payment.status<>'draft' OR v_payment.posted_journal_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Payment not found, not draft, or already posted' USING ERRCODE='23514';
  END IF;
  IF v_payment.payment_type NOT IN ('receipt','payment') THEN
    RAISE EXCEPTION 'Payment type must be receipt or payment' USING ERRCODE='23514';
  END IF;
  IF v_payment.amount<=0 OR v_payment.contact_id IS NULL OR v_payment.settlement_account_id IS NULL THEN
    RAISE EXCEPTION 'Payment requires a positive amount, contact, and settlement account' USING ERRCODE='23514';
  END IF;

  SELECT a.account_type INTO v_account_type
    FROM public.accounts a
   WHERE a.organization_id=p_organization_id AND a.id=v_payment.account_id
     AND a.status='active' AND a.is_postable;
  IF (v_payment.payment_type='receipt' AND v_account_type IS DISTINCT FROM 'asset')
     OR (v_payment.payment_type='payment' AND v_account_type IS DISTINCT FROM 'liability') THEN
    RAISE EXCEPTION 'Receipt requires an active postable receivable asset account; payment requires an active postable payable liability account' USING ERRCODE='23514';
  END IF;

  SELECT a.account_type INTO v_settlement_type
    FROM public.accounts a
   WHERE a.organization_id=p_organization_id AND a.id=v_payment.settlement_account_id
     AND a.status='active' AND a.is_postable;
  IF v_settlement_type IS DISTINCT FROM 'asset' THEN
    RAISE EXCEPTION 'Settlement account must be an active postable asset account' USING ERRCODE='23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.contacts c
     WHERE c.organization_id=p_organization_id AND c.id=v_payment.contact_id AND c.status='active'
  ) THEN
    RAISE EXCEPTION 'Payment contact is missing or inactive' USING ERRCODE='23514';
  END IF;

  SELECT count(*),COALESCE(sum(pa.allocated_amount),0)
    INTO v_alloc_count,v_allocated_total
    FROM public.payment_allocations pa
   WHERE pa.organization_id=p_organization_id AND pa.payment_id=p_payment_id;
  IF v_allocated_total>v_payment.amount THEN
    RAISE EXCEPTION 'Payment allocations exceed payment amount' USING ERRCODE='23514';
  END IF;

  FOR v_alloc IN
    SELECT pa.document_type,pa.document_id,pa.allocated_amount
      FROM public.payment_allocations pa
     WHERE pa.organization_id=p_organization_id AND pa.payment_id=p_payment_id
     ORDER BY pa.document_type,pa.document_id
  LOOP
    IF v_payment.payment_type='receipt' AND v_alloc.document_type='sales' THEN
      SELECT s.customer_id,s.receivable_account_id,s.total_amount
        INTO v_doc_contact,v_doc_account,v_doc_total
        FROM public.sales s
       WHERE s.organization_id=p_organization_id AND s.id=v_alloc.document_id
       FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Receipt allocation references a missing sale' USING ERRCODE='23514'; END IF;
      IF NOT EXISTS(SELECT 1 FROM public.sales s WHERE s.organization_id=p_organization_id AND s.id=v_alloc.document_id AND s.status='posted') THEN
        RAISE EXCEPTION 'Receipt can only be allocated to a posted sale' USING ERRCODE='23514';
      END IF;
      SELECT COALESCE(sum(r.total_amount),0) INTO v_returned
        FROM public.sales_returns r
       WHERE r.organization_id=p_organization_id AND r.sales_id=v_alloc.document_id AND r.status='posted';
      SELECT COALESCE(sum(pa.allocated_amount),0) INTO v_previously_allocated
        FROM public.payment_allocations pa
        JOIN public.payments p ON p.organization_id=pa.organization_id AND p.id=pa.payment_id
       WHERE pa.organization_id=p_organization_id AND pa.document_type='sales'
         AND pa.document_id=v_alloc.document_id AND pa.payment_id<>p_payment_id
         AND p.payment_type='receipt' AND p.status='posted';
    ELSIF v_payment.payment_type='payment' AND v_alloc.document_type='purchase' THEN
      SELECT s.supplier_id,s.payable_account_id,s.total_amount
        INTO v_doc_contact,v_doc_account,v_doc_total
        FROM public.purchase s
       WHERE s.organization_id=p_organization_id AND s.id=v_alloc.document_id
       FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Payment allocation references a missing purchase' USING ERRCODE='23514'; END IF;
      IF NOT EXISTS(SELECT 1 FROM public.purchase s WHERE s.organization_id=p_organization_id AND s.id=v_alloc.document_id AND s.status='posted') THEN
        RAISE EXCEPTION 'Payment can only be allocated to a posted purchase' USING ERRCODE='23514';
      END IF;
      SELECT COALESCE(sum(r.total_amount),0) INTO v_returned
        FROM public.purchase_returns r
       WHERE r.organization_id=p_organization_id AND r.purchase_id=v_alloc.document_id AND r.status='posted';
      SELECT COALESCE(sum(pa.allocated_amount),0) INTO v_previously_allocated
        FROM public.payment_allocations pa
        JOIN public.payments p ON p.organization_id=pa.organization_id AND p.id=pa.payment_id
       WHERE pa.organization_id=p_organization_id AND pa.document_type='purchase'
         AND pa.document_id=v_alloc.document_id AND pa.payment_id<>p_payment_id
         AND p.payment_type='payment' AND p.status='posted';
    ELSE
      RAISE EXCEPTION 'Allocation document type does not match payment type' USING ERRCODE='23514';
    END IF;

    IF v_doc_contact IS DISTINCT FROM v_payment.contact_id
       OR v_doc_account IS DISTINCT FROM v_payment.account_id THEN
      RAISE EXCEPTION 'Allocation contact or control account does not match the source invoice' USING ERRCODE='23514';
    END IF;
    IF v_alloc.allocated_amount<=0
       OR v_alloc.allocated_amount>round(v_doc_total-v_returned-v_previously_allocated,4) THEN
      RAISE EXCEPTION 'Allocation exceeds the remaining invoice balance' USING ERRCODE='23514';
    END IF;
  END LOOP;

  PERFORM set_config('zero_erp.allow_workflow','on',true);
  INSERT INTO public.journal_entries(
    id,organization_id,entry_date,entry_type,status,reference_type,reference_id,
    description,created_by,created_at,updated_by,updated_at
  )
  VALUES(
    v_journal_id,p_organization_id,v_payment.payment_date,
    CASE WHEN v_payment.payment_type='receipt' THEN 'receipt' ELSE 'payment' END,
    'draft','payment',p_payment_id,
    COALESCE(v_payment.description,CASE WHEN v_payment.payment_type='receipt' THEN 'Customer receipt' ELSE 'Supplier payment' END),
    v_user_id,now(),v_user_id,now()
  );

  IF v_payment.payment_type='receipt' THEN
    INSERT INTO public.account_transactions(
      organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by
    ) VALUES
      (p_organization_id,v_journal_id,v_payment.settlement_account_id,1,'Cash/bank received',v_payment.amount,0,NULL,v_user_id,v_user_id),
      (p_organization_id,v_journal_id,v_payment.account_id,2,'Customer receivable settled',0,v_payment.amount,v_payment.contact_id,v_user_id,v_user_id);
  ELSE
    INSERT INTO public.account_transactions(
      organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by
    ) VALUES
      (p_organization_id,v_journal_id,v_payment.account_id,1,'Supplier payable settled',v_payment.amount,0,v_payment.contact_id,v_user_id,v_user_id),
      (p_organization_id,v_journal_id,v_payment.settlement_account_id,2,'Cash/bank paid',0,v_payment.amount,NULL,v_user_id,v_user_id);
  END IF;

  PERFORM public.post_journal_entry(p_organization_id,v_journal_id);

  UPDATE public.payments
     SET code=COALESCE(code,private.allocate_document_number(p_organization_id,'payments')),
         status='posted',confirmed_at=now(),confirmed_by=v_user_id,
         posted_by=v_user_id,posted_journal_entry_id=v_journal_id,
         updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_payment_id AND status='draft';
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment posting failed' USING ERRCODE='23514'; END IF;

  RETURN v_journal_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.post_payment(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.post_payment(uuid,uuid) TO authenticated;

COMMIT;
