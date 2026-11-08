-- ZERO ERP V1 control-account metadata acceptance test.
-- Validates receivable/payable account selection and mandatory contact dimensions.
BEGIN;
DO $setup$
DECLARE
  v_user uuid:=gen_random_uuid();
  v_org uuid;
  v_cash uuid;
  v_equity uuid;
  v_opening_journal uuid:=gen_random_uuid();
BEGIN
  INSERT INTO auth.users(id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  VALUES(v_user,'authenticated','authenticated','zero-control-'||v_user::text||'@example.invalid','','{}','{}',now(),now(),now());
  PERFORM set_config('request.jwt.claim.sub',v_user::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_user::text,'role','authenticated')::text,true);
  v_org:=public.create_organization('Control Account Metadata Test');
  SELECT id INTO v_cash FROM public.accounts WHERE organization_id=v_org AND code='1110';
  SELECT id INTO v_equity FROM public.accounts WHERE organization_id=v_org AND code='3200';
  INSERT INTO public.journal_entries(id,organization_id,entry_date,entry_type,status,description,created_by)
  VALUES(v_opening_journal,v_org,current_date,'opening_balance','draft','Setup opening balance',v_user);
  INSERT INTO public.account_transactions(organization_id,journal_entry_id,account_id,line_number,debit,credit,created_by)
  VALUES(v_org,v_opening_journal,v_cash,1,100,0,v_user),
        (v_org,v_opening_journal,v_equity,2,0,100,v_user);
  PERFORM public.complete_organization_setup(v_org,'[]'::jsonb,true);
  PERFORM set_config('zero_control.org',v_org::text,true);
  PERFORM set_config('zero_control.user',v_user::text,true);
END;
$setup$;

SET LOCAL ROLE authenticated;
DO $checks$
#variable_conflict use_variable
DECLARE
  v_org uuid:=current_setting('zero_control.org')::uuid;
  v_user uuid:=current_setting('zero_control.user')::uuid;
  v_customer uuid:=gen_random_uuid();
  v_cash uuid;
  v_receivable uuid;
  v_custom_receivable uuid;
  v_journal uuid:=gen_random_uuid();
  v_bad_account_rejected boolean:=false;
  v_missing_contact_rejected boolean:=false;
  v_custom_code text;
BEGIN
  SELECT id INTO v_cash FROM public.accounts WHERE organization_id=v_org AND code='1110';
  SELECT id INTO v_receivable FROM public.accounts WHERE organization_id=v_org AND code='1130';
  INSERT INTO public.contacts(id,organization_id,code,name,status,created_by)
  VALUES(v_customer,v_org,'CUS-CTRL-1','Control account test customer','active',v_user);

  BEGIN
    INSERT INTO public.sales(organization_id,customer_id,invoice_date,status,subtotal,discount_amount,total_amount,receivable_account_id,created_by)
    VALUES(v_org,v_customer,current_date,'draft',100,0,100,v_cash,v_user);
  EXCEPTION WHEN check_violation THEN v_bad_account_rejected:=true;
  END;
  IF NOT v_bad_account_rejected THEN
    RAISE EXCEPTION 'Cash account was accepted as a sales receivable control account';
  END IF;

  INSERT INTO public.journal_entries(id,organization_id,entry_date,entry_type,status,description,created_by)
  VALUES(v_journal,v_org,current_date,'manual','draft','Missing contact validation',v_user);
  BEGIN
    INSERT INTO public.account_transactions(organization_id,journal_entry_id,account_id,line_number,debit,credit,created_by)
    VALUES(v_org,v_journal,v_receivable,1,100,0,v_user);
  EXCEPTION WHEN check_violation THEN v_missing_contact_rejected:=true;
  END;
  IF NOT v_missing_contact_rejected THEN
    RAISE EXCEPTION 'Receivable ledger line without a contact was accepted';
  END IF;

  v_custom_code:=public.next_account_code(v_org,'asset');
  INSERT INTO public.accounts(organization_id,code,account_name,account_type,normal_balance,is_control_account,is_postable,requires_contact,status,created_by)
  VALUES(v_org,v_custom_code,'Custom Receivable Control','asset','debit',true,true,true,'active',v_user)
  RETURNING id INTO v_custom_receivable;
  INSERT INTO public.sales(organization_id,customer_id,invoice_date,status,subtotal,discount_amount,total_amount,receivable_account_id,created_by)
  VALUES(v_org,v_customer,current_date,'draft',100,0,100,v_custom_receivable,v_user);
END;
$checks$;
RESET ROLE;
ROLLBACK;

SELECT 'Control-account mapping and contact enforcement tests passed' AS result;
