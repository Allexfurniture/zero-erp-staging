-- ZERO ERP V1: opening receivable/payable subledger and payment allocation.
BEGIN;

CREATE TABLE public.opening_balance_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  opening_journal_entry_id uuid NOT NULL,
  opening_journal_line_id uuid NOT NULL UNIQUE,
  account_id uuid NOT NULL,
  contact_id uuid NOT NULL,
  balance_type text NOT NULL CHECK (balance_type IN ('receivable','payable')),
  description text,
  opening_date date NOT NULL,
  original_amount numeric(20,4) NOT NULL CHECK (original_amount > 0),
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT opening_balance_items_org_fk
    FOREIGN KEY (organization_id) REFERENCES public.organizations(id),
  CONSTRAINT opening_balance_items_journal_fk
    FOREIGN KEY (organization_id,opening_journal_entry_id)
    REFERENCES public.journal_entries(organization_id,id),
  CONSTRAINT opening_balance_items_line_fk
    FOREIGN KEY (opening_journal_line_id) REFERENCES public.account_transactions(id),
  CONSTRAINT opening_balance_items_account_fk
    FOREIGN KEY (organization_id,account_id) REFERENCES public.accounts(organization_id,id),
  CONSTRAINT opening_balance_items_contact_fk
    FOREIGN KEY (organization_id,contact_id) REFERENCES public.contacts(organization_id,id)
);

CREATE INDEX opening_balance_items_contact_idx
  ON public.opening_balance_items(organization_id,contact_id,balance_type);
CREATE INDEX opening_balance_items_journal_idx
  ON public.opening_balance_items(organization_id,opening_journal_entry_id);

ALTER TABLE public.opening_balance_items ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.opening_balance_items TO authenticated;
CREATE POLICY opening_balance_items_member_select
  ON public.opening_balance_items FOR SELECT TO authenticated
  USING (private.is_org_member(organization_id) OR private.is_org_creator(organization_id));

CREATE OR REPLACE FUNCTION private.materialize_opening_balance_items()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.entry_type='opening_balance' AND OLD.status='draft' AND NEW.status='posted' THEN
    IF EXISTS (
      SELECT 1
        FROM public.account_transactions t
        JOIN public.accounts a ON a.organization_id=t.organization_id AND a.id=t.account_id
        LEFT JOIN public.contacts c ON c.organization_id=t.organization_id AND c.id=t.contact_id
       WHERE t.organization_id=NEW.organization_id AND t.journal_entry_id=NEW.id
         AND (
           (a.code='1130' AND (t.debit<=0 OR t.credit<>0 OR c.status IS DISTINCT FROM 'active'))
           OR
           (a.code='2110' AND (t.credit<=0 OR t.debit<>0 OR c.status IS DISTINCT FROM 'active'))
         )
    ) THEN
      RAISE EXCEPTION 'Opening receivable lines must be debit balances and opening payable lines must be credit balances for active contacts'
        USING ERRCODE='23514';
    END IF;

    INSERT INTO public.opening_balance_items(
      organization_id,opening_journal_entry_id,opening_journal_line_id,
      account_id,contact_id,balance_type,description,opening_date,original_amount,created_by
    )
    SELECT t.organization_id,NEW.id,t.id,t.account_id,t.contact_id,'receivable',
           t.description,NEW.entry_date,t.debit,t.created_by
      FROM public.account_transactions t
      JOIN public.accounts a ON a.organization_id=t.organization_id AND a.id=t.account_id
     WHERE t.organization_id=NEW.organization_id AND t.journal_entry_id=NEW.id
       AND a.code='1130' AND t.debit>0 AND t.credit=0;

    INSERT INTO public.opening_balance_items(
      organization_id,opening_journal_entry_id,opening_journal_line_id,
      account_id,contact_id,balance_type,description,opening_date,original_amount,created_by
    )
    SELECT t.organization_id,NEW.id,t.id,t.account_id,t.contact_id,'payable',
           t.description,NEW.entry_date,t.credit,t.created_by
      FROM public.account_transactions t
      JOIN public.accounts a ON a.organization_id=t.organization_id AND a.id=t.account_id
     WHERE t.organization_id=NEW.organization_id AND t.journal_entry_id=NEW.id
       AND a.code='2110' AND t.credit>0 AND t.debit=0;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.materialize_opening_balance_items() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER journal_entries_materialize_opening_balances
AFTER UPDATE OF status ON public.journal_entries
FOR EACH ROW
EXECUTE FUNCTION private.materialize_opening_balance_items();

ALTER TABLE public.payment_allocations
  DROP CONSTRAINT payment_allocations_document_type_check;
ALTER TABLE public.payment_allocations
  ADD CONSTRAINT payment_allocations_document_type_check
  CHECK (document_type IN ('sales','purchase','opening_balance'));

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
  v_doc_balance_type text;
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  SELECT o.status INTO v_org_status FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'active' THEN RAISE EXCEPTION 'Payment posting requires an active organization' USING ERRCODE='23514'; END IF;

  SELECT p.* INTO v_payment FROM public.payments p
   WHERE p.organization_id=p_organization_id AND p.id=p_payment_id FOR UPDATE;
  IF NOT FOUND OR v_payment.status<>'draft' OR v_payment.posted_journal_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Payment not found, not draft, or already posted' USING ERRCODE='23514';
  END IF;
  IF v_payment.payment_type NOT IN ('receipt','payment') THEN RAISE EXCEPTION 'Payment type must be receipt or payment' USING ERRCODE='23514'; END IF;
  IF v_payment.amount<=0 OR v_payment.contact_id IS NULL OR v_payment.settlement_account_id IS NULL THEN
    RAISE EXCEPTION 'Payment requires a positive amount, contact, and settlement account' USING ERRCODE='23514';
  END IF;

  SELECT a.account_type INTO v_account_type FROM public.accounts a
   WHERE a.organization_id=p_organization_id AND a.id=v_payment.account_id
     AND a.status='active' AND a.is_postable;
  IF (v_payment.payment_type='receipt' AND v_account_type IS DISTINCT FROM 'asset')
     OR (v_payment.payment_type='payment' AND v_account_type IS DISTINCT FROM 'liability') THEN
    RAISE EXCEPTION 'Receipt requires an active postable receivable asset account; payment requires an active postable payable liability account' USING ERRCODE='23514';
  END IF;

  SELECT a.account_type INTO v_settlement_type FROM public.accounts a
   WHERE a.organization_id=p_organization_id AND a.id=v_payment.settlement_account_id
     AND a.status='active' AND a.is_postable;
  IF v_settlement_type IS DISTINCT FROM 'asset' THEN RAISE EXCEPTION 'Settlement account must be an active postable asset account' USING ERRCODE='23514'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.contacts c WHERE c.organization_id=p_organization_id AND c.id=v_payment.contact_id AND c.status='active') THEN
    RAISE EXCEPTION 'Payment contact is missing or inactive' USING ERRCODE='23514';
  END IF;

  SELECT COALESCE(sum(pa.allocated_amount),0) INTO v_allocated_total
    FROM public.payment_allocations pa WHERE pa.organization_id=p_organization_id AND pa.payment_id=p_payment_id;
  IF v_allocated_total>v_payment.amount THEN RAISE EXCEPTION 'Payment allocations exceed payment amount' USING ERRCODE='23514'; END IF;

  FOR v_alloc IN
    SELECT pa.document_type,pa.document_id,pa.allocated_amount
      FROM public.payment_allocations pa
     WHERE pa.organization_id=p_organization_id AND pa.payment_id=p_payment_id
     ORDER BY pa.document_type,pa.document_id
  LOOP
    v_returned:=0;
    v_previously_allocated:=0;
    v_doc_balance_type:=NULL;

    IF v_payment.payment_type='receipt' AND v_alloc.document_type='sales' THEN
      SELECT s.customer_id,s.receivable_account_id,s.total_amount
        INTO v_doc_contact,v_doc_account,v_doc_total
        FROM public.sales s WHERE s.organization_id=p_organization_id AND s.id=v_alloc.document_id FOR UPDATE;
      IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.sales s WHERE s.organization_id=p_organization_id AND s.id=v_alloc.document_id AND s.status='posted') THEN
        RAISE EXCEPTION 'Receipt allocation must reference a posted sale' USING ERRCODE='23514';
      END IF;
      SELECT COALESCE(sum(r.total_amount),0) INTO v_returned FROM public.sales_returns r
       WHERE r.organization_id=p_organization_id AND r.sales_id=v_alloc.document_id AND r.status='posted';
      SELECT COALESCE(sum(pa.allocated_amount),0) INTO v_previously_allocated
        FROM public.payment_allocations pa JOIN public.payments p ON p.organization_id=pa.organization_id AND p.id=pa.payment_id
       WHERE pa.organization_id=p_organization_id AND pa.document_type='sales' AND pa.document_id=v_alloc.document_id
         AND pa.payment_id<>p_payment_id AND p.payment_type='receipt' AND p.status='posted';

    ELSIF v_payment.payment_type='payment' AND v_alloc.document_type='purchase' THEN
      SELECT s.supplier_id,s.payable_account_id,s.total_amount
        INTO v_doc_contact,v_doc_account,v_doc_total
        FROM public.purchase s WHERE s.organization_id=p_organization_id AND s.id=v_alloc.document_id FOR UPDATE;
      IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.purchase s WHERE s.organization_id=p_organization_id AND s.id=v_alloc.document_id AND s.status='posted') THEN
        RAISE EXCEPTION 'Payment allocation must reference a posted purchase' USING ERRCODE='23514';
      END IF;
      SELECT COALESCE(sum(r.total_amount),0) INTO v_returned FROM public.purchase_returns r
       WHERE r.organization_id=p_organization_id AND r.purchase_id=v_alloc.document_id AND r.status='posted';
      SELECT COALESCE(sum(pa.allocated_amount),0) INTO v_previously_allocated
        FROM public.payment_allocations pa JOIN public.payments p ON p.organization_id=pa.organization_id AND p.id=pa.payment_id
       WHERE pa.organization_id=p_organization_id AND pa.document_type='purchase' AND pa.document_id=v_alloc.document_id
         AND pa.payment_id<>p_payment_id AND p.payment_type='payment' AND p.status='posted';

    ELSIF v_payment.payment_type='receipt' AND v_alloc.document_type='opening_balance' THEN
      SELECT ob.contact_id,ob.account_id,ob.original_amount,ob.balance_type
        INTO v_doc_contact,v_doc_account,v_doc_total,v_doc_balance_type
        FROM public.opening_balance_items ob
       WHERE ob.organization_id=p_organization_id AND ob.id=v_alloc.document_id FOR UPDATE;
      IF NOT FOUND OR v_doc_balance_type IS DISTINCT FROM 'receivable' THEN
        RAISE EXCEPTION 'Receipt allocation must reference an opening receivable balance' USING ERRCODE='23514';
      END IF;
      SELECT COALESCE(sum(pa.allocated_amount),0) INTO v_previously_allocated
        FROM public.payment_allocations pa JOIN public.payments p ON p.organization_id=pa.organization_id AND p.id=pa.payment_id
       WHERE pa.organization_id=p_organization_id AND pa.document_type='opening_balance' AND pa.document_id=v_alloc.document_id
         AND pa.payment_id<>p_payment_id AND p.payment_type='receipt' AND p.status='posted';

    ELSIF v_payment.payment_type='payment' AND v_alloc.document_type='opening_balance' THEN
      SELECT ob.contact_id,ob.account_id,ob.original_amount,ob.balance_type
        INTO v_doc_contact,v_doc_account,v_doc_total,v_doc_balance_type
        FROM public.opening_balance_items ob
       WHERE ob.organization_id=p_organization_id AND ob.id=v_alloc.document_id FOR UPDATE;
      IF NOT FOUND OR v_doc_balance_type IS DISTINCT FROM 'payable' THEN
        RAISE EXCEPTION 'Supplier payment allocation must reference an opening payable balance' USING ERRCODE='23514';
      END IF;
      SELECT COALESCE(sum(pa.allocated_amount),0) INTO v_previously_allocated
        FROM public.payment_allocations pa JOIN public.payments p ON p.organization_id=pa.organization_id AND p.id=pa.payment_id
       WHERE pa.organization_id=p_organization_id AND pa.document_type='opening_balance' AND pa.document_id=v_alloc.document_id
         AND pa.payment_id<>p_payment_id AND p.payment_type='payment' AND p.status='posted';
    ELSE
      RAISE EXCEPTION 'Allocation document type does not match payment type' USING ERRCODE='23514';
    END IF;

    IF v_doc_contact IS DISTINCT FROM v_payment.contact_id OR v_doc_account IS DISTINCT FROM v_payment.account_id THEN
      RAISE EXCEPTION 'Allocation contact or control account does not match source balance' USING ERRCODE='23514';
    END IF;
    IF v_alloc.allocated_amount<=0 OR v_alloc.allocated_amount>round(v_doc_total-v_returned-v_previously_allocated,4) THEN
      RAISE EXCEPTION 'Allocation exceeds remaining invoice/opening balance' USING ERRCODE='23514';
    END IF;
  END LOOP;

  PERFORM set_config('zero_erp.allow_workflow','on',true);
  INSERT INTO public.journal_entries(id,organization_id,entry_date,entry_type,status,reference_type,reference_id,description,created_by,created_at,updated_by,updated_at)
  VALUES(v_journal_id,p_organization_id,v_payment.payment_date,
    CASE WHEN v_payment.payment_type='receipt' THEN 'receipt' ELSE 'payment' END,
    'draft','payment',p_payment_id,
    COALESCE(v_payment.description,CASE WHEN v_payment.payment_type='receipt' THEN 'Customer receipt' ELSE 'Supplier payment' END),
    v_user_id,now(),v_user_id,now());

  IF v_payment.payment_type='receipt' THEN
    INSERT INTO public.account_transactions(organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by)
    VALUES(p_organization_id,v_journal_id,v_payment.settlement_account_id,1,'Cash/bank received',v_payment.amount,0,NULL,v_user_id,v_user_id),
          (p_organization_id,v_journal_id,v_payment.account_id,2,'Customer receivable settled',0,v_payment.amount,v_payment.contact_id,v_user_id,v_user_id);
  ELSE
    INSERT INTO public.account_transactions(organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by)
    VALUES(p_organization_id,v_journal_id,v_payment.account_id,1,'Supplier payable settled',v_payment.amount,0,v_payment.contact_id,v_user_id,v_user_id),
          (p_organization_id,v_journal_id,v_payment.settlement_account_id,2,'Cash/bank paid',0,v_payment.amount,NULL,v_user_id,v_user_id);
  END IF;

  PERFORM public.post_journal_entry(p_organization_id,v_journal_id);
  UPDATE public.payments SET code=COALESCE(code,private.allocate_document_number(p_organization_id,'payments')),
    status='posted',confirmed_at=now(),confirmed_by=v_user_id,posted_by=v_user_id,posted_journal_entry_id=v_journal_id,
    updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_payment_id AND status='draft';
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment posting failed' USING ERRCODE='23514'; END IF;
  RETURN v_journal_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.post_payment(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.post_payment(uuid,uuid) TO authenticated;

COMMIT;