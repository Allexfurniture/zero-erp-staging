-- ZERO ERP V1: prevent generic journal reversal from bypassing source-document ledgers.
BEGIN;

CREATE OR REPLACE FUNCTION public.reverse_journal_entry(
  p_organization_id uuid,
  p_journal_entry_id uuid,
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
  IF p_reversal_date IS NULL OR p_reason IS NULL OR btrim(p_reason)='' OR length(btrim(p_reason))>500 THEN
    RAISE EXCEPTION 'A reversal date and reason of 1-500 characters are required' USING ERRCODE='22023';
  END IF;
  SELECT o.status INTO v_org_status FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Journal reversal requires an active organization' USING ERRCODE='23514';
  END IF;

  SELECT j.* INTO v_original FROM public.journal_entries j
   WHERE j.organization_id=p_organization_id AND j.id=p_journal_entry_id
   FOR UPDATE;
  IF NOT FOUND OR v_original.status<>'posted' OR v_original.reversal_of_id IS NOT NULL
     OR v_original.reversal_journal_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Only an unreversed posted journal entry can be reversed' USING ERRCODE='23514';
  END IF;

  IF v_original.reference_type IS NOT NULL OR v_original.reference_id IS NOT NULL THEN
    RAISE EXCEPTION 'Referenced journals must be reversed through their source-document workflow'
      USING ERRCODE='23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.account_transactions t
     WHERE t.organization_id=p_organization_id AND t.journal_entry_id=p_journal_entry_id
  ) THEN
    RAISE EXCEPTION 'Journal entry has no lines to reverse' USING ERRCODE='23514';
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

REVOKE ALL ON FUNCTION public.reverse_journal_entry(uuid,uuid,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reverse_journal_entry(uuid,uuid,date,text) TO authenticated,service_role;

COMMIT;
