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
     OR to_regprocedure('public.post_sales(uuid,uuid)') IS NULL
     OR to_regprocedure('public.post_purchase_return(uuid,uuid)') IS NULL
     OR to_regprocedure('public.post_sales_return(uuid,uuid)') IS NULL
     OR to_regprocedure('public.post_inventory_adjustment(uuid,date,text,jsonb,uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Purchase, sales, return and inventory-adjustment RPCs must be installed';
  END IF;

  IF to_regprocedure('private.enforce_product_identity_immutable()') IS NULL
     OR to_regprocedure('private.enforce_used_account_definition_immutable()') IS NULL THEN
    RAISE EXCEPTION 'Used product and account definitions must be protected';
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
  v_gain uuid;
  v_loss uuid;
  v_uom uuid:=gen_random_uuid();
  v_supplier uuid:=gen_random_uuid();
  v_customer uuid:=gen_random_uuid();
  v_product uuid:=gen_random_uuid();
  v_other_product uuid:=gen_random_uuid();
  v_adjust_product uuid:=gen_random_uuid();
  v_precision_product uuid:=gen_random_uuid();
  v_opening uuid:=gen_random_uuid();
  v_purchase uuid:=gen_random_uuid();
  v_purchase_journal uuid;
  v_sale uuid:=gen_random_uuid();
  v_sales_journal uuid;
  v_adjustment_journal uuid;
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
  SELECT id INTO v_gain FROM public.accounts WHERE organization_id=v_org AND code='4200';
  SELECT id INTO v_loss FROM public.accounts WHERE organization_id=v_org AND code='5200';

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
  VALUES
    (v_product,v_org,private.allocate_document_number(v_org,'products'),'Smoke Product',v_uom,v_inventory,v_revenue,v_cogs,true,v_user),
    (v_other_product,v_org,private.allocate_document_number(v_org,'products'),'Other Product',v_uom,v_inventory,v_revenue,v_cogs,true,v_user),
    (v_adjust_product,v_org,private.allocate_document_number(v_org,'products'),'Adjustment Product',v_uom,v_inventory,v_revenue,v_cogs,true,v_user);

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
    UPDATE public.products SET sales_account_id=v_revenue
     WHERE organization_id=v_org AND id=v_product;
    -- Same-value update is harmless; try a real mapping change next.
    UPDATE public.products SET sales_account_id=(SELECT id FROM public.accounts WHERE organization_id=v_org AND code='4200')
     WHERE organization_id=v_org AND id=v_product;
  EXCEPTION WHEN check_violation THEN
    v_failed:=true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'Product account mapping was mutable after inventory posting'; END IF;

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

  -- Return headers must match source counterparty; return lines must match the
  -- exact source document line and product.
  DECLARE
    v_purchase_return uuid:=gen_random_uuid();
    v_sales_return uuid:=gen_random_uuid();
    v_purchase_item uuid;
    v_sales_item uuid;
    v_return_rejected boolean:=false;
  BEGIN
    SELECT id INTO v_purchase_item FROM public.purchase_items WHERE organization_id=v_org AND purchase_id=v_purchase;
    INSERT INTO public.purchase_returns(id,organization_id,purchase_id,supplier_id,return_date,payable_account_id,created_by)
    VALUES(v_purchase_return,v_org,v_purchase,v_supplier,current_date,v_payable,v_user);
    BEGIN
      INSERT INTO public.purchase_return_items(organization_id,purchase_return_id,line_number,purchase_item_id,product_id,quantity,unit_cost,line_total,created_by)
      VALUES(v_org,v_purchase_return,1,v_purchase_item,v_other_product,1,10,10,v_user);
    EXCEPTION WHEN check_violation THEN
      v_return_rejected:=true;
    END;
    IF NOT v_return_rejected THEN RAISE EXCEPTION 'Purchase return accepted a product different from its source line'; END IF;

    SELECT id INTO v_sales_item FROM public.sales_items WHERE organization_id=v_org AND sales_id=v_sale;
    v_return_rejected:=false;
    INSERT INTO public.sales_returns(id,organization_id,sales_id,customer_id,return_date,receivable_account_id,created_by)
    VALUES(v_sales_return,v_org,v_sale,v_customer,current_date,v_receivable,v_user);
    BEGIN
      INSERT INTO public.sales_return_items(organization_id,sales_return_id,line_number,sales_item_id,product_id,quantity,unit_price,line_total,created_by)
      VALUES(v_org,v_sales_return,1,v_sales_item,v_other_product,1,20,20,v_user);
    EXCEPTION WHEN check_violation THEN
      v_return_rejected:=true;
    END;
    IF NOT v_return_rejected THEN RAISE EXCEPTION 'Sales return accepted a product different from its source line'; END IF;
  END;
  SELECT quantity,inventory_value INTO v_qty,v_value FROM public.inventory_balances WHERE organization_id=v_org AND product_id=v_product;
  IF v_qty<>6 OR v_value<>54 THEN
    RAISE EXCEPTION 'Sales inventory balance incorrect: quantity %, value %',v_qty,v_value;
  END IF;
  SELECT cogs_total INTO v_cogs_total FROM public.sales_items WHERE organization_id=v_org AND sales_id=v_sale;
  IF v_cogs_total<>36 THEN
    RAISE EXCEPTION 'Sales COGS incorrect: %',v_cogs_total;
  END IF;

  -- A purchase return uses current moving-average inventory cost and reconciles
  -- the supplier credit through the configured purchase-return variance account.
  DECLARE
    v_purchase_return uuid:=gen_random_uuid();
    v_sales_return uuid:=gen_random_uuid();
    v_purchase_item uuid;
    v_sales_item uuid;
    v_return_journal uuid;
  BEGIN
    SELECT id INTO v_purchase_item FROM public.purchase_items WHERE organization_id=v_org AND purchase_id=v_purchase;
    INSERT INTO public.purchase_returns(
      id,organization_id,purchase_id,supplier_id,return_date,status,subtotal,discount_amount,total_amount,
      payable_account_id,created_by
    )
    VALUES(v_purchase_return,v_org,v_purchase,v_supplier,current_date,'draft',20,2,18,v_payable,v_user);
    INSERT INTO public.purchase_return_items(
      organization_id,purchase_return_id,line_number,purchase_item_id,product_id,quantity,unit_cost,line_total,created_by
    )
    VALUES(v_org,v_purchase_return,1,v_purchase_item,v_product,2,10,20,v_user);
    v_return_journal:=public.post_purchase_return(v_org,v_purchase_return);
    IF NOT EXISTS(SELECT 1 FROM public.purchase_returns WHERE id=v_purchase_return AND status='posted' AND posted_journal_entry_id=v_return_journal) THEN
      RAISE EXCEPTION 'Purchase return posting did not finalize source document';
    END IF;
    SELECT quantity,inventory_value INTO v_qty,v_value FROM public.inventory_balances WHERE organization_id=v_org AND product_id=v_product;
    IF v_qty<>4 OR v_value<>36 THEN
      RAISE EXCEPTION 'Purchase return inventory balance incorrect: quantity %, value %',v_qty,v_value;
    END IF;

    SELECT id INTO v_sales_item FROM public.sales_items WHERE organization_id=v_org AND sales_id=v_sale;
    INSERT INTO public.sales_returns(
      id,organization_id,sales_id,customer_id,return_date,status,subtotal,discount_amount,total_amount,
      receivable_account_id,created_by
    )
    VALUES(v_sales_return,v_org,v_sale,v_customer,current_date,'draft',20,0,20,v_receivable,v_user);
    INSERT INTO public.sales_return_items(
      organization_id,sales_return_id,line_number,sales_item_id,product_id,quantity,unit_price,line_total,created_by
    )
    VALUES(v_org,v_sales_return,1,v_sales_item,v_product,1,20,20,v_user);
    v_return_journal:=public.post_sales_return(v_org,v_sales_return);
    IF NOT EXISTS(SELECT 1 FROM public.sales_returns WHERE id=v_sales_return AND status='posted' AND posted_journal_entry_id=v_return_journal) THEN
      RAISE EXCEPTION 'Sales return posting did not finalize source document';
    END IF;
    SELECT quantity,inventory_value INTO v_qty,v_value FROM public.inventory_balances WHERE organization_id=v_org AND product_id=v_product;
    IF v_qty<>5 OR v_value<>45 THEN
      RAISE EXCEPTION 'Sales return inventory balance incorrect: quantity %, value %',v_qty,v_value;
    END IF;
    SELECT cogs_total INTO v_cogs_total FROM public.sales_return_items WHERE organization_id=v_org AND sales_return_id=v_sales_return;
    IF v_cogs_total<>9 THEN RAISE EXCEPTION 'Sales return COGS restoration incorrect: %',v_cogs_total; END IF;
  END;

  -- Receipts and supplier payments post balanced journals and allocate only to
  -- matching posted invoices for the same contact/control account.
  DECLARE
    v_receipt_id uuid:=gen_random_uuid();
    v_supplier_payment_id uuid:=gen_random_uuid();
    v_payment_journal uuid;
  BEGIN
    INSERT INTO public.payments(id,organization_id,payment_type,contact_id,payment_date,amount,account_id,settlement_account_id,created_by)
    VALUES(v_receipt_id,v_org,'receipt',v_customer,current_date,5,v_receivable,v_cash,v_user);
    INSERT INTO public.payment_allocations(organization_id,payment_id,document_type,document_id,allocated_amount,created_by)
    VALUES(v_org,v_receipt_id,'sales',v_sale,5,v_user);
    v_payment_journal:=public.post_payment(v_org,v_receipt_id);
    IF NOT EXISTS(SELECT 1 FROM public.payments WHERE id=v_receipt_id AND status='posted' AND posted_journal_entry_id=v_payment_journal) THEN
      RAISE EXCEPTION 'Customer receipt did not post';
    END IF;
    IF (SELECT round(sum(debit),4) FROM public.account_transactions WHERE organization_id=v_org AND journal_entry_id=v_payment_journal)<>5
       OR (SELECT round(sum(credit),4) FROM public.account_transactions WHERE organization_id=v_org AND journal_entry_id=v_payment_journal)<>5 THEN
      RAISE EXCEPTION 'Customer receipt journal is unbalanced';
    END IF;

    INSERT INTO public.payments(id,organization_id,payment_type,contact_id,payment_date,amount,account_id,settlement_account_id,created_by)
    VALUES(v_supplier_payment_id,v_org,'payment',v_supplier,current_date,5,v_payable,v_cash,v_user);
    INSERT INTO public.payment_allocations(organization_id,payment_id,document_type,document_id,allocated_amount,created_by)
    VALUES(v_org,v_supplier_payment_id,'purchase',v_purchase,5,v_user);
    v_payment_journal:=public.post_payment(v_org,v_supplier_payment_id);
    IF NOT EXISTS(SELECT 1 FROM public.payments WHERE id=v_supplier_payment_id AND status='posted' AND posted_journal_entry_id=v_payment_journal) THEN
      RAISE EXCEPTION 'Supplier payment did not post';
    END IF;
    IF (SELECT round(sum(debit),4) FROM public.account_transactions WHERE organization_id=v_org AND journal_entry_id=v_payment_journal)<>5
       OR (SELECT round(sum(credit),4) FROM public.account_transactions WHERE organization_id=v_org AND journal_entry_id=v_payment_journal)<>5 THEN
      RAISE EXCEPTION 'Supplier payment journal is unbalanced';
    END IF;
  END;

  v_adjustment_journal:=public.post_inventory_adjustment(
    v_org,current_date,'Mixed inventory adjustment',
    jsonb_build_array(
      jsonb_build_object('product_id',v_adjust_product,'direction','in','quantity',5,'unit_cost',3),
      jsonb_build_object('product_id',v_product,'direction','out','quantity',1)
    ),
    v_gain,v_loss
  );
  SELECT quantity,inventory_value INTO v_qty,v_value FROM public.inventory_balances
   WHERE organization_id=v_org AND product_id=v_adjust_product;
  IF v_qty<>5 OR v_value<>15 THEN
    RAISE EXCEPTION 'Inventory increase adjustment incorrect: quantity %, value %',v_qty,v_value;
  END IF;
  SELECT quantity,inventory_value INTO v_qty,v_value FROM public.inventory_balances
   WHERE organization_id=v_org AND product_id=v_product;
  IF v_qty<>4 OR v_value<>36 THEN
    RAISE EXCEPTION 'Inventory decrease adjustment incorrect: quantity %, value %',v_qty,v_value;
  END IF;
  IF EXISTS(
    SELECT 1 FROM public.account_transactions
     WHERE organization_id=v_org AND journal_entry_id=v_adjustment_journal
     GROUP BY journal_entry_id
    HAVING round(sum(debit),4)<>round(sum(credit),4)
  ) THEN RAISE EXCEPTION 'Inventory adjustment journal is unbalanced'; END IF;

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


-- Authenticated-role RLS test: active members see only their tenant, can
-- maintain member-level records, and cannot administer accounts or sequences.
BEGIN;
DO $rls_member_isolation_setup$
DECLARE
  v_owner uuid:=gen_random_uuid();
  v_member uuid:=gen_random_uuid();
  v_org_a uuid;
  v_org_b uuid;
BEGIN
  INSERT INTO auth.users(id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  VALUES
    (v_owner,'authenticated','authenticated','zero-rls-owner-'||v_owner::text||'@example.invalid','','{}','{}',now(),now(),now()),
    (v_member,'authenticated','authenticated','zero-rls-member-'||v_member::text||'@example.invalid','','{}','{}',now(),now(),now());
  PERFORM set_config('request.jwt.claim.sub',v_owner::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_owner::text,'role','authenticated')::text,true);
  v_org_a:=public.create_organization('ZERO ERP RLS member organization');
  v_org_b:=public.create_organization('ZERO ERP RLS private organization');
  INSERT INTO public.organization_users(organization_id,user_id,status,created_by)
  VALUES(v_org_a,v_member,'active',v_owner);
  PERFORM set_config('zero_erp.test_org_a',v_org_a::text,true);
  PERFORM set_config('zero_erp.test_org_b',v_org_b::text,true);
  PERFORM set_config('request.jwt.claim.sub',v_member::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_member::text,'role','authenticated')::text,true);
END;
$rls_member_isolation_setup$;

SET LOCAL ROLE authenticated;
DO $rls_member_isolation_assert$
DECLARE
  v_org_a uuid:=current_setting('zero_erp.test_org_a')::uuid;
  v_org_b uuid:=current_setting('zero_erp.test_org_b')::uuid;
  v_blocked boolean:=false;
  v_rows integer;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.organizations WHERE id=v_org_a) THEN
    RAISE EXCEPTION 'Member cannot read organization membership';
  END IF;
  IF EXISTS(SELECT 1 FROM public.organizations WHERE id=v_org_b) THEN
    RAISE EXCEPTION 'Cross-tenant organization data leaked';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.accounts WHERE organization_id=v_org_a) THEN
    RAISE EXCEPTION 'Member cannot read organization chart of accounts';
  END IF;
  IF EXISTS(SELECT 1 FROM public.accounts WHERE organization_id=v_org_b) THEN
    RAISE EXCEPTION 'Cross-tenant accounts leaked';
  END IF;

  INSERT INTO public.contacts(organization_id,code,name,status)
  VALUES(v_org_a,'MEMBER-TEST','Member contact','active');

  BEGIN
    INSERT INTO public.accounts(organization_id,code,account_name,account_type,normal_balance,is_control_account,is_postable,status)
    VALUES(v_org_a,'1199','Member-created account','asset','debit',false,true,'active');
  EXCEPTION WHEN insufficient_privilege THEN
    v_blocked:=true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'Ordinary member could create a creator-managed account'; END IF;

  UPDATE public.number_sequences SET next_number=next_number+1
   WHERE organization_id=v_org_a AND document_type='sales';
  GET DIAGNOSTICS v_rows=ROW_COUNT;
  IF v_rows<>0 THEN RAISE EXCEPTION 'Ordinary member modified a read-only number sequence'; END IF;

  v_blocked:=false;
  BEGIN
    PERFORM public.next_account_code(v_org_a,'asset');
  EXCEPTION WHEN insufficient_privilege THEN
    v_blocked:=true;
  END;
  IF NOT v_blocked THEN RAISE EXCEPTION 'Ordinary member could allocate account codes'; END IF;

  IF has_function_privilege('authenticated','public.next_document_number(uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'Authenticated role can directly call document number allocator';
  END IF;
END;
$rls_member_isolation_assert$;
RESET ROLE;
ROLLBACK;
