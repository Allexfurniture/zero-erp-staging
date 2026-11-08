-- ZERO ERP V1: return-document reversals and SECURITY INVOKER API facade.
-- Source-document reversal updates both accounting and inventory atomically.
BEGIN;

CREATE OR REPLACE FUNCTION public.reverse_purchase_return(
  p_organization_id uuid, p_return_id uuid, p_reversal_date date, p_reason text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_user uuid:=auth.uid();
  v_return public.purchase_returns%ROWTYPE;
  v_source public.purchase%ROWTYPE;
  v_journal uuid;
  v_item record;
  v_balance public.inventory_balances%ROWTYPE;
  v_new_qty numeric(20,6);
  v_new_value numeric(20,4);
  v_avg numeric(20,6);
BEGIN
  IF v_user IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  PERFORM 1 FROM public.organizations WHERE id=p_organization_id AND status='active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization not found or inactive' USING ERRCODE='23514'; END IF;
  SELECT * INTO v_return FROM public.purchase_returns
   WHERE organization_id=p_organization_id AND id=p_return_id FOR UPDATE;
  IF NOT FOUND OR v_return.status<>'posted' OR v_return.reversal_journal_entry_id IS NOT NULL
     OR v_return.posted_journal_entry_id IS NULL THEN
    RAISE EXCEPTION 'Only an unreversed posted purchase return can be reversed' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_source FROM public.purchase
   WHERE organization_id=p_organization_id AND id=v_return.purchase_id FOR UPDATE;
  IF NOT FOUND OR v_source.status<>'posted' THEN
    RAISE EXCEPTION 'Source purchase is not posted' USING ERRCODE='23514';
  END IF;

  PERFORM p.id FROM public.products p
   JOIN (SELECT DISTINCT product_id FROM public.inventory_transactions
          WHERE organization_id=p_organization_id AND reference_type='journal_entry'
            AND reference_id=v_return.posted_journal_entry_id
            AND transaction_type='purchase_return') x ON x.product_id=p.id
   WHERE p.organization_id=p_organization_id ORDER BY p.id FOR UPDATE OF p;

  FOR v_item IN
    SELECT product_id, sum(quantity)::numeric(20,6) qty,
           sum(total_value)::numeric(20,4) val
      FROM public.inventory_transactions
     WHERE organization_id=p_organization_id AND reference_type='journal_entry'
       AND reference_id=v_return.posted_journal_entry_id
       AND transaction_type='purchase_return' AND direction='out'
     GROUP BY product_id ORDER BY product_id
  LOOP
    SELECT * INTO v_balance FROM public.inventory_balances
     WHERE organization_id=p_organization_id AND product_id=v_item.product_id FOR UPDATE;
    IF NOT FOUND THEN
      INSERT INTO public.inventory_balances(organization_id,product_id,quantity,average_cost,inventory_value,created_by,updated_by,updated_at)
      VALUES(p_organization_id,v_item.product_id,v_item.qty,
             CASE WHEN v_item.qty=0 THEN 0 ELSE round(v_item.val/v_item.qty,6) END,
             v_item.val,v_user,v_user,now());
      v_new_qty:=v_item.qty; v_new_value:=v_item.val;
    ELSE
      v_new_qty:=v_balance.quantity+v_item.qty;
      v_new_value:=round(v_balance.inventory_value+v_item.val,4);
      UPDATE public.inventory_balances
         SET quantity=v_new_qty,inventory_value=v_new_value,
             average_cost=CASE WHEN v_new_qty=0 THEN 0 ELSE round(v_new_value/v_new_qty,6) END,
             updated_by=v_user,updated_at=now()
       WHERE organization_id=p_organization_id AND product_id=v_item.product_id;
    END IF;
    v_avg:=CASE WHEN v_new_qty=0 THEN 0 ELSE round(v_new_value/v_new_qty,6) END;
    INSERT INTO public.inventory_transactions(
      organization_id,code,product_id,transaction_date,transaction_type,direction,quantity,unit_cost,total_value,
      reference_type,reference_id,unit_cost_before,average_cost_after,created_by
    ) VALUES (
      p_organization_id,private.allocate_document_number(p_organization_id,'inventory_transactions'),
      v_item.product_id,p_reversal_date,'purchase_return_reversal','in',v_item.qty,
      CASE WHEN v_item.qty=0 THEN 0 ELSE round(v_item.val/v_item.qty,6) END,v_item.val,
      'journal_entry',v_return.posted_journal_entry_id,v_balance.average_cost,v_avg,v_user
    );
  END LOOP;

  v_journal:=private.reverse_source_journal(
    p_organization_id,v_return.posted_journal_entry_id,'purchase_return',p_return_id,p_reversal_date,p_reason
  );
  PERFORM set_config('zero_erp.allow_workflow','on',true);
  UPDATE public.purchase_returns
     SET status='reversed',reversal_journal_entry_id=v_journal,reversed_at=now(),
         reversed_by=v_user,reversal_reason=btrim(p_reason),updated_by=v_user,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_return_id AND status='posted';
  IF NOT FOUND THEN RAISE EXCEPTION 'Purchase return reversal metadata could not be finalized' USING ERRCODE='23514'; END IF;
  RETURN v_journal;
END;
$function$;

CREATE OR REPLACE FUNCTION public.reverse_sales_return(
  p_organization_id uuid, p_return_id uuid, p_reversal_date date, p_reason text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_user uuid:=auth.uid();
  v_return public.sales_returns%ROWTYPE;
  v_source public.sales%ROWTYPE;
  v_journal uuid;
  v_item record;
  v_balance public.inventory_balances%ROWTYPE;
  v_new_qty numeric(20,6);
  v_new_value numeric(20,4);
  v_avg numeric(20,6);
BEGIN
  IF v_user IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  PERFORM 1 FROM public.organizations WHERE id=p_organization_id AND status='active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization not found or inactive' USING ERRCODE='23514'; END IF;
  SELECT * INTO v_return FROM public.sales_returns
   WHERE organization_id=p_organization_id AND id=p_return_id FOR UPDATE;
  IF NOT FOUND OR v_return.status<>'posted' OR v_return.reversal_journal_entry_id IS NOT NULL
     OR v_return.posted_journal_entry_id IS NULL THEN
    RAISE EXCEPTION 'Only an unreversed posted sales return can be reversed' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_source FROM public.sales
   WHERE organization_id=p_organization_id AND id=v_return.sales_id FOR UPDATE;
  IF NOT FOUND OR v_source.status<>'posted' THEN
    RAISE EXCEPTION 'Source sale is not posted' USING ERRCODE='23514';
  END IF;

  PERFORM p.id FROM public.products p
   JOIN (SELECT DISTINCT product_id FROM public.inventory_transactions
          WHERE organization_id=p_organization_id AND reference_type='journal_entry'
            AND reference_id=v_return.posted_journal_entry_id
            AND transaction_type='sales_return') x ON x.product_id=p.id
   WHERE p.organization_id=p_organization_id ORDER BY p.id FOR UPDATE OF p;

  FOR v_item IN
    SELECT product_id, sum(quantity)::numeric(20,6) qty,
           sum(total_value)::numeric(20,4) val
      FROM public.inventory_transactions
     WHERE organization_id=p_organization_id AND reference_type='journal_entry'
       AND reference_id=v_return.posted_journal_entry_id
       AND transaction_type='sales_return' AND direction='in'
     GROUP BY product_id ORDER BY product_id
  LOOP
    SELECT * INTO v_balance FROM public.inventory_balances
     WHERE organization_id=p_organization_id AND product_id=v_item.product_id FOR UPDATE;
    IF NOT FOUND OR v_balance.quantity<v_item.qty OR v_balance.inventory_value<v_item.val THEN
      RAISE EXCEPTION 'Cannot reverse sales return: returned inventory has already been consumed or revalued for product %',v_item.product_id USING ERRCODE='23514';
    END IF;
    v_new_qty:=v_balance.quantity-v_item.qty;
    v_new_value:=round(v_balance.inventory_value-v_item.val,4);
    IF v_new_qty<0 OR v_new_value<0 THEN
      RAISE EXCEPTION 'Sales return reversal would create negative inventory' USING ERRCODE='23514';
    END IF;
    v_avg:=CASE WHEN v_new_qty=0 THEN 0 ELSE round(v_new_value/v_new_qty,6) END;
    UPDATE public.inventory_balances
       SET quantity=v_new_qty,inventory_value=v_new_value,average_cost=v_avg,
           updated_by=v_user,updated_at=now()
     WHERE organization_id=p_organization_id AND product_id=v_item.product_id;
    INSERT INTO public.inventory_transactions(
      organization_id,code,product_id,transaction_date,transaction_type,direction,quantity,unit_cost,total_value,
      reference_type,reference_id,unit_cost_before,average_cost_after,created_by
    ) VALUES (
      p_organization_id,private.allocate_document_number(p_organization_id,'inventory_transactions'),
      v_item.product_id,p_reversal_date,'sales_return_reversal','out',v_item.qty,
      CASE WHEN v_item.qty=0 THEN 0 ELSE round(v_item.val/v_item.qty,6) END,v_item.val,
      'journal_entry',v_return.posted_journal_entry_id,v_balance.average_cost,v_avg,v_user
    );
  END LOOP;

  v_journal:=private.reverse_source_journal(
    p_organization_id,v_return.posted_journal_entry_id,'sales_return',p_return_id,p_reversal_date,p_reason
  );
  PERFORM set_config('zero_erp.allow_workflow','on',true);
  UPDATE public.sales_returns
     SET status='reversed',reversal_journal_entry_id=v_journal,reversed_at=now(),
         reversed_by=v_user,reversal_reason=btrim(p_reason),updated_by=v_user,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_return_id AND status='posted';
  IF NOT FOUND THEN RAISE EXCEPTION 'Sales return reversal metadata could not be finalized' USING ERRCODE='23514'; END IF;
  RETURN v_journal;
END;
$function$;

DO $extend_reversal$
DECLARE v_def text;
BEGIN
  v_def:=pg_get_functiondef('private.reverse_source_journal(uuid,uuid,text,uuid,date,text)'::regprocedure);
  v_def:=replace(v_def,
    'IF p_source_type NOT IN (''payment'',''expense'') OR p_source_id IS NULL THEN',
    'IF p_source_type NOT IN (''payment'',''expense'',''purchase_return'',''sales_return'') OR p_source_id IS NULL THEN');
  IF position('purchase_return' in v_def)=0 OR position('sales_return' in v_def)=0 THEN
    RAISE EXCEPTION 'Could not safely extend source journal reversal types';
  END IF;
  EXECUTE v_def;
END;
$extend_reversal$;

CREATE POLICY private_templates_postgres_access
ON private.default_account_templates
FOR ALL TO postgres USING (true) WITH CHECK (true);
CREATE POLICY private_expense_templates_postgres_access
ON private.default_expense_category_templates
FOR ALL TO postgres USING (true) WITH CHECK (true);


REVOKE EXECUTE ON FUNCTION public.reverse_purchase_return(uuid,uuid,date,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.reverse_sales_return(uuid,uuid,date,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reverse_purchase_return(uuid,uuid,date,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_sales_return(uuid,uuid,date,text) TO authenticated;

COMMIT;
