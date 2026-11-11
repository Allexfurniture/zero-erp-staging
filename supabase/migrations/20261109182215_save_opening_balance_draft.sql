CREATE OR REPLACE FUNCTION private.save_opening_balance_draft(
  p_organization_id uuid,
  p_entry_date date,
  p_description text,
  p_lines jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_org_status text;
  v_journal_id uuid;
  v_journal_status text;
  v_invalid_count bigint;
BEGIN
  IF v_user_id IS NULL OR NOT private.is_org_creator(p_organization_id) THEN
    RAISE EXCEPTION 'Only the organization creator can save opening balances'
      USING ERRCODE='42501';
  END IF;
  IF p_entry_date IS NULL THEN
    RAISE EXCEPTION 'Opening balance date is required' USING ERRCODE='22023';
  END IF;
  IF p_description IS NOT NULL AND length(btrim(p_description))>500 THEN
    RAISE EXCEPTION 'Opening balance description is too long' USING ERRCODE='22023';
  END IF;
  IF p_lines IS NULL OR jsonb_typeof(p_lines) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Opening journal lines must be a JSON array' USING ERRCODE='22023';
  END IF;
  IF jsonb_array_length(p_lines)>500 THEN
    RAISE EXCEPTION 'Opening journal cannot contain more than 500 lines' USING ERRCODE='22023';
  END IF;

  SELECT o.status INTO v_org_status
    FROM public.organizations o
   WHERE o.id=p_organization_id
   FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'configuring' THEN
    RAISE EXCEPTION 'Organization is not in configuring state' USING ERRCODE='23514';
  END IF;

  SELECT j.id,j.status INTO v_journal_id,v_journal_status
    FROM public.journal_entries j
   WHERE j.organization_id=p_organization_id
     AND j.entry_type='opening_balance'
   FOR UPDATE;
  IF v_journal_id IS NOT NULL AND v_journal_status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'Opening balance journal is already locked' USING ERRCODE='23514';
  END IF;

  SELECT count(*) INTO v_invalid_count
    FROM jsonb_to_recordset(p_lines) AS x(
      account_id uuid,debit numeric(20,4),credit numeric(20,4),
      contact_id uuid,description text
    )
    LEFT JOIN public.accounts a
      ON a.organization_id=p_organization_id AND a.id=x.account_id
    LEFT JOIN public.contacts c
      ON c.organization_id=p_organization_id AND c.id=x.contact_id
   WHERE x.account_id IS NULL
      OR x.debit IS NULL OR x.credit IS NULL
      OR x.debit::text='NaN' OR x.credit::text='NaN'
      OR x.debit<0 OR x.credit<0
      OR (x.debit=0 AND x.credit=0)
      OR (x.debit>0 AND x.credit>0)
      OR a.id IS NULL OR a.status<>'active' OR NOT a.is_postable
      OR (a.code IN ('1130','2110') AND (
        x.contact_id IS NULL OR c.id IS NULL OR c.status IS DISTINCT FROM 'active'
      ))
      OR (a.code='1140' AND (x.debit<=0 OR x.credit<>0))
      OR (x.contact_id IS NOT NULL AND (
        c.id IS NULL OR c.status IS DISTINCT FROM 'active'
      ));
  IF v_invalid_count>0 THEN
    RAISE EXCEPTION 'Opening journal contains invalid accounts, amounts or contact assignments'
      USING ERRCODE='23514';
  END IF;

  IF v_journal_id IS NULL THEN
    INSERT INTO public.journal_entries(
      organization_id,entry_date,entry_type,status,description,created_by,updated_by
    )
    VALUES(
      p_organization_id,p_entry_date,'opening_balance','draft',
      NULLIF(btrim(p_description),''),v_user_id,v_user_id
    )
    RETURNING id INTO v_journal_id;
  ELSE
    DELETE FROM public.account_transactions
     WHERE organization_id=p_organization_id AND journal_entry_id=v_journal_id;
    UPDATE public.journal_entries
       SET entry_date=p_entry_date,description=NULLIF(btrim(p_description),''),
           updated_by=v_user_id,updated_at=now()
     WHERE organization_id=p_organization_id AND id=v_journal_id AND status='draft';
  END IF;

  INSERT INTO public.account_transactions(
    organization_id,journal_entry_id,account_id,line_number,description,
    debit,credit,contact_id,created_by,updated_by
  )
  SELECT p_organization_id,v_journal_id,x.account_id,x.ordinality::integer,
         NULLIF(btrim(x.description),''),x.debit,x.credit,x.contact_id,v_user_id,v_user_id
    FROM jsonb_to_recordset(p_lines) WITH ORDINALITY AS x(
      account_id uuid,debit numeric(20,4),credit numeric(20,4),
      contact_id uuid,description text,ordinality bigint
    )
   ORDER BY x.ordinality;
  RETURN v_journal_id;
END;
$function$;

REVOKE ALL ON FUNCTION private.save_opening_balance_draft(uuid,date,text,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.save_opening_balance_draft(uuid,date,text,jsonb)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.save_opening_balance_draft(
  p_organization_id uuid,p_entry_date date,p_description text,p_lines jsonb
)
RETURNS uuid
LANGUAGE sql
SET search_path = ''
AS $function$
  SELECT private.save_opening_balance_draft($1,$2,$3,$4)
$function$;

REVOKE ALL ON FUNCTION public.save_opening_balance_draft(uuid,date,text,jsonb)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_opening_balance_draft(uuid,date,text,jsonb)
  TO authenticated;
