-- ZERO ERP V1 real-life authenticated business lifecycle acceptance test.
-- Run against staging after all migrations. All generated records are rolled back.
BEGIN;

DO $signup$
DECLARE
  v_user uuid:=gen_random_uuid();
  v_org uuid;
BEGIN
  INSERT INTO auth.users(id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  VALUES(v_user,'authenticated','authenticated','zero-life-auth-'||v_user::text||'@example.invalid','','{}','{}',now(),now(),now());
  PERFORM set_config('request.jwt.claim.sub',v_user::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_user::text,'role','authenticated')::text,true);
  v_org:=public.create_organization('ZERO ERP Authenticated End-to-End Acceptance');
  PERFORM set_config('zero_life.user_id',v_user::text,true);
  PERFORM set_config('zero_life.org_id',v_org::text,true);
END;
$signup$;

SET LOCAL ROLE authenticated;

DO $business_lifecycle$
#variable_conflict use_variable
DECLARE
  u uuid:=current_setting('zero_life.user_id')::uuid;
  org uuid:=current_setting('zero_life.org_id')::uuid;
  cash uuid; ar uuid; inv uuid; ap uuid; equity uuid; rev uuid; cogs uuid; exp_acct uuid;
  supplier uuid:=gen_random_uuid(); customer uuid:=gen_random_uuid(); uom uuid:=gen_random_uuid();
  product uuid:=gen_random_uuid(); product2 uuid:=gen_random_uuid();
  opening_journal uuid:=gen_random_uuid(); purchase_id uuid:=gen_random_uuid(); sale_id uuid:=gen_random_uuid();
  receipt_id uuid:=gen_random_uuid(); payment_id uuid:=gen_random_uuid();
  opening_receipt_id uuid:=gen_random_uuid(); opening_payment_id uuid:=gen_random_uuid();
  pr_id uuid:=gen_random_uuid(); sr_id uuid:=gen_random_uuid(); expense_id uuid:=gen_random_uuid();
  cat uuid; custom_code text; ar_opening_id uuid; ap_opening_id uuid;
  q numeric; val numeric; failed boolean:=false;
BEGIN
  IF auth.uid() IS DISTINCT FROM u THEN RAISE EXCEPTION 'Authenticated identity context incorrect'; END IF;

  SELECT id INTO cash FROM public.accounts WHERE organization_id=org AND code='1110';
  SELECT id INTO ar FROM public.accounts WHERE organization_id=org AND code='1130';
  SELECT id INTO inv FROM public.accounts WHERE organization_id=org AND code='1140';
  SELECT id INTO ap FROM public.accounts WHERE organization_id=org AND code='2110';
  SELECT id INTO equity FROM public.accounts WHERE organization_id=org AND code='3200';
  SELECT id INTO rev FROM public.accounts WHERE organization_id=org AND code='4100';
  SELECT id INTO cogs FROM public.accounts WHERE organization_id=org AND code='5100';
  SELECT id INTO exp_acct FROM public.accounts WHERE organization_id=org AND code='5200';
  IF (SELECT count(*) FROM public.accounts WHERE organization_id=org)<>13 THEN
    RAISE EXCEPTION 'Default chart of accounts incomplete';
  END IF;

  INSERT INTO public.contacts(id,organization_id,code,name,status,created_by)
  VALUES(supplier,org,'SUP-OPEN-001','Opening supplier','active',u),
        (customer,org,'CUS-OPEN-001','Opening customer','active',u);
  INSERT INTO public.units_of_measure(id,organization_id,name,status,created_by)
  VALUES(uom,org,'Piece','active',u);
  INSERT INTO public.products(id,organization_id,code,name,unit_id,inventory_account_id,sales_account_id,cogs_account_id,status,created_by)
  VALUES(product,org,'PRD-OPEN-001','Opening stock product',uom,inv,rev,cogs,true,u),
        (product2,org,'PRD-ADJ-002','Adjustment test product',uom,inv,rev,cogs,true,u);

  INSERT INTO public.journal_entries(id,organization_id,entry_date,entry_type,status,description,created_by)
  VALUES(opening_journal,org,current_date,'opening_balance','draft','Opening cash, AR, inventory, AP and equity',u);
  INSERT INTO public.account_transactions(organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by)
  VALUES(org,opening_journal,cash,1,'Opening cash',10000,0,NULL,u),
        (org,opening_journal,ar,2,'Opening customer invoice INV-OLD-01',4000,0,customer,u),
        (org,opening_journal,inv,3,'Opening inventory',5000,0,NULL,u),
        (org,opening_journal,ap,4,'Opening supplier invoice BILL-OLD-01',0,3000,supplier,u),
        (org,opening_journal,equity,5,'Opening equity',0,16000,NULL,u);

  PERFORM public.complete_organization_setup(
    org,jsonb_build_array(jsonb_build_object('product_id',product,'quantity',10,'unit_cost',500)),false
  );
  SELECT id INTO ar_opening_id FROM public.opening_balance_items
   WHERE organization_id=org AND balance_type='receivable' AND contact_id=customer;
  SELECT id INTO ap_opening_id FROM public.opening_balance_items
   WHERE organization_id=org AND balance_type='payable' AND contact_id=supplier;
  IF ar_opening_id IS NULL OR ap_opening_id IS NULL THEN
    RAISE EXCEPTION 'Opening AR/AP subledger was not materialized';
  END IF;
  SELECT quantity,inventory_value INTO q,val FROM public.inventory_balances
   WHERE organization_id=org AND product_id=product;
  IF q<>10 OR val<>5000 THEN RAISE EXCEPTION 'Opening inventory mismatch'; END IF;

  -- Partial settlement of opening A/R and A/P.
  INSERT INTO public.payments(id,organization_id,payment_type,contact_id,payment_date,amount,account_id,settlement_account_id,created_by)
  VALUES(opening_receipt_id,org,'receipt',customer,current_date,500,ar,cash,u);
  INSERT INTO public.payment_allocations(organization_id,payment_id,document_type,document_id,allocated_amount,created_by)
  VALUES(org,opening_receipt_id,'opening_balance',ar_opening_id,500,u);
  PERFORM public.post_payment(org,opening_receipt_id);

  INSERT INTO public.payments(id,organization_id,payment_type,contact_id,payment_date,amount,account_id,settlement_account_id,created_by)
  VALUES(opening_payment_id,org,'payment',supplier,current_date,700,ap,cash,u);
  INSERT INTO public.payment_allocations(organization_id,payment_id,document_type,document_id,allocated_amount,created_by)
  VALUES(org,opening_payment_id,'opening_balance',ap_opening_id,700,u);
  PERFORM public.post_payment(org,opening_payment_id);

  -- Credit purchase and partial supplier settlement.
  INSERT INTO public.purchase(id,organization_id,supplier_id,invoice_date,status,subtotal,discount_amount,total_amount,payable_account_id,created_by)
  VALUES(purchase_id,org,supplier,current_date,'draft',3000,0,3000,ap,u);
  INSERT INTO public.purchase_items(organization_id,purchase_id,line_number,product_id,quantity,unit_cost,line_total,created_by)
  VALUES(org,purchase_id,1,product,5,600,3000,u);
  PERFORM public.post_purchase(org,purchase_id);

  INSERT INTO public.payments(id,organization_id,payment_type,contact_id,payment_date,amount,account_id,settlement_account_id,created_by)
  VALUES(payment_id,org,'payment',supplier,current_date,1000,ap,cash,u);
  INSERT INTO public.payment_allocations(organization_id,payment_id,document_type,document_id,allocated_amount,created_by)
  VALUES(org,payment_id,'purchase',purchase_id,1000,u);
  PERFORM public.post_payment(org,payment_id);

  -- Credit sale and partial customer receipt.
  INSERT INTO public.sales(id,organization_id,customer_id,invoice_date,status,subtotal,discount_amount,total_amount,receivable_account_id,created_by)
  VALUES(sale_id,org,customer,current_date,'draft',2700,0,2700,ar,u);
  INSERT INTO public.sales_items(organization_id,sales_id,line_number,product_id,quantity,unit_price,line_total,created_by)
  VALUES(org,sale_id,1,product,3,900,2700,u);
  PERFORM public.post_sales(org,sale_id);

  INSERT INTO public.payments(id,organization_id,payment_type,contact_id,payment_date,amount,account_id,settlement_account_id,created_by)
  VALUES(receipt_id,org,'receipt',customer,current_date,1000,ar,cash,u);
  INSERT INTO public.payment_allocations(organization_id,payment_id,document_type,document_id,allocated_amount,created_by)
  VALUES(org,receipt_id,'sales',sale_id,1000,u);
  PERFORM public.post_payment(org,receipt_id);

  -- Excess settlement against an opening receivable must be rejected.
  DECLARE v_bad_payment uuid:=gen_random_uuid();
  BEGIN
    INSERT INTO public.payments(id,organization_id,payment_type,contact_id,payment_date,amount,account_id,settlement_account_id,created_by)
    VALUES(v_bad_payment,org,'receipt',customer,current_date,4000,ar,cash,u);
    INSERT INTO public.payment_allocations(organization_id,payment_id,document_type,document_id,allocated_amount,created_by)
    VALUES(org,v_bad_payment,'opening_balance',ar_opening_id,4000,u);
    BEGIN
      PERFORM public.post_payment(org,v_bad_payment);
    EXCEPTION WHEN check_violation THEN failed:=true;
    END;
    IF NOT failed THEN RAISE EXCEPTION 'Over-allocation of opening receivable was accepted'; END IF;
  END;

  -- Purchase return with cost variance and customer sales return.
  INSERT INTO public.purchase_returns(id,organization_id,purchase_id,supplier_id,return_date,status,subtotal,discount_amount,total_amount,payable_account_id,purchase_return_variance_account_id,created_by)
  VALUES(pr_id,org,purchase_id,supplier,current_date,'draft',600,0,600,ap,exp_acct,u);
  INSERT INTO public.purchase_return_items(organization_id,purchase_return_id,line_number,purchase_item_id,product_id,quantity,unit_cost,line_total,created_by)
  SELECT org,pr_id,1,pi.id,product,1,600,600,u FROM public.purchase_items pi WHERE pi.purchase_id=purchase_id;
  PERFORM public.post_purchase_return(org,pr_id);

  INSERT INTO public.sales_returns(id,organization_id,sales_id,customer_id,return_date,status,subtotal,discount_amount,total_amount,receivable_account_id,created_by)
  VALUES(sr_id,org,sale_id,customer,current_date,'draft',900,0,900,ar,u);
  INSERT INTO public.sales_return_items(organization_id,sales_return_id,line_number,sales_item_id,product_id,quantity,unit_price,line_total,created_by)
  SELECT org,sr_id,1,si.id,product,1,900,900,u FROM public.sales_items si WHERE si.sales_id=sale_id;
  PERFORM public.post_sales_return(org,sr_id);

  -- Operating expense and mixed inbound/outbound inventory adjustment.
  SELECT id INTO cat FROM public.expense_categories
   WHERE organization_id=org AND status IS TRUE ORDER BY code LIMIT 1;
  INSERT INTO public.expenses(id,organization_id,expense_category_id,expense_date,amount,description,status,created_by)
  VALUES(expense_id,org,cat,current_date,150,'Office operating expense','draft',u);
  PERFORM public.post_expense(org,expense_id);

  PERFORM public.post_inventory_adjustment(
    org,current_date,'Physical count adjustment',
    jsonb_build_array(
      jsonb_build_object('product_id',product2,'direction','in','quantity',2,'unit_cost',400),
      jsonb_build_object('product_id',product,'direction','out','quantity',1)
    ),
    (SELECT id FROM public.accounts WHERE organization_id=org AND code='4200'),
    (SELECT id FROM public.accounts WHERE organization_id=org AND code='5200')
  );

  -- Creator-managed custom account provisioning.
  custom_code:=public.next_account_code(org,'expense');
  INSERT INTO public.accounts(organization_id,code,account_name,account_type,normal_balance,is_control_account,is_postable,status,created_by)
  VALUES(org,custom_code,'Acceptance Test Expense Account','expense','debit',false,true,'active',u);

  IF EXISTS(
    SELECT 1 FROM public.journal_entries e
    JOIN public.account_transactions t ON t.organization_id=e.organization_id AND t.journal_entry_id=e.id
    WHERE e.organization_id=org AND e.status='posted'
    GROUP BY e.id HAVING round(sum(t.debit),4)<>round(sum(t.credit),4)
  ) THEN RAISE EXCEPTION 'Unbalanced posted journal found'; END IF;

  SELECT quantity,inventory_value INTO q,val FROM public.inventory_balances
   WHERE organization_id=org AND product_id=product;
  IF q<>11 THEN RAISE EXCEPTION 'Inventory final quantity mismatch: %',q; END IF;
  IF (SELECT quantity FROM public.inventory_balances WHERE organization_id=org AND product_id=product2)<>2 THEN
    RAISE EXCEPTION 'Adjustment inbound inventory mismatch';
  END IF;
  IF (SELECT count(*) FROM public.inventory_transactions WHERE organization_id=org)<>7 THEN
    RAISE EXCEPTION 'Inventory ledger row count mismatch';
  END IF;

  IF (
    SELECT round(ob.original_amount-COALESCE(sum(pa.allocated_amount) FILTER (WHERE p.status='posted'),0),4)
    FROM public.opening_balance_items ob
    LEFT JOIN public.payment_allocations pa
      ON pa.organization_id=ob.organization_id AND pa.document_type='opening_balance' AND pa.document_id=ob.id
    LEFT JOIN public.payments p ON p.organization_id=pa.organization_id AND p.id=pa.payment_id
    WHERE ob.id=ar_opening_id GROUP BY ob.original_amount
  )<>3500 THEN RAISE EXCEPTION 'Opening receivable remaining mismatch'; END IF;

  IF (
    SELECT round(ob.original_amount-COALESCE(sum(pa.allocated_amount) FILTER (WHERE p.status='posted'),0),4)
    FROM public.opening_balance_items ob
    LEFT JOIN public.payment_allocations pa
      ON pa.organization_id=ob.organization_id AND pa.document_type='opening_balance' AND pa.document_id=ob.id
    LEFT JOIN public.payments p ON p.organization_id=pa.organization_id AND p.id=pa.payment_id
    WHERE ob.id=ap_opening_id GROUP BY ob.original_amount
  )<>2300 THEN RAISE EXCEPTION 'Opening payable remaining mismatch'; END IF;

  IF NOT has_table_privilege('authenticated','public.opening_balance_items','SELECT')
     OR has_table_privilege('authenticated','public.opening_balance_items','INSERT') THEN
    RAISE EXCEPTION 'Opening balance subledger privileges are incorrect';
  END IF;
END;
$business_lifecycle$;

RESET ROLE;
ROLLBACK;

SELECT 'Authenticated real-life lifecycle passed' AS result;
