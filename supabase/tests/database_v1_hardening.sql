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

  IF to_regprocedure('public.post_purchase(uuid,uuid)') IS NULL
     OR to_regprocedure('public.post_sales(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Purchase and sales posting RPCs must be installed';
  END IF;

  SELECT pg_get_functiondef('private.purchase_net_lines(uuid,uuid)'::regprocedure) INTO v_def;
  IF position('discount_units' IN v_def)=0 THEN
    RAISE EXCEPTION 'Purchase discount allocation must use exact currency units';
  END IF;
  SELECT pg_get_functiondef('private.sales_net_lines(uuid,uuid)'::regprocedure) INTO v_def;
  IF position('discount_units' IN v_def)=0 THEN
    RAISE EXCEPTION 'Sales discount allocation must use exact currency units';
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

  SELECT pg_get_functiondef('public.reverse_journal_entry(uuid,uuid,date,text)'::regprocedure) INTO v_def;
  IF position('source-document workflow' IN v_def)=0 THEN
    RAISE EXCEPTION 'Generic journal reversal must reject referenced source-document journals';
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
  EXCEPTION WHEN SQLSTATE '22000' THEN
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


-- Atomic purchase/sales posting integration test. All test rows are rolled back.
BEGIN;
DO $posting_integration$
DECLARE
  v_user uuid:=gen_random_uuid();
  v_org uuid;
  v_cash uuid;
  v_equity uuid;
  v_inventory uuid;
  v_payable uuid;
  v_receivable uuid;
  v_revenue uuid;
  v_cogs uuid;
  v_uom uuid:=gen_random_uuid();
  v_supplier uuid:=gen_random_uuid();
  v_customer uuid:=gen_random_uuid();
  v_product uuid:=gen_random_uuid();
  v_precision_product uuid:=gen_random_uuid();
  v_opening uuid:=gen_random_uuid();
  v_purchase uuid:=gen_random_uuid();
  v_purchase_journal uuid;
  v_sale uuid:=gen_random_uuid();
  v_sales_journal uuid;
  v_overstock_sale uuid:=gen_random_uuid();
  v_failed boolean:=false;
  v_qty numeric;
  v_value numeric;
  v_cogs_total numeric;
  v_precision_qty numeric(20,6):=1.1234567::numeric(20,6);
  v_precision_cost numeric(20,6):=2.1234567::numeric(20,6);
  v_precision_value numeric(20,4);
BEGIN
  INSERT INTO auth.users(id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  VALUES(v_user,'authenticated','authenticated','zero-workflow-'||v_user::text||'@example.invalid','','{}','{}',now(),now(),now());
  PERFORM set_config('request.jwt.claim.sub',v_user::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_user::text,'role','authenticated')::text,true);

  v_org:=public.create_organization('ZERO ERP posting workflow rollback test');
  SELECT id INTO v_cash FROM public.accounts WHERE organization_id=v_org AND code='1110';
  SELECT id INTO v_equity FROM public.accounts WHERE organization_id=v_org AND code='3100';
  SELECT id INTO v_inventory FROM public.accounts WHERE organization_id=v_org AND code='1140';
  SELECT id INTO v_payable FROM public.accounts WHERE organization_id=v_org AND code='2110';
  SELECT id INTO v_receivable FROM public.accounts WHERE organization_id=v_org AND code='1130';
  SELECT id INTO v_revenue FROM public.accounts WHERE organization_id=v_org AND code='4100';
  SELECT id INTO v_cogs FROM public.accounts WHERE organization_id=v_org AND code='5100';

  INSERT INTO public.units_of_measure(id,organization_id,name,status,created_by)
  VALUES(v_uom,v_org,'Piece','active',v_user);
  INSERT INTO public.products(id,organization_id,code,name,unit_id,inventory_account_id,sales_account_id,cogs_account_id,status,created_by)
  VALUES(v_precision_product,v_org,private.allocate_document_number(v_org,'products'),'Precision Product',v_uom,v_inventory,v_revenue,v_cogs,true,v_user);

  v_precision_value:=round(v_precision_qty*v_precision_cost,4);
  INSERT INTO public.journal_entries(id,organization_id,entry_date,entry_type,status,description,created_by)
  VALUES(v_opening,v_org,current_date,'opening_balance','draft','Opening inventory precision test',v_user);
  INSERT INTO public.account_transactions(organization_id,journal_entry_id,account_id,line_number,debit,credit,created_by)
  VALUES(v_org,v_opening,v_inventory,1,v_precision_value,0,v_user),(v_org,v_opening,v_equity,2,0,v_precision_value,v_user);
  PERFORM public.complete_organization_setup(
    v_org,
    jsonb_build_array(jsonb_build_object('product_id',v_precision_product,'quantity',1.1234567,'unit_cost',2.1234567)),
    false
  );
  IF NOT EXISTS(
    SELECT 1 FROM public.inventory_balances
     WHERE organization_id=v_org AND product_id=v_precision_product
       AND quantity=v_precision_qty AND inventory_value=v_precision_value
  ) THEN
    RAISE EXCEPTION 'Opening inventory precision was not normalized consistently';
  END IF;
  INSERT INTO public.contacts(id,organization_id,code,name,status,created_by)
  VALUES
    (v_supplier,v_org,private.allocate_document_number(v_org,'contacts'),'Smoke Supplier','active',v_user),
    (v_customer,v_org,private.allocate_document_number(v_org,'contacts'),'Smoke Customer','active',v_user);
  INSERT INTO public.products(id,organization_id,code,name,unit_id,inventory_account_id,sales_account_id,cogs_account_id,status,created_by)
  VALUES(v_product,v_org,private.allocate_document_number(v_org,'products'),'Smoke Product',v_uom,v_inventory,v_revenue,v_cogs,true,v_user);

  INSERT INTO public.purchase(id,organization_id,supplier_id,invoice_date,status,subtotal,discount_amount,total_amount,payable_account_id,created_by)
  VALUES(v_purchase,v_org,v_supplier,current_date,'draft',100,10,90,v_payable,v_user);
  INSERT INTO public.purchase_items(organization_id,purchase_id,line_number,product_id,quantity,unit_cost,line_total,created_by)
  VALUES(v_org,v_purchase,1,v_product,10,10,100,v_user);

  v_purchase_journal:=public.post_purchase(v_org,v_purchase);
  IF NOT EXISTS(SELECT 1 FROM public.purchase WHERE id=v_purchase AND status='posted' AND posted_journal_entry_id=v_purchase_journal) THEN
    RAISE EXCEPTION 'Purchase posting did not finalize source document';
  END IF;

  v_failed:=false;
  BEGIN
    PERFORM public.reverse_journal_entry(v_org,v_purchase_journal,current_date,'Should use purchase workflow');
  EXCEPTION WHEN check_violation THEN
    v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Generic reversal was allowed for a purchase journal'; END IF;
  SELECT quantity,inventory_value INTO v_qty,v_value FROM public.inventory_balances WHERE organization_id=v_org AND product_id=v_product;
  IF v_qty<>10 OR v_value<>90 THEN
    RAISE EXCEPTION 'Purchase inventory balance incorrect: quantity %, value %',v_qty,v_value;
  END IF;

  INSERT INTO public.sales(id,organization_id,customer_id,invoice_date,status,subtotal,discount_amount,total_amount,receivable_account_id,created_by)
  VALUES(v_sale,v_org,v_customer,current_date,'draft',80,0,80,v_receivable,v_user);
  INSERT INTO public.sales_items(organization_id,sales_id,line_number,product_id,quantity,unit_price,line_total,created_by)
  VALUES(v_org,v_sale,1,v_product,4,20,80,v_user);

  v_sales_journal:=public.post_sales(v_org,v_sale);
  IF NOT EXISTS(SELECT 1 FROM public.sales WHERE id=v_sale AND status='posted' AND posted_journal_entry_id=v_sales_journal) THEN
    RAISE EXCEPTION 'Sales posting did not finalize source document';
  END IF;
  SELECT quantity,inventory_value INTO v_qty,v_value FROM public.inventory_balances WHERE organization_id=v_org AND product_id=v_product;
  IF v_qty<>6 OR v_value<>54 THEN
    RAISE EXCEPTION 'Sales inventory balance incorrect: quantity %, value %',v_qty,v_value;
  END IF;
  SELECT cogs_total INTO v_cogs_total FROM public.sales_items WHERE organization_id=v_org AND sales_id=v_sale;
  IF v_cogs_total<>36 THEN
    RAISE EXCEPTION 'Sales COGS incorrect: %',v_cogs_total;
  END IF;

  INSERT INTO public.sales(id,organization_id,customer_id,invoice_date,status,subtotal,discount_amount,total_amount,receivable_account_id,created_by)
  VALUES(v_overstock_sale,v_org,v_customer,current_date,'draft',1000,0,1000,v_receivable,v_user);
  INSERT INTO public.sales_items(organization_id,sales_id,line_number,product_id,quantity,unit_price,line_total,created_by)
  VALUES(v_org,v_overstock_sale,1,v_product,100,10,1000,v_user);
  BEGIN
    PERFORM public.post_sales(v_org,v_overstock_sale);
  EXCEPTION WHEN check_violation THEN
    v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Overstock sale was not rejected'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.sales WHERE id=v_overstock_sale AND status='draft' AND posted_journal_entry_id IS NULL) THEN
    RAISE EXCEPTION 'Failed sale was not rolled back to draft';
  END IF;

  -- Generic reversal remains available for an unreferenced manual journal.
  DECLARE
    v_manual_id uuid:=gen_random_uuid();
    v_manual_posted uuid;
    v_manual_reversal uuid;
    v_expense_account uuid;
  BEGIN
    SELECT id INTO v_expense_account FROM public.accounts WHERE organization_id=v_org AND code='5200';
    INSERT INTO public.journal_entries(id,organization_id,entry_date,entry_type,status,description,created_by)
    VALUES(v_manual_id,v_org,current_date,'manual','draft','Manual journal reversal test',v_user);
    INSERT INTO public.account_transactions(organization_id,journal_entry_id,account_id,line_number,debit,credit,created_by)
    VALUES(v_org,v_manual_id,v_expense_account,1,25,0,v_user),(v_org,v_manual_id,v_cash,2,0,25,v_user);
    v_manual_posted:=public.post_journal_entry(v_org,v_manual_id);
    v_manual_reversal:=public.reverse_journal_entry(v_org,v_manual_posted,current_date,'Smoke test reversal');
    IF NOT EXISTS(SELECT 1 FROM public.journal_entries WHERE id=v_manual_id AND reversal_journal_entry_id=v_manual_reversal) THEN
      RAISE EXCEPTION 'Manual journal reversal metadata was not finalized';
    END IF;
  END;

  IF EXISTS(
    SELECT 1 FROM public.account_transactions t
    WHERE t.organization_id=v_org AND t.journal_entry_id IN (v_purchase_journal,v_sales_journal)
    GROUP BY t.journal_entry_id
    HAVING round(sum(t.debit),4)<>round(sum(t.credit),4)
  ) THEN RAISE EXCEPTION 'Posted purchase or sales journal is unbalanced'; END IF;
END;
$posting_integration$;
ROLLBACK;
