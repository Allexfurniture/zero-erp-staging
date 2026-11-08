-- ZERO ERP V1 database hardening smoke tests.
-- Run after applying the initial schema migration with psql or the Supabase SQL editor.
DO $tests$
DECLARE
  v_missing_rls text;
  v_def text;
  v_anon_definer_count integer;
BEGIN
  SELECT string_agg(format('%I.%I',n.nspname,c.relname), ', ')
    INTO v_missing_rls
    FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public'
     AND c.relkind IN ('r','p')
     AND NOT c.relrowsecurity;
  IF v_missing_rls IS NOT NULL THEN
    RAISE EXCEPTION 'RLS is disabled on public tables: %',v_missing_rls;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='public' AND table_name='organizations' AND column_name='owner_user_id'
  ) THEN
    RAISE EXCEPTION 'Organizations must have an explicit owner_user_id';
  END IF;

  SELECT pg_get_functiondef('private.is_org_creator(uuid)'::regprocedure) INTO v_def;
  IF position('owner_user_id' IN v_def)=0 THEN
    RAISE EXCEPTION 'Organization creator authorization must use owner_user_id';
  END IF;

  SELECT pg_get_functiondef('private.enforce_organization_scope_immutable()'::regprocedure) INTO v_def;
  IF position('organization_id is immutable' IN v_def)=0 THEN
    RAISE EXCEPTION 'Organization scope immutability guard is missing';
  END IF;

  SELECT pg_get_functiondef('private.enforce_draft_document()'::regprocedure) INTO v_def;
  IF position('reversal_of_id' IN v_def)=0 THEN
    RAISE EXCEPTION 'Draft document guard does not protect reversal_of_id';
  END IF;

  SELECT pg_get_functiondef('public.post_journal_entry(uuid,uuid)'::regprocedure) INTO v_def;
  IF position('exactly invert the original journal' IN v_def)=0 THEN
    RAISE EXCEPTION 'Journal posting does not verify exact reversal lines';
  END IF;

  SELECT pg_get_functiondef('public.next_document_number(uuid,text)'::regprocedure) INTO v_def;
  IF position('Only the organization creator may allocate account codes' IN v_def)=0 THEN
    RAISE EXCEPTION 'Account code sequence is not creator-restricted';
  END IF;

  SELECT pg_get_functiondef('public.complete_organization_setup(uuid,jsonb,boolean)'::regprocedure) INTO v_def;
  IF position('sum(round(x.quantity*x.unit_cost,4))' IN v_def)=0 THEN
    RAISE EXCEPTION 'Opening inventory rounding policy is inconsistent';
  END IF;

  SELECT pg_get_functiondef('public.post_expense(uuid,uuid)'::regprocedure) INTO v_def;
  IF position('Expense settlement account must be an asset' IN v_def)=0 THEN
    RAISE EXCEPTION 'Expense settlement account type is not validated';
  END IF;

  IF has_function_privilege('authenticated','public.next_document_number(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'Authenticated users can directly consume document-number sequences';
  END IF;

  SELECT count(*) INTO v_anon_definer_count
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.prosecdef
     AND has_function_privilege('anon',p.oid,'EXECUTE');
  IF v_anon_definer_count>0 THEN
    RAISE EXCEPTION 'Found % public SECURITY DEFINER functions executable by anon',v_anon_definer_count;
  END IF;
END;
$tests$;

SELECT 'ZERO ERP V1 hardening smoke tests passed' AS result;

-- End-to-end rollback fixture: organization provisioning, setup completion,
-- explicit ownership, and tenant-scope immutability.
BEGIN;
DO $integration$
DECLARE
  v_user uuid := gen_random_uuid();
  v_org uuid;
  v_second_org uuid;
  v_cash uuid;
  v_equity uuid;
  v_journal uuid := gen_random_uuid();
  v_contact uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users(id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  VALUES (v_user,'authenticated','authenticated','zero-erp-test-'||v_user::text||'@example.invalid','', '{}'::jsonb,'{}'::jsonb,now(),now(),now());

  PERFORM set_config('request.jwt.claim.sub',v_user::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_user::text,'role','authenticated')::text,true);

  v_org := public.create_organization('ZERO ERP integration rollback test');
  v_second_org := public.create_organization('ZERO ERP second rollback test');

  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id=v_org AND owner_user_id=v_user) THEN
    RAISE EXCEPTION 'Organization owner assignment failed';
  END IF;

  SELECT id INTO v_cash FROM public.accounts WHERE organization_id=v_org AND code='1110';
  SELECT id INTO v_equity FROM public.accounts WHERE organization_id=v_org AND code='3100';
  IF v_cash IS NULL OR v_equity IS NULL THEN
    RAISE EXCEPTION 'Default chart of accounts is incomplete';
  END IF;

  INSERT INTO public.journal_entries(id,organization_id,entry_date,entry_type,status,description,created_by)
  VALUES(v_journal,v_org,current_date,'opening_balance','draft','Integration opening journal',v_user);
  INSERT INTO public.account_transactions(organization_id,journal_entry_id,account_id,line_number,debit,credit,created_by)
  VALUES (v_org,v_journal,v_cash,1,100,0,v_user),(v_org,v_journal,v_equity,2,0,100,v_user);

  PERFORM public.complete_organization_setup(v_org,'[]'::jsonb,true);
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id=v_org AND status='active') THEN
    RAISE EXCEPTION 'Organization setup completion failed';
  END IF;

  INSERT INTO public.contacts(id,organization_id,code,name,status,created_by)
  VALUES(v_contact,v_org,private.allocate_document_number(v_org,'contacts'),'Tenant scope test','active',v_user);

  BEGIN
    UPDATE public.contacts SET organization_id=v_second_org WHERE id=v_contact;
    RAISE EXCEPTION 'Tenant scope mutation was not rejected';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    UPDATE public.organizations SET owner_user_id=gen_random_uuid() WHERE id=v_org;
    RAISE EXCEPTION 'Organization ownership mutation was not rejected';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END;
$integration$;
ROLLBACK;
