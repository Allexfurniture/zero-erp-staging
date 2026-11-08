-- ZERO ERP V1: source-aware reversals for payments and expenses.
BEGIN;

CREATE OR REPLACE FUNCTION private.reverse_source_journal(
  p_organization_id uuid,
  p_journal_entry_id uuid,
  p_source_type text,
  p_source_id uuid,
  p_reversal_date date,
  p_reason text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid:=auth.uid();
  v_org_status text;
  v_original public.journal_entries%ROWTYPE;
  v_reversal_id uuid:=gen_random_uuid();
  v_reversal_code text;
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  PERFORM o.id FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization not found' USING ERRCODE='23503'; END IF;
  IF p_reversal_date IS NULL OR p_reason IS NULL OR btrim(p_reason)='' OR length(btrim(p_reason))>500 THEN
    RAISE EXCEPTION 'A reversal date and reason of 1-500 characters are required' USING ERRCODE='22023';
  END IF;
  IF p_source_type NOT IN ('payment','expense') OR p_source_id IS NULL THEN
    RAISE EXCEPTION 'Unsupported source document reversal type' USING ERRCODE='22023';
  END IF;

  SELECT o.status INTO v_org_status FROM public.organizations o
   WHERE o.id=p_organization_id FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Source document reversal requires an active organization' USING ERRCODE='23514';
  END IF;

  SELECT j.* INTO v_original FROM public.journal_entries j
   WHERE j.organization_id=p_organization_id AND j.id=p_journal_entry_id FOR UPDATE;
  IF NOT FOUND OR v_original.status<>'posted'
     OR v_original.reversal_of_id IS NOT NULL
     OR v_original.reversal_journal_entry_id IS NOT NULL
     OR v_original.reference_type IS DISTINCT FROM p_source_type
     OR v_original.reference_id IS DISTINCT FROM p_source_id THEN
    RAISE EXCEPTION 'Source journal is missing, already reversed, or does not match the source document' USING ERRCODE='23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.account_transactions t
     WHERE t.organization_id=p_organization_id AND t.journal_entry_id=p_journal_entry_id
  ) THEN
    RAISE EXCEPTION 'Source journal has no lines to reverse' USING ERRCODE='23514';
  END IF;

  PERFORM set_config('zero_erp.allow_workflow','on',true);
  v_reversal_code:=private.allocate_document_number(p_organization_id,'journal_entries');
  INSERT INTO public.journal_entries(
    id,organization_id,code,entry_date,entry_type,status,reference_type,reference_id,
    description,reversal_of_id,reversal_reason,created_by,created_at,updated_by,updated_at
  )
  VALUES(
    v_reversal_id,p_organization_id,v_reversal_code,p_reversal_date,'reversal','draft',
    'journal_entry',v_original.id,
    'Reversal of '||COALESCE(v_original.code,v_original.id::text),
    v_original.id,btrim(p_reason),v_user_id,now(),v_user_id,now()
  );

  INSERT INTO public.account_transactions(
    organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by
  )
  SELECT t.organization_id,v_reversal_id,t.account_id,
         row_number() OVER (ORDER BY t.line_number,t.id)::integer,
         t.description,t.credit,t.debit,t.contact_id,v_user_id,v_user_id
    FROM public.account_transactions t
   WHERE t.organization_id=p_organization_id AND t.journal_entry_id=p_journal_entry_id;

  PERFORM public.post_journal_entry(p_organization_id,v_reversal_id);

  UPDATE public.journal_entries
     SET reversal_journal_entry_id=v_reversal_id,reversed_at=now(),
         reversed_by=v_user_id,reversal_reason=btrim(p_reason),
         updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_journal_entry_id;

  RETURN v_reversal_id;
END;
$function$;
REVOKE ALL ON FUNCTION private.reverse_source_journal(uuid,uuid,text,uuid,date,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.reverse_payment(
  p_organization_id uuid,p_payment_id uuid,p_reversal_date date,p_reason text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid:=auth.uid();
  v_payment public.payments%ROWTYPE;
  v_reversal_id uuid;
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  PERFORM o.id FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization not found' USING ERRCODE='23503'; END IF;
  SELECT p.* INTO v_payment FROM public.payments p
   WHERE p.organization_id=p_organization_id AND p.id=p_payment_id FOR UPDATE;
  IF NOT FOUND OR v_payment.status<>'posted' OR v_payment.reversal_journal_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Only an unreversed posted payment can be reversed' USING ERRCODE='23514';
  END IF;

  v_reversal_id:=private.reverse_source_journal(
    p_organization_id,v_payment.posted_journal_entry_id,'payment',p_payment_id,p_reversal_date,p_reason
  );
  PERFORM set_config('zero_erp.allow_workflow','on',true);
  UPDATE public.payments
     SET status='reversed',reversal_journal_entry_id=v_reversal_id,
         reversed_at=now(),reversed_by=v_user_id,reversal_reason=btrim(p_reason),
         updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_payment_id AND status='posted';
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment reversal metadata could not be finalized' USING ERRCODE='23514'; END IF;
  RETURN v_reversal_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.reverse_payment(uuid,uuid,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reverse_payment(uuid,uuid,date,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reverse_expense(
  p_organization_id uuid,p_expense_id uuid,p_reversal_date date,p_reason text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid:=auth.uid();
  v_expense public.expenses%ROWTYPE;
  v_reversal_id uuid;
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  PERFORM o.id FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization not found' USING ERRCODE='23503'; END IF;
  SELECT e.* INTO v_expense FROM public.expenses e
   WHERE e.organization_id=p_organization_id AND e.id=p_expense_id FOR UPDATE;
  IF NOT FOUND OR v_expense.status<>'posted' OR v_expense.reversal_journal_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Only an unreversed posted expense can be reversed' USING ERRCODE='23514';
  END IF;

  v_reversal_id:=private.reverse_source_journal(
    p_organization_id,v_expense.posted_journal_entry_id,'expense',p_expense_id,p_reversal_date,p_reason
  );
  PERFORM set_config('zero_erp.allow_workflow','on',true);
  UPDATE public.expenses
     SET status='reversed',reversal_journal_entry_id=v_reversal_id,
         reversed_at=now(),reversed_by=v_user_id,reversal_reason=btrim(p_reason),
         updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_expense_id AND status='posted';
  IF NOT FOUND THEN RAISE EXCEPTION 'Expense reversal metadata could not be finalized' USING ERRCODE='23514'; END IF;
  RETURN v_reversal_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.reverse_expense(uuid,uuid,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reverse_expense(uuid,uuid,date,text) TO authenticated;

COMMIT;