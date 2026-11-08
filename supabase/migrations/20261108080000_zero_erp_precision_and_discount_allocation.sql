-- ZERO ERP V1: align opening inventory precision and exact document discount allocation.
BEGIN;
CREATE OR REPLACE FUNCTION public.complete_organization_setup(
  p_organization_id uuid,
  p_inventory_items jsonb DEFAULT '[]'::jsonb,
  p_confirm_zero_inventory boolean DEFAULT false
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
  v_journal_code text;
  v_entry_date date;
  v_inventory_account_id uuid;
  v_debit numeric(20,4);
  v_credit numeric(20,4);
  v_inventory_debit numeric(20,4);
  v_inventory_credit numeric(20,4);
  v_inventory_total numeric(20,4);
  v_line_count bigint;
  v_bad_lines bigint;
  v_item_count bigint;
  v_distinct_products bigint;
  v_item record;
  v_total_value numeric(20,4);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';
  END IF;
  IF NOT private.is_org_creator(p_organization_id) THEN
    RAISE EXCEPTION 'Only the organization creator can complete setup' USING ERRCODE='42501';
  END IF;
  IF p_inventory_items IS NULL OR jsonb_typeof(p_inventory_items) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Inventory opening items must be a JSON array' USING ERRCODE='22023';
  END IF;

  SELECT o.status INTO v_org_status
    FROM public.organizations o
   WHERE o.id=p_organization_id
   FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'configuring' THEN
    RAISE EXCEPTION 'Organization is not in configuring state' USING ERRCODE='23514';
  END IF;

  SELECT j.id,j.code,j.entry_date
    INTO v_journal_id,v_journal_code,v_entry_date
    FROM public.journal_entries j
   WHERE j.organization_id=p_organization_id
     AND j.entry_type='opening_balance'
   FOR UPDATE;
  IF v_journal_id IS NULL THEN
    RAISE EXCEPTION 'An opening balance journal entry is required' USING ERRCODE='23514';
  END IF;
  IF EXISTS (SELECT 1 FROM public.journal_entries j WHERE j.id=v_journal_id AND j.status<>'draft') THEN
    RAISE EXCEPTION 'Opening balance journal must be draft before setup completion' USING ERRCODE='23514';
  END IF;

  SELECT count(*),COALESCE(sum(t.debit),0),COALESCE(sum(t.credit),0)
    INTO v_line_count,v_debit,v_credit
    FROM public.account_transactions t
   WHERE t.organization_id=p_organization_id AND t.journal_entry_id=v_journal_id;
  IF v_line_count < 2 OR v_debit <= 0 OR round(v_debit,4)<>round(v_credit,4) THEN
    RAISE EXCEPTION 'Opening journal must contain at least two lines and be balanced' USING ERRCODE='23514';
  END IF;

  SELECT count(*) INTO v_bad_lines
    FROM public.account_transactions t
    JOIN public.accounts a ON a.organization_id=t.organization_id AND a.id=t.account_id
   WHERE t.organization_id=p_organization_id AND t.journal_entry_id=v_journal_id
     AND (a.status<>'active' OR NOT a.is_postable
       OR (a.code IN ('1130','2110') AND t.contact_id IS NULL));
  IF v_bad_lines>0 THEN
    RAISE EXCEPTION 'Opening journal contains inactive/non-postable accounts or control-account lines without contacts' USING ERRCODE='23514';
  END IF;

  SELECT a.id INTO v_inventory_account_id
    FROM public.accounts a
   WHERE a.organization_id=p_organization_id AND a.code='1140'
     AND a.account_type='asset' AND a.is_postable AND a.status='active';
  IF v_inventory_account_id IS NULL THEN
    RAISE EXCEPTION 'Inventory Asset account 1140 is missing or not postable' USING ERRCODE='23514';
  END IF;

  SELECT count(*),count(DISTINCT x.product_id),
         COALESCE(sum(round(x.quantity*x.unit_cost,4)),0)
    INTO v_item_count,v_distinct_products,v_inventory_total
    FROM jsonb_to_recordset(p_inventory_items) AS x(product_id uuid,quantity numeric(20,6),unit_cost numeric(20,6));
  IF v_item_count<>v_distinct_products THEN
    RAISE EXCEPTION 'Inventory opening items contain duplicate products' USING ERRCODE='23514';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_to_recordset(p_inventory_items) AS x(product_id uuid,quantity numeric(20,6),unit_cost numeric(20,6))
    WHERE x.product_id IS NULL OR x.quantity IS NULL OR x.unit_cost IS NULL
       OR x.quantity<=0 OR x.unit_cost<0
  ) THEN
    RAISE EXCEPTION 'Each inventory item requires a product, positive quantity and nonnegative unit cost' USING ERRCODE='23514';
  END IF;
  IF v_item_count=0 AND NOT p_confirm_zero_inventory THEN
    RAISE EXCEPTION 'Explicit zero-inventory confirmation is required' USING ERRCODE='23514';
  END IF;
  IF EXISTS (
    SELECT 1
      FROM jsonb_to_recordset(p_inventory_items) AS x(product_id uuid,quantity numeric(20,6),unit_cost numeric(20,6))
      LEFT JOIN public.products p ON p.organization_id=p_organization_id AND p.id=x.product_id
     WHERE p.id IS NULL OR p.status IS NOT TRUE OR p.inventory_account_id IS DISTINCT FROM v_inventory_account_id
  ) THEN
    RAISE EXCEPTION 'Inventory items must reference active products mapped to Inventory Asset account 1140' USING ERRCODE='23514';
  END IF;

  SELECT COALESCE(sum(t.debit),0),COALESCE(sum(t.credit),0)
    INTO v_inventory_debit,v_inventory_credit
    FROM public.account_transactions t
   WHERE t.organization_id=p_organization_id AND t.journal_entry_id=v_journal_id
     AND t.account_id=v_inventory_account_id;
  IF round(v_inventory_debit,4)<>v_inventory_total OR v_inventory_credit<>0 THEN
    RAISE EXCEPTION 'Inventory Asset debit must equal the total opening inventory value' USING ERRCODE='23514';
  END IF;

  IF EXISTS (SELECT 1 FROM public.inventory_transactions WHERE organization_id=p_organization_id)
     OR EXISTS (SELECT 1 FROM public.inventory_balances WHERE organization_id=p_organization_id) THEN
    RAISE EXCEPTION 'Opening inventory ledger already exists; setup cannot be completed twice' USING ERRCODE='23505';
  END IF;

  -- Only this trusted SECURITY DEFINER transaction can pass workflow triggers.
  PERFORM set_config('zero_erp.allow_workflow','on',true);

  IF v_journal_code IS NULL THEN
    v_journal_code := private.allocate_document_number(p_organization_id,'journal_entries');
  END IF;

  FOR v_item IN
    SELECT x.product_id,x.quantity,x.unit_cost
      FROM jsonb_to_recordset(p_inventory_items) AS x(product_id uuid,quantity numeric(20,6),unit_cost numeric(20,6))
     ORDER BY x.product_id
  LOOP
    v_total_value := round(v_item.quantity*v_item.unit_cost,4);
    INSERT INTO public.inventory_transactions
      (organization_id,code,product_id,transaction_date,transaction_type,direction,
       quantity,unit_cost,total_value,reference_type,reference_id,unit_cost_before,
       average_cost_after,created_by)
    VALUES
      (p_organization_id,private.allocate_document_number(p_organization_id,'inventory_transactions'),
       v_item.product_id,v_entry_date,'opening','in',v_item.quantity,v_item.unit_cost,
       v_total_value,'journal_entry',v_journal_id,NULL,v_item.unit_cost,v_user_id);

    INSERT INTO public.inventory_balances
      (organization_id,product_id,quantity,average_cost,inventory_value,created_by,updated_by,updated_at)
    VALUES
      (p_organization_id,v_item.product_id,v_item.quantity,v_item.unit_cost,v_total_value,
       v_user_id,v_user_id,now());
  END LOOP;

  UPDATE public.journal_entries
     SET code=v_journal_code,status='posted',confirmed_at=now(),confirmed_by=v_user_id,
         posted_at=now(),posted_by=v_user_id,updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=v_journal_id AND status='draft';
  IF NOT FOUND THEN RAISE EXCEPTION 'Opening journal could not be posted' USING ERRCODE='23514'; END IF;

  UPDATE public.organizations
     SET status='active',updated_by=v_user_id,updated_at=now()
   WHERE id=p_organization_id AND status='configuring';
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization activation failed' USING ERRCODE='23514'; END IF;

  RETURN v_journal_id;
END;
$function$;
CREATE OR REPLACE FUNCTION private.purchase_net_lines(p_organization_id uuid,p_purchase_id uuid)
RETURNS TABLE(item_id uuid,product_id uuid,quantity numeric,unit_cost numeric,line_total numeric,net_line_total numeric)
LANGUAGE sql STABLE SET search_path = ''
AS $function$
WITH header AS (
 SELECT p.subtotal,p.discount_amount FROM public.purchase p
 WHERE p.organization_id=p_organization_id AND p.id=p_purchase_id
), base AS (
 SELECT i.id AS item_id,i.product_id,i.quantity,i.unit_cost,i.line_total,i.line_number,
        h.subtotal,h.discount_amount,
        CASE WHEN h.subtotal=0 THEN 0 ELSE h.discount_amount*10000*i.line_total/h.subtotal END AS exact_discount_units,
        floor(CASE WHEN h.subtotal=0 THEN 0 ELSE h.discount_amount*10000*i.line_total/h.subtotal END) AS base_discount_units
 FROM public.purchase_items i CROSS JOIN header h
 WHERE i.organization_id=p_organization_id AND i.purchase_id=p_purchase_id
), ranked AS (
 SELECT b.*,
        row_number() OVER (ORDER BY (b.exact_discount_units-b.base_discount_units) DESC,b.line_number,b.item_id) AS discount_rank,
        sum(b.base_discount_units) OVER () AS base_units_total,
        round(b.discount_amount*10000,0) AS total_discount_units
 FROM base b
), allocated AS (
 SELECT r.*,r.base_discount_units
        + CASE WHEN r.discount_rank<=r.total_discount_units-r.base_units_total THEN 1 ELSE 0 END AS discount_units
 FROM ranked r
)
SELECT a.item_id,a.product_id,a.quantity,a.unit_cost,a.line_total,round(a.line_total-a.discount_units/10000,4)
FROM allocated a;
$function$;

CREATE OR REPLACE FUNCTION private.sales_net_lines(p_organization_id uuid,p_sales_id uuid)
RETURNS TABLE(item_id uuid,product_id uuid,quantity numeric,unit_price numeric,line_total numeric,net_line_total numeric)
LANGUAGE sql STABLE SET search_path = ''
AS $function$
WITH header AS (
 SELECT s.subtotal,s.discount_amount FROM public.sales s
 WHERE s.organization_id=p_organization_id AND s.id=p_sales_id
), base AS (
 SELECT i.id AS item_id,i.product_id,i.quantity,i.unit_price,i.line_total,i.line_number,
        h.subtotal,h.discount_amount,
        CASE WHEN h.subtotal=0 THEN 0 ELSE h.discount_amount*10000*i.line_total/h.subtotal END AS exact_discount_units,
        floor(CASE WHEN h.subtotal=0 THEN 0 ELSE h.discount_amount*10000*i.line_total/h.subtotal END) AS base_discount_units
 FROM public.sales_items i CROSS JOIN header h
 WHERE i.organization_id=p_organization_id AND i.sales_id=p_sales_id
), ranked AS (
 SELECT b.*,
        row_number() OVER (ORDER BY (b.exact_discount_units-b.base_discount_units) DESC,b.line_number,b.item_id) AS discount_rank,
        sum(b.base_discount_units) OVER () AS base_units_total,
        round(b.discount_amount*10000,0) AS total_discount_units
 FROM base b
), allocated AS (
 SELECT r.*,r.base_discount_units
        + CASE WHEN r.discount_rank<=r.total_discount_units-r.base_units_total THEN 1 ELSE 0 END AS discount_units
 FROM ranked r
)
SELECT a.item_id,a.product_id,a.quantity,a.unit_price,a.line_total,round(a.line_total-a.discount_units/10000,4)
FROM allocated a;
$function$;

REVOKE ALL ON FUNCTION private.purchase_net_lines(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.sales_net_lines(uuid,uuid) FROM PUBLIC,anon,authenticated;

COMMIT;