-- ZERO ERP V1: atomic purchase-return and sales-return workflows.
-- Purchase returns relieve stock at current moving-average cost; variance is
-- posted to the configured expense account. Sales returns restore stock at the
-- original sale COGS and reverse the source sale's net revenue.
BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS purchase_return_items_one_source_line_uidx
  ON public.purchase_return_items(organization_id,purchase_return_id,purchase_item_id);
CREATE UNIQUE INDEX IF NOT EXISTS sales_return_items_one_source_line_uidx
  ON public.sales_return_items(organization_id,sales_return_id,sales_item_id);

CREATE OR REPLACE FUNCTION private.purchase_return_net_lines(p_organization_id uuid,p_return_id uuid)
RETURNS TABLE(item_id uuid,purchase_item_id uuid,product_id uuid,quantity numeric,net_line_total numeric)
LANGUAGE sql STABLE SET search_path = ''
AS $function$
WITH header AS (
 SELECT r.subtotal,r.discount_amount FROM public.purchase_returns r
 WHERE r.organization_id=p_organization_id AND r.id=p_return_id
), base AS (
 SELECT i.id AS item_id,i.purchase_item_id,i.product_id,i.quantity,i.line_total,i.line_number,
        h.subtotal,h.discount_amount,
        CASE WHEN h.subtotal=0 THEN 0 ELSE h.discount_amount*10000*i.line_total/h.subtotal END AS exact_discount_units,
        floor(CASE WHEN h.subtotal=0 THEN 0 ELSE h.discount_amount*10000*i.line_total/h.subtotal END) AS base_discount_units
 FROM public.purchase_return_items i CROSS JOIN header h
 WHERE i.organization_id=p_organization_id AND i.purchase_return_id=p_return_id
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
SELECT a.item_id,a.purchase_item_id,a.product_id,a.quantity,
       round(a.line_total-a.discount_units/10000,4)
FROM allocated a;
$function$;

CREATE OR REPLACE FUNCTION private.sales_return_net_lines(p_organization_id uuid,p_return_id uuid)
RETURNS TABLE(item_id uuid,sales_item_id uuid,product_id uuid,quantity numeric,net_line_total numeric)
LANGUAGE sql STABLE SET search_path = ''
AS $function$
WITH header AS (
 SELECT r.subtotal,r.discount_amount FROM public.sales_returns r
 WHERE r.organization_id=p_organization_id AND r.id=p_return_id
), base AS (
 SELECT i.id AS item_id,i.sales_item_id,i.product_id,i.quantity,i.line_total,i.line_number,
        h.subtotal,h.discount_amount,
        CASE WHEN h.subtotal=0 THEN 0 ELSE h.discount_amount*10000*i.line_total/h.subtotal END AS exact_discount_units,
        floor(CASE WHEN h.subtotal=0 THEN 0 ELSE h.discount_amount*10000*i.line_total/h.subtotal END) AS base_discount_units
 FROM public.sales_return_items i CROSS JOIN header h
 WHERE i.organization_id=p_organization_id AND i.sales_return_id=p_return_id
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
SELECT a.item_id,a.sales_item_id,a.product_id,a.quantity,
       round(a.line_total-a.discount_units/10000,4)
FROM allocated a;
$function$;

REVOKE ALL ON FUNCTION private.purchase_return_net_lines(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.sales_return_net_lines(uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.post_purchase_return(p_organization_id uuid,p_return_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid:=auth.uid();
  v_org_status text;
  v_return public.purchase_returns%ROWTYPE;
  v_source public.purchase%ROWTYPE;
  v_payable_type text;
  v_variance_type text;
  v_line_count bigint;
  v_subtotal numeric(20,4);
  v_invalid bigint;
  v_journal_id uuid:=gen_random_uuid();
  v_line_no integer:=0;
  v_product record;
  v_account record;
  v_balance public.inventory_balances%ROWTYPE;
  v_cost_removed numeric(20,4);
  v_total_cost_removed numeric(20,4):=0;
  v_variance numeric(20,4);
  v_new_qty numeric(20,6);
  v_new_value numeric(20,4);
  v_new_average numeric(20,6);
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  SELECT o.status INTO v_org_status FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Purchase return posting requires an active organization' USING ERRCODE='23514';
  END IF;

  SELECT r.* INTO v_return FROM public.purchase_returns r
   WHERE r.organization_id=p_organization_id AND r.id=p_return_id FOR UPDATE;
  IF NOT FOUND OR v_return.status<>'draft' OR v_return.posted_journal_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Purchase return not found, not draft, or already posted' USING ERRCODE='23514';
  END IF;

  SELECT p.* INTO v_source FROM public.purchase p
   WHERE p.organization_id=p_organization_id AND p.id=v_return.purchase_id FOR UPDATE;
  IF NOT FOUND OR v_source.status<>'posted' OR v_source.supplier_id IS DISTINCT FROM v_return.supplier_id THEN
    RAISE EXCEPTION 'Purchase return must reference its posted source purchase and supplier' USING ERRCODE='23514';
  END IF;
  IF v_return.payable_account_id IS DISTINCT FROM v_source.payable_account_id THEN
    RAISE EXCEPTION 'Purchase return must use the source purchase payable account' USING ERRCODE='23514';
  END IF;

  SELECT a.account_type INTO v_payable_type
    FROM public.accounts a
   WHERE a.organization_id=p_organization_id AND a.id=v_return.payable_account_id
     AND a.status='active' AND a.is_postable;
  IF v_payable_type IS DISTINCT FROM 'liability' THEN
    RAISE EXCEPTION 'Purchase return payable account must be an active postable liability' USING ERRCODE='23514';
  END IF;

  SELECT count(*),COALESCE(sum(i.line_total),0),
         count(*) FILTER (WHERE i.quantity<=0 OR i.unit_cost<0 OR i.line_total<>round(i.quantity*i.unit_cost,4))
    INTO v_line_count,v_subtotal,v_invalid
    FROM public.purchase_return_items i
   WHERE i.organization_id=p_organization_id AND i.purchase_return_id=p_return_id;
  IF v_line_count=0 OR v_invalid>0 OR round(v_subtotal,4)<>v_return.subtotal
     OR v_return.discount_amount<0 OR v_return.discount_amount>v_return.subtotal
     OR v_return.total_amount<>round(v_return.subtotal-v_return.discount_amount,4)
     OR v_return.total_amount<=0 THEN
    RAISE EXCEPTION 'Purchase return lines or header totals are invalid' USING ERRCODE='23514';
  END IF;

  SELECT count(*) INTO v_invalid
    FROM private.purchase_return_net_lines(p_organization_id,p_return_id) current_line
    JOIN private.purchase_net_lines(p_organization_id,v_source.id) source_line
      ON source_line.item_id=current_line.purchase_item_id
    LEFT JOIN LATERAL (
      SELECT COALESCE(sum(pri.quantity),0) AS returned_qty,
             COALESCE(sum(prn.net_line_total),0) AS returned_value
        FROM public.purchase_return_items pri
        JOIN public.purchase_returns pr
          ON pr.organization_id=pri.organization_id AND pr.id=pri.purchase_return_id
         AND pr.status='posted' AND pr.id<>p_return_id
        JOIN private.purchase_return_net_lines(pri.organization_id,pr.id) prn
          ON prn.item_id=pri.id
       WHERE pri.organization_id=p_organization_id
         AND pri.purchase_item_id=current_line.purchase_item_id
    ) prior ON true
   WHERE current_line.quantity+prior.returned_qty>source_line.quantity
      OR current_line.net_line_total+prior.returned_value>source_line.net_line_total;
  IF v_invalid>0 THEN
    RAISE EXCEPTION 'Purchase return quantity or value exceeds the unreturned source purchase line' USING ERRCODE='23514';
  END IF;

  SELECT count(*) INTO v_invalid
    FROM private.purchase_return_net_lines(p_organization_id,p_return_id) n
    JOIN public.products p ON p.organization_id=p_organization_id AND p.id=n.product_id
    JOIN public.accounts a ON a.organization_id=p.organization_id AND a.id=p.inventory_account_id
   WHERE p.status IS NOT TRUE OR a.account_type<>'asset' OR a.status<>'active' OR NOT a.is_postable;
  IF v_invalid>0 THEN
    RAISE EXCEPTION 'Purchase return products must map to active postable inventory asset accounts' USING ERRCODE='23514';
  END IF;

  PERFORM p.id
    FROM public.products p
    JOIN private.purchase_return_net_lines(p_organization_id,p_return_id) n ON n.product_id=p.id
   WHERE p.organization_id=p_organization_id
   ORDER BY p.id FOR UPDATE OF p;

  FOR v_product IN
    SELECT n.product_id,sum(n.quantity)::numeric(20,6) AS quantity,
           p.inventory_account_id
      FROM private.purchase_return_net_lines(p_organization_id,p_return_id) n
      JOIN public.products p ON p.organization_id=p_organization_id AND p.id=n.product_id
     GROUP BY n.product_id,p.inventory_account_id
     ORDER BY n.product_id
  LOOP
    SELECT b.* INTO v_balance FROM public.inventory_balances b
     WHERE b.organization_id=p_organization_id AND b.product_id=v_product.product_id FOR UPDATE;
    IF NOT FOUND OR v_balance.quantity<v_product.quantity OR v_balance.quantity<=0 THEN
      RAISE EXCEPTION 'Insufficient inventory to process purchase return for product %',v_product.product_id USING ERRCODE='23514';
    END IF;
    v_cost_removed:=CASE WHEN v_product.quantity=v_balance.quantity
                         THEN v_balance.inventory_value
                         ELSE round(v_product.quantity*v_balance.average_cost,4) END;
    v_total_cost_removed:=v_total_cost_removed+v_cost_removed;
  END LOOP;

  v_variance:=round(v_total_cost_removed-v_return.total_amount,4);
  IF v_variance<>0 THEN
    SELECT a.account_type INTO v_variance_type
      FROM public.accounts a
     WHERE a.organization_id=p_organization_id
       AND a.id=v_return.purchase_return_variance_account_id
       AND a.status='active' AND a.is_postable;
    IF v_variance_type IS DISTINCT FROM 'expense' THEN
      RAISE EXCEPTION 'A purchase return variance requires an active postable expense account' USING ERRCODE='23514';
    END IF;
  END IF;

  PERFORM set_config('zero_erp.allow_workflow','on',true);
  INSERT INTO public.journal_entries(
    id,organization_id,entry_date,entry_type,status,reference_type,reference_id,
    description,created_by,created_at,updated_by,updated_at
  )
  VALUES(
    v_journal_id,p_organization_id,v_return.return_date,'purchase_return','draft',
    'purchase_return',p_return_id,'Purchase return '||COALESCE(v_return.code,p_return_id::text),
    v_user_id,now(),v_user_id,now()
  );

  v_line_no:=v_line_no+1;
  INSERT INTO public.account_transactions(
    organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by
  )
  VALUES(
    p_organization_id,v_journal_id,v_return.payable_account_id,v_line_no,'Supplier payable reduction',
    v_return.total_amount,0,v_return.supplier_id,v_user_id,v_user_id
  );

  FOR v_account IN
    SELECT p.inventory_account_id AS account_id,
           sum(CASE WHEN n.quantity=b.quantity THEN b.inventory_value
                    ELSE round(n.quantity*b.average_cost,4) END) AS amount
      FROM (
        SELECT product_id,sum(quantity)::numeric(20,6) AS quantity
          FROM private.purchase_return_net_lines(p_organization_id,p_return_id)
         GROUP BY product_id
      ) n
      JOIN public.products p ON p.organization_id=p_organization_id AND p.id=n.product_id
      JOIN public.inventory_balances b ON b.organization_id=p_organization_id AND b.product_id=n.product_id
     GROUP BY p.inventory_account_id
     ORDER BY p.inventory_account_id
  LOOP
    IF v_account.amount>0 THEN
      v_line_no:=v_line_no+1;
      INSERT INTO public.account_transactions(
        organization_id,journal_entry_id,account_id,line_number,description,debit,credit,created_by,updated_by
      )
      VALUES(p_organization_id,v_journal_id,v_account.account_id,v_line_no,'Inventory returned to supplier',
             0,v_account.amount,v_user_id,v_user_id);
    END IF;
  END LOOP;

  IF v_variance>0 THEN
    v_line_no:=v_line_no+1;
    INSERT INTO public.account_transactions(
      organization_id,journal_entry_id,account_id,line_number,description,debit,credit,created_by,updated_by
    )
    VALUES(p_organization_id,v_journal_id,v_return.purchase_return_variance_account_id,v_line_no,
           'Purchase return cost variance',v_variance,0,v_user_id,v_user_id);
  ELSIF v_variance<0 THEN
    v_line_no:=v_line_no+1;
    INSERT INTO public.account_transactions(
      organization_id,journal_entry_id,account_id,line_number,description,debit,credit,created_by,updated_by
    )
    VALUES(p_organization_id,v_journal_id,v_return.purchase_return_variance_account_id,v_line_no,
           'Purchase return cost variance',0,abs(v_variance),v_user_id,v_user_id);
  END IF;

  FOR v_product IN
    SELECT n.product_id,sum(n.quantity)::numeric(20,6) AS quantity,
           p.inventory_account_id
      FROM private.purchase_return_net_lines(p_organization_id,p_return_id) n
      JOIN public.products p ON p.organization_id=p_organization_id AND p.id=n.product_id
     GROUP BY n.product_id,p.inventory_account_id
     ORDER BY n.product_id
  LOOP
    SELECT b.* INTO v_balance FROM public.inventory_balances b
     WHERE b.organization_id=p_organization_id AND b.product_id=v_product.product_id FOR UPDATE;
    v_cost_removed:=CASE WHEN v_product.quantity=v_balance.quantity
                         THEN v_balance.inventory_value
                         ELSE round(v_product.quantity*v_balance.average_cost,4) END;
    v_new_qty:=v_balance.quantity-v_product.quantity;
    v_new_value:=CASE WHEN v_new_qty=0 THEN 0 ELSE round(v_balance.inventory_value-v_cost_removed,4) END;
    v_new_average:=CASE WHEN v_new_qty=0 THEN 0 ELSE round(v_new_value/v_new_qty,6) END;

    INSERT INTO public.inventory_transactions(
      organization_id,code,product_id,transaction_date,transaction_type,direction,
      quantity,unit_cost,total_value,reference_type,reference_id,unit_cost_before,
      average_cost_after,created_by
    )
    VALUES(
      p_organization_id,private.allocate_document_number(p_organization_id,'inventory_transactions'),
      v_product.product_id,v_return.return_date,'purchase_return','out',v_product.quantity,
      CASE WHEN v_product.quantity=0 THEN 0 ELSE round(v_cost_removed/v_product.quantity,6) END,
      v_cost_removed,'journal_entry',v_journal_id,v_balance.average_cost,v_new_average,v_user_id
    );

    UPDATE public.inventory_balances
       SET quantity=v_new_qty,inventory_value=v_new_value,average_cost=v_new_average,
           updated_by=v_user_id,updated_at=now()
     WHERE organization_id=p_organization_id AND product_id=v_product.product_id;
  END LOOP;

  PERFORM public.post_journal_entry(p_organization_id,v_journal_id);
  UPDATE public.purchase_returns
     SET code=COALESCE(code,private.allocate_document_number(p_organization_id,'purchase_returns')),
         status='posted',confirmed_at=now(),confirmed_by=v_user_id,posted_by=v_user_id,
         posted_journal_entry_id=v_journal_id,updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_return_id AND status='draft';
  IF NOT FOUND THEN RAISE EXCEPTION 'Purchase return posting failed' USING ERRCODE='23514'; END IF;
  RETURN v_journal_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.post_sales_return(p_organization_id uuid,p_return_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid:=auth.uid();
  v_org_status text;
  v_return public.sales_returns%ROWTYPE;
  v_source public.sales%ROWTYPE;
  v_receivable_type text;
  v_line_count bigint;
  v_subtotal numeric(20,4);
  v_invalid bigint;
  v_journal_id uuid:=gen_random_uuid();
  v_line_no integer:=0;
  v_product record;
  v_account record;
  v_balance public.inventory_balances%ROWTYPE;
  v_unit_cost numeric(20,6);
  v_cogs_total numeric(20,4);
  v_new_qty numeric(20,6);
  v_new_value numeric(20,4);
  v_new_average numeric(20,6);
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  SELECT o.status INTO v_org_status FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Sales return posting requires an active organization' USING ERRCODE='23514';
  END IF;

  SELECT r.* INTO v_return FROM public.sales_returns r
   WHERE r.organization_id=p_organization_id AND r.id=p_return_id FOR UPDATE;
  IF NOT FOUND OR v_return.status<>'draft' OR v_return.posted_journal_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Sales return not found, not draft, or already posted' USING ERRCODE='23514';
  END IF;

  SELECT s.* INTO v_source FROM public.sales s
   WHERE s.organization_id=p_organization_id AND s.id=v_return.sales_id FOR UPDATE;
  IF NOT FOUND OR v_source.status<>'posted' OR v_source.customer_id IS DISTINCT FROM v_return.customer_id THEN
    RAISE EXCEPTION 'Sales return must reference its posted source sale and customer' USING ERRCODE='23514';
  END IF;
  IF v_return.receivable_account_id IS DISTINCT FROM v_source.receivable_account_id THEN
    RAISE EXCEPTION 'Sales return must use the source sale receivable account' USING ERRCODE='23514';
  END IF;

  SELECT a.account_type INTO v_receivable_type
    FROM public.accounts a
   WHERE a.organization_id=p_organization_id AND a.id=v_return.receivable_account_id
     AND a.status='active' AND a.is_postable;
  IF v_receivable_type IS DISTINCT FROM 'asset' THEN
    RAISE EXCEPTION 'Sales return receivable account must be an active postable asset' USING ERRCODE='23514';
  END IF;

  SELECT count(*),COALESCE(sum(i.line_total),0),
         count(*) FILTER (WHERE i.quantity<=0 OR i.unit_price<0 OR i.line_total<>round(i.quantity*i.unit_price,4))
    INTO v_line_count,v_subtotal,v_invalid
    FROM public.sales_return_items i
   WHERE i.organization_id=p_organization_id AND i.sales_return_id=p_return_id;
  IF v_line_count=0 OR v_invalid>0 OR round(v_subtotal,4)<>v_return.subtotal
     OR v_return.discount_amount<0 OR v_return.discount_amount>v_return.subtotal
     OR v_return.total_amount<>round(v_return.subtotal-v_return.discount_amount,4)
     OR v_return.total_amount<=0 THEN
    RAISE EXCEPTION 'Sales return lines or header totals are invalid' USING ERRCODE='23514';
  END IF;

  SELECT count(*) INTO v_invalid
    FROM private.sales_return_net_lines(p_organization_id,p_return_id) current_line
    JOIN private.sales_net_lines(p_organization_id,v_source.id) source_line
      ON source_line.item_id=current_line.sales_item_id
    LEFT JOIN LATERAL (
      SELECT COALESCE(sum(sri.quantity),0) AS returned_qty,
             COALESCE(sum(srn.net_line_total),0) AS returned_value
        FROM public.sales_return_items sri
        JOIN public.sales_returns sr
          ON sr.organization_id=sri.organization_id AND sr.id=sri.sales_return_id
         AND sr.status='posted' AND sr.id<>p_return_id
        JOIN private.sales_return_net_lines(sri.organization_id,sr.id) srn
          ON srn.item_id=sri.id
       WHERE sri.organization_id=p_organization_id
         AND sri.sales_item_id=current_line.sales_item_id
    ) prior ON true
   WHERE current_line.quantity+prior.returned_qty>source_line.quantity
      OR current_line.net_line_total+prior.returned_value>source_line.net_line_total;
  IF v_invalid>0 THEN
    RAISE EXCEPTION 'Sales return quantity or value exceeds the unreturned source sales line' USING ERRCODE='23514';
  END IF;

  SELECT count(*) INTO v_invalid
    FROM private.sales_return_net_lines(p_organization_id,p_return_id) n
    JOIN public.products p ON p.organization_id=p_organization_id AND p.id=n.product_id
    JOIN public.accounts ia ON ia.organization_id=p.organization_id AND ia.id=p.inventory_account_id
    JOIN public.accounts ra ON ra.organization_id=p.organization_id AND ra.id=p.sales_account_id
    JOIN public.accounts ca ON ca.organization_id=p.organization_id AND ca.id=p.cogs_account_id
   WHERE p.status IS NOT TRUE
      OR ia.account_type<>'asset' OR ia.status<>'active' OR NOT ia.is_postable
      OR ra.account_type<>'income' OR ra.status<>'active' OR NOT ra.is_postable
      OR ca.account_type<>'expense' OR ca.status<>'active' OR NOT ca.is_postable;
  IF v_invalid>0 THEN
    RAISE EXCEPTION 'Sales return products must have active postable inventory, income and COGS mappings' USING ERRCODE='23514';
  END IF;

  PERFORM p.id
    FROM public.products p
    JOIN private.sales_return_net_lines(p_organization_id,p_return_id) n ON n.product_id=p.id
   WHERE p.organization_id=p_organization_id
   ORDER BY p.id FOR UPDATE OF p;

  -- Restore each return line's COGS from the source posted sale, not user input.
  UPDATE public.sales_return_items ri
     SET cogs_unit_cost=si.cogs_unit_cost,
         cogs_total=CASE
           WHEN ri.quantity+COALESCE(prior.returned_qty,0)=si.quantity
             THEN round(si.cogs_total-COALESCE(prior.returned_cogs,0),4)
           ELSE round(ri.quantity*si.cogs_unit_cost,4)
         END,
         updated_by=v_user_id,updated_at=now()
    FROM public.sales_items si
    LEFT JOIN LATERAL (
      SELECT COALESCE(sum(sri.quantity),0) AS returned_qty,
             COALESCE(sum(sri.cogs_total),0) AS returned_cogs
        FROM public.sales_return_items sri
        JOIN public.sales_returns sr
          ON sr.organization_id=sri.organization_id AND sr.id=sri.sales_return_id
         AND sr.status='posted' AND sr.id<>p_return_id
       WHERE sri.organization_id=si.organization_id AND sri.sales_item_id=si.id
    ) prior ON true
   WHERE ri.organization_id=p_organization_id AND ri.sales_return_id=p_return_id
     AND si.organization_id=ri.organization_id AND si.id=ri.sales_item_id;

  IF EXISTS(SELECT 1 FROM public.sales_return_items WHERE organization_id=p_organization_id AND sales_return_id=p_return_id AND cogs_total<0) THEN
    RAISE EXCEPTION 'Sales return COGS allocation is invalid' USING ERRCODE='23514';
  END IF;

  PERFORM set_config('zero_erp.allow_workflow','on',true);
  INSERT INTO public.journal_entries(
    id,organization_id,entry_date,entry_type,status,reference_type,reference_id,
    description,created_by,created_at,updated_by,updated_at
  )
  VALUES(
    v_journal_id,p_organization_id,v_return.return_date,'sales_return','draft',
    'sales_return',p_return_id,'Sales return '||COALESCE(v_return.code,p_return_id::text),
    v_user_id,now(),v_user_id,now()
  );

  FOR v_account IN
    SELECT p.sales_account_id AS account_id,sum(n.net_line_total) AS amount
      FROM private.sales_return_net_lines(p_organization_id,p_return_id) n
      JOIN public.products p ON p.organization_id=p_organization_id AND p.id=n.product_id
     GROUP BY p.sales_account_id ORDER BY p.sales_account_id
  LOOP
    IF v_account.amount>0 THEN
      v_line_no:=v_line_no+1;
      INSERT INTO public.account_transactions(
        organization_id,journal_entry_id,account_id,line_number,description,debit,credit,created_by,updated_by
      )
      VALUES(p_organization_id,v_journal_id,v_account.account_id,v_line_no,'Sales returns and allowances',
             v_account.amount,0,v_user_id,v_user_id);
    END IF;
  END LOOP;

  v_line_no:=v_line_no+1;
  INSERT INTO public.account_transactions(
    organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by
  )
  VALUES(
    p_organization_id,v_journal_id,v_return.receivable_account_id,v_line_no,'Customer receivable reduction',
    0,v_return.total_amount,v_return.customer_id,v_user_id,v_user_id
  );

  FOR v_account IN
    SELECT p.inventory_account_id AS account_id,sum(i.cogs_total) AS amount
      FROM public.sales_return_items i
      JOIN public.products p ON p.organization_id=i.organization_id AND p.id=i.product_id
     WHERE i.organization_id=p_organization_id AND i.sales_return_id=p_return_id
     GROUP BY p.inventory_account_id ORDER BY p.inventory_account_id
  LOOP
    IF v_account.amount>0 THEN
      v_line_no:=v_line_no+1;
      INSERT INTO public.account_transactions(
        organization_id,journal_entry_id,account_id,line_number,description,debit,credit,created_by,updated_by
      )
      VALUES(p_organization_id,v_journal_id,v_account.account_id,v_line_no,'Inventory restored from customer return',
             v_account.amount,0,v_user_id,v_user_id);
    END IF;
  END LOOP;

  FOR v_account IN
    SELECT p.cogs_account_id AS account_id,sum(i.cogs_total) AS amount
      FROM public.sales_return_items i
      JOIN public.products p ON p.organization_id=i.organization_id AND p.id=i.product_id
     WHERE i.organization_id=p_organization_id AND i.sales_return_id=p_return_id
     GROUP BY p.cogs_account_id ORDER BY p.cogs_account_id
  LOOP
    IF v_account.amount>0 THEN
      v_line_no:=v_line_no+1;
      INSERT INTO public.account_transactions(
        organization_id,journal_entry_id,account_id,line_number,description,debit,credit,created_by,updated_by
      )
      VALUES(p_organization_id,v_journal_id,v_account.account_id,v_line_no,'Reverse cost of goods sold',
             0,v_account.amount,v_user_id,v_user_id);
    END IF;
  END LOOP;

  FOR v_product IN
    SELECT i.product_id,sum(i.quantity)::numeric(20,6) AS quantity,
           sum(i.cogs_total)::numeric(20,4) AS total_value
      FROM public.sales_return_items i
     WHERE i.organization_id=p_organization_id AND i.sales_return_id=p_return_id
     GROUP BY i.product_id ORDER BY i.product_id
  LOOP
    SELECT b.* INTO v_balance FROM public.inventory_balances b
     WHERE b.organization_id=p_organization_id AND b.product_id=v_product.product_id FOR UPDATE;
    IF NOT FOUND THEN
      INSERT INTO public.inventory_balances(
        organization_id,product_id,quantity,average_cost,inventory_value,created_by,updated_by,updated_at
      )
      VALUES(
        p_organization_id,v_product.product_id,v_product.quantity,
        CASE WHEN v_product.quantity=0 THEN 0 ELSE round(v_product.total_value/v_product.quantity,6) END,
        v_product.total_value,v_user_id,v_user_id,now()
      );
      v_new_qty:=v_product.quantity;
      v_new_value:=v_product.total_value;
      v_new_average:=CASE WHEN v_new_qty=0 THEN 0 ELSE round(v_new_value/v_new_qty,6) END;
    ELSE
      v_new_qty:=v_balance.quantity+v_product.quantity;
      v_new_value:=round(v_balance.inventory_value+v_product.total_value,4);
      v_new_average:=CASE WHEN v_new_qty=0 THEN 0 ELSE round(v_new_value/v_new_qty,6) END;
      UPDATE public.inventory_balances
         SET quantity=v_new_qty,inventory_value=v_new_value,average_cost=v_new_average,
             updated_by=v_user_id,updated_at=now()
       WHERE organization_id=p_organization_id AND product_id=v_product.product_id;
    END IF;

    INSERT INTO public.inventory_transactions(
      organization_id,code,product_id,transaction_date,transaction_type,direction,
      quantity,unit_cost,total_value,reference_type,reference_id,unit_cost_before,
      average_cost_after,created_by
    )
    VALUES(
      p_organization_id,private.allocate_document_number(p_organization_id,'inventory_transactions'),
      v_product.product_id,v_return.return_date,'sales_return','in',v_product.quantity,
      CASE WHEN v_product.quantity=0 THEN 0 ELSE round(v_product.total_value/v_product.quantity,6) END,
      v_product.total_value,'journal_entry',v_journal_id,
      CASE WHEN v_balance.id IS NOT NULL THEN v_balance.average_cost ELSE NULL END,
      v_new_average,v_user_id
    );
  END LOOP;

  PERFORM public.post_journal_entry(p_organization_id,v_journal_id);
  UPDATE public.sales_returns
     SET code=COALESCE(code,private.allocate_document_number(p_organization_id,'sales_returns')),
         status='posted',confirmed_at=now(),confirmed_by=v_user_id,posted_by=v_user_id,
         posted_journal_entry_id=v_journal_id,updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_return_id AND status='draft';
  IF NOT FOUND THEN RAISE EXCEPTION 'Sales return posting failed' USING ERRCODE='23514'; END IF;
  RETURN v_journal_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.post_purchase_return(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.post_purchase_return(uuid,uuid) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.post_sales_return(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.post_sales_return(uuid,uuid) TO authenticated,service_role;

COMMIT;
