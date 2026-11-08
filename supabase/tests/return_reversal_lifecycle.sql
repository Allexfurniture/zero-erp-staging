-- ZERO ERP source return reversal lifecycle acceptance tests.
-- Validates balanced journal reversals, exact inventory restoration, source return-limit reopening,
-- duplicate reversal protection, and rejection when returned stock has already been consumed.
BEGIN;
DO $return_reversal$
#variable_conflict use_variable
DECLARE
  v_user uuid:=gen_random_uuid();
  v_org uuid;
  v_cash uuid; v_equity uuid; v_inventory uuid; v_ar uuid; v_ap uuid;
  v_revenue uuid; v_expense uuid;
  v_uom uuid:=gen_random_uuid();
  v_supplier uuid:=gen_random_uuid(); v_customer uuid:=gen_random_uuid();
  v_product uuid:=gen_random_uuid();
  v_opening uuid:=gen_random_uuid();
  v_purchase uuid:=gen_random_uuid(); v_sale uuid:=gen_random_uuid(); v_sale2 uuid:=gen_random_uuid();
  v_purchase_return uuid:=gen_random_uuid(); v_sales_return uuid:=gen_random_uuid();
  v_purchase_return_again uuid:=gen_random_uuid(); v_sales_return_again uuid:=gen_random_uuid();
  v_purchase_item uuid; v_sales_item uuid;
  v_reversal uuid;
  v_qty_before numeric; v_value_before numeric; v_qty_after numeric; v_value_after numeric;
  v_rejected boolean;
BEGIN
  INSERT INTO auth.users(id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  VALUES(v_user,'authenticated','authenticated','zero-return-reversal-'||v_user::text||'@example.invalid','','{}','{}',now(),now(),now());
  PERFORM set_config('request.jwt.claim.sub',v_user::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_user::text,'role','authenticated')::text,true);

  v_org:=public.create_organization('ZERO ERP return reversal acceptance');
  SELECT id INTO v_cash FROM public.accounts WHERE organization_id=v_org AND code='1110';
  SELECT id INTO v_equity FROM public.accounts WHERE organization_id=v_org AND code='3200';
  SELECT id INTO v_inventory FROM public.accounts WHERE organization_id=v_org AND code='1140';
  SELECT id INTO v_ar FROM public.accounts WHERE organization_id=v_org AND code='1130';
  SELECT id INTO v_ap FROM public.accounts WHERE organization_id=v_org AND code='2110';
  SELECT id INTO v_revenue FROM public.accounts WHERE organization_id=v_org AND code='4100';
  SELECT id INTO v_expense FROM public.accounts WHERE organization_id=v_org AND code='5200';

  INSERT INTO public.units_of_measure(id,organization_id,name,status,created_by)
  VALUES(v_uom,v_org,'Piece','active',v_user);
  INSERT INTO public.contacts(id,organization_id,code,name,status,created_by)
  VALUES(v_supplier,v_org,'REV-SUP','Reversal Supplier','active',v_user),
        (v_customer,v_org,'REV-CUS','Reversal Customer','active',v_user);
  INSERT INTO public.products(id,organization_id,code,name,unit_id,inventory_account_id,sales_account_id,cogs_account_id,status,created_by)
  VALUES(v_product,v_org,'REV-PRD','Reversal Product',v_uom,v_inventory,v_revenue,v_expense,true,v_user);

  INSERT INTO public.journal_entries(id,organization_id,entry_date,entry_type,status,description,created_by)
  VALUES(v_opening,v_org,current_date,'opening_balance','draft','Opening cash and inventory',v_user);
  INSERT INTO public.account_transactions(organization_id,journal_entry_id,account_id,line_number,debit,credit,created_by)
  VALUES(v_org,v_opening,v_cash,1,1000,0,v_user),
        (v_org,v_opening,v_inventory,2,1000,0,v_user),
        (v_org,v_opening,v_equity,3,0,2000,v_user);
  PERFORM public.complete_organization_setup(
    v_org,jsonb_build_array(jsonb_build_object('product_id',v_product,'quantity',10,'unit_cost',100)),false
  );

  -- Post a purchase and return two units; reversal must restore the exact inventory value removed.
  INSERT INTO public.purchase(id,organization_id,supplier_id,invoice_date,status,subtotal,discount_amount,total_amount,payable_account_id,created_by)
  VALUES(v_purchase,v_org,v_supplier,current_date,'draft',600,0,600,v_ap,v_user);
  INSERT INTO public.purchase_items(organization_id,purchase_id,line_number,product_id,quantity,unit_cost,line_total,created_by)
  VALUES(v_org,v_purchase,1,v_product,5,120,600,v_user);
  PERFORM public.post_purchase(v_org,v_purchase);
  SELECT quantity,inventory_value INTO v_qty_before,v_value_before FROM public.inventory_balances
   WHERE organization_id=v_org AND product_id=v_product;
  SELECT id INTO v_purchase_item FROM public.purchase_items WHERE organization_id=v_org AND purchase_id=v_purchase;

  INSERT INTO public.purchase_returns(id,organization_id,purchase_id,supplier_id,return_date,status,subtotal,discount_amount,total_amount,payable_account_id,purchase_return_variance_account_id,created_by)
  VALUES(v_purchase_return,v_org,v_purchase,v_supplier,current_date,'draft',240,0,240,v_ap,v_expense,v_user);
  INSERT INTO public.purchase_return_items(organization_id,purchase_return_id,line_number,purchase_item_id,product_id,quantity,unit_cost,line_total,created_by)
  VALUES(v_org,v_purchase_return,1,v_purchase_item,v_product,2,120,240,v_user);
  PERFORM public.post_purchase_return(v_org,v_purchase_return);
  v_reversal:=public.reverse_purchase_return(v_org,v_purchase_return,current_date,'Acceptance test purchase return reversal');

  SELECT quantity,inventory_value INTO v_qty_after,v_value_after FROM public.inventory_balances
   WHERE organization_id=v_org AND product_id=v_product;
  IF v_qty_after<>v_qty_before OR v_value_after<>v_value_before THEN
    RAISE EXCEPTION 'Purchase return reversal did not restore exact inventory quantity/value';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.purchase_returns WHERE id=v_purchase_return AND status='reversed' AND reversal_journal_entry_id=v_reversal) THEN
    RAISE EXCEPTION 'Purchase return reversal metadata missing';
  END IF;
  v_rejected:=false;
  BEGIN
    PERFORM public.reverse_purchase_return(v_org,v_purchase_return,current_date,'Duplicate reversal');
  EXCEPTION WHEN check_violation THEN v_rejected:=true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Duplicate purchase return reversal was accepted'; END IF;

  -- The reversed purchase return no longer consumes source-line returnable quantity.
  INSERT INTO public.purchase_returns(id,organization_id,purchase_id,supplier_id,return_date,status,subtotal,discount_amount,total_amount,payable_account_id,purchase_return_variance_account_id,created_by)
  VALUES(v_purchase_return_again,v_org,v_purchase,v_supplier,current_date,'draft',600,0,600,v_ap,v_expense,v_user);
  INSERT INTO public.purchase_return_items(organization_id,purchase_return_id,line_number,purchase_item_id,product_id,quantity,unit_cost,line_total,created_by)
  VALUES(v_org,v_purchase_return_again,1,v_purchase_item,v_product,5,120,600,v_user);
  PERFORM public.post_purchase_return(v_org,v_purchase_return_again);

  -- Post a sale and a customer return; reversal removes the returned stock at its original COGS.
  INSERT INTO public.sales(id,organization_id,customer_id,invoice_date,status,subtotal,discount_amount,total_amount,receivable_account_id,created_by)
  VALUES(v_sale,v_org,v_customer,current_date,'draft',60,0,60,v_ar,v_user);
  INSERT INTO public.sales_items(organization_id,sales_id,line_number,product_id,quantity,unit_price,line_total,created_by)
  VALUES(v_org,v_sale,1,v_product,3,20,60,v_user);
  PERFORM public.post_sales(v_org,v_sale);
  SELECT quantity,inventory_value INTO v_qty_before,v_value_before FROM public.inventory_balances
   WHERE organization_id=v_org AND product_id=v_product;
  SELECT id INTO v_sales_item FROM public.sales_items WHERE organization_id=v_org AND sales_id=v_sale;

  INSERT INTO public.sales_returns(id,organization_id,sales_id,customer_id,return_date,status,subtotal,discount_amount,total_amount,receivable_account_id,created_by)
  VALUES(v_sales_return,v_org,v_sale,v_customer,current_date,'draft',20,0,20,v_ar,v_user);
  INSERT INTO public.sales_return_items(organization_id,sales_return_id,line_number,sales_item_id,product_id,quantity,unit_price,line_total,created_by)
  VALUES(v_org,v_sales_return,1,v_sales_item,v_product,1,20,20,v_user);
  PERFORM public.post_sales_return(v_org,v_sales_return);
  v_reversal:=public.reverse_sales_return(v_org,v_sales_return,current_date,'Acceptance test sales return reversal');

  SELECT quantity,inventory_value INTO v_qty_after,v_value_after FROM public.inventory_balances
   WHERE organization_id=v_org AND product_id=v_product;
  IF v_qty_after<>v_qty_before OR v_value_after<>v_value_before THEN
    RAISE EXCEPTION 'Sales return reversal did not restore exact pre-return inventory';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.sales_returns WHERE id=v_sales_return AND status='reversed' AND reversal_journal_entry_id=v_reversal) THEN
    RAISE EXCEPTION 'Sales return reversal metadata missing';
  END IF;
  v_rejected:=false;
  BEGIN
    PERFORM public.reverse_sales_return(v_org,v_sales_return,current_date,'Duplicate reversal');
  EXCEPTION WHEN check_violation THEN v_rejected:=true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Duplicate sales return reversal was accepted'; END IF;

  -- The reversed sales return no longer consumes source-line returnable quantity.
  INSERT INTO public.sales_returns(id,organization_id,sales_id,customer_id,return_date,status,subtotal,discount_amount,total_amount,receivable_account_id,created_by)
  VALUES(v_sales_return_again,v_org,v_sale,v_customer,current_date,'draft',60,0,60,v_ar,v_user);
  INSERT INTO public.sales_return_items(organization_id,sales_return_id,line_number,sales_item_id,product_id,quantity,unit_price,line_total,created_by)
  VALUES(v_org,v_sales_return_again,1,v_sales_item,v_product,3,20,60,v_user);
  PERFORM public.post_sales_return(v_org,v_sales_return_again);

  -- Consume all remaining stock, then ensure the sales-return reversal fails atomically.
  SELECT quantity INTO v_qty_before FROM public.inventory_balances WHERE organization_id=v_org AND product_id=v_product;
  INSERT INTO public.sales(id,organization_id,customer_id,invoice_date,status,subtotal,discount_amount,total_amount,receivable_account_id,created_by)
  VALUES(v_sale2,v_org,v_customer,current_date,'draft',v_qty_before*20,0,v_qty_before*20,v_ar,v_user);
  INSERT INTO public.sales_items(organization_id,sales_id,line_number,product_id,quantity,unit_price,line_total,created_by)
  VALUES(v_org,v_sale2,1,v_product,v_qty_before,20,v_qty_before*20,v_user);
  PERFORM public.post_sales(v_org,v_sale2);

  v_rejected:=false;
  BEGIN
    PERFORM public.reverse_sales_return(v_org,v_sales_return_again,current_date,'Must not create negative stock');
  EXCEPTION WHEN check_violation THEN v_rejected:=true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'Sales return reversal was allowed after returned inventory was consumed'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.sales_returns WHERE id=v_sales_return_again AND status='posted' AND reversal_journal_entry_id IS NULL) THEN
    RAISE EXCEPTION 'Failed sales return reversal was not atomic';
  END IF;
  IF EXISTS(SELECT 1 FROM public.inventory_balances WHERE organization_id=v_org AND product_id=v_product AND (quantity<0 OR inventory_value<0)) THEN
    RAISE EXCEPTION 'Return reversal created negative inventory';
  END IF;

  IF EXISTS(
    SELECT 1 FROM public.journal_entries je
    JOIN public.account_transactions t ON t.organization_id=je.organization_id AND t.journal_entry_id=je.id
    WHERE je.organization_id=v_org AND je.status='posted'
    GROUP BY je.id HAVING round(sum(t.debit),4)<>round(sum(t.credit),4)
  ) THEN RAISE EXCEPTION 'Unbalanced posted journal found in return reversal lifecycle'; END IF;
END;
$return_reversal$;
ROLLBACK;
SELECT 'ZERO ERP return reversal lifecycle passed' AS result;
