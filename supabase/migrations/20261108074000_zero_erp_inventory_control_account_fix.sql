-- ZERO ERP V1: atomic purchase and sales posting workflows.
BEGIN;

CREATE OR REPLACE FUNCTION private.purchase_net_lines(p_organization_id uuid,p_purchase_id uuid)
RETURNS TABLE(
  item_id uuid, product_id uuid, quantity numeric, unit_cost numeric,
  line_total numeric, net_line_total numeric
)
LANGUAGE sql
STABLE
SET search_path = ''
AS $function$
  WITH header AS (
    SELECT p.subtotal,p.discount_amount,p.total_amount
      FROM public.purchase p
     WHERE p.organization_id=p_organization_id AND p.id=p_purchase_id
  ),
  ranked AS (
    SELECT i.id AS item_id,i.product_id,i.quantity,i.unit_cost,i.line_total,
           h.total_amount,
           row_number() OVER (ORDER BY i.line_number,i.id) AS rn,
           count(*) OVER () AS cnt,
           round(CASE WHEN h.subtotal=0 THEN 0
                      ELSE i.line_total*h.discount_amount/h.subtotal END,4) AS discount_alloc
      FROM public.purchase_items i
      CROSS JOIN header h
     WHERE i.organization_id=p_organization_id AND i.purchase_id=p_purchase_id
  ),
  allocated AS (
    SELECT r.*,
           round(r.line_total-r.discount_alloc,4) AS provisional_net,
           sum(CASE WHEN r.rn<r.cnt THEN round(r.line_total-r.discount_alloc,4) ELSE 0 END) OVER () AS prior_net
      FROM ranked r
  )
  SELECT a.item_id,a.product_id,a.quantity,a.unit_cost,a.line_total,
         CASE WHEN a.rn=a.cnt THEN round(a.total_amount-a.prior_net,4)
              ELSE a.provisional_net END
    FROM allocated a;
$function$;

CREATE OR REPLACE FUNCTION private.sales_net_lines(p_organization_id uuid,p_sales_id uuid)
RETURNS TABLE(
  item_id uuid, product_id uuid, quantity numeric, unit_price numeric,
  line_total numeric, net_line_total numeric
)
LANGUAGE sql
STABLE
SET search_path = ''
AS $function$
  WITH header AS (
    SELECT s.subtotal,s.discount_amount,s.total_amount
      FROM public.sales s
     WHERE s.organization_id=p_organization_id AND s.id=p_sales_id
  ),
  ranked AS (
    SELECT i.id AS item_id,i.product_id,i.quantity,i.unit_price,i.line_total,
           h.total_amount,
           row_number() OVER (ORDER BY i.line_number,i.id) AS rn,
           count(*) OVER () AS cnt,
           round(CASE WHEN h.subtotal=0 THEN 0
                      ELSE i.line_total*h.discount_amount/h.subtotal END,4) AS discount_alloc
      FROM public.sales_items i
      CROSS JOIN header h
     WHERE i.organization_id=p_organization_id AND i.sales_id=p_sales_id
  ),
  allocated AS (
    SELECT r.*,
           round(r.line_total-r.discount_alloc,4) AS provisional_net,
           sum(CASE WHEN r.rn<r.cnt THEN round(r.line_total-r.discount_alloc,4) ELSE 0 END) OVER () AS prior_net
      FROM ranked r
  )
  SELECT a.item_id,a.product_id,a.quantity,a.unit_price,a.line_total,
         CASE WHEN a.rn=a.cnt THEN round(a.total_amount-a.prior_net,4)
              ELSE a.provisional_net END
    FROM allocated a;
$function$;

REVOKE ALL ON FUNCTION private.purchase_net_lines(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.sales_net_lines(uuid,uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.post_purchase(p_organization_id uuid,p_purchase_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid:=auth.uid();
  v_org_status text;
  v_purchase public.purchase%ROWTYPE;
  v_supplier_status text;
  v_payable_type text;
  v_line_count bigint;
  v_lines_subtotal numeric(20,4);
  v_invalid bigint;
  v_journal_id uuid:=gen_random_uuid();
  v_line_no integer:=0;
  v_account record;
  v_product record;
  v_balance public.inventory_balances%ROWTYPE;
  v_has_balance boolean;
  v_new_qty numeric(20,6);
  v_new_value numeric(20,4);
  v_new_average numeric(20,6);
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;

  SELECT o.status INTO v_org_status
    FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Purchase posting requires an active organization' USING ERRCODE='23514';
  END IF;

  SELECT p.* INTO v_purchase
    FROM public.purchase p
   WHERE p.organization_id=p_organization_id AND p.id=p_purchase_id
   FOR UPDATE;
  IF NOT FOUND OR v_purchase.status<>'draft' OR v_purchase.posted_journal_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Purchase not found, not draft, or already posted' USING ERRCODE='23514';
  END IF;

  SELECT c.status INTO v_supplier_status
    FROM public.contacts c
   WHERE c.organization_id=p_organization_id AND c.id=v_purchase.supplier_id;
  IF v_supplier_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Purchase supplier is missing or inactive' USING ERRCODE='23514';
  END IF;

  SELECT a.account_type INTO v_payable_type
    FROM public.accounts a
   WHERE a.organization_id=p_organization_id AND a.id=v_purchase.payable_account_id
     AND a.status='active' AND a.is_postable;
  IF v_payable_type IS DISTINCT FROM 'liability' THEN
    RAISE EXCEPTION 'Purchase payable account must be an active postable liability account' USING ERRCODE='23514';
  END IF;

  SELECT count(*),COALESCE(sum(i.line_total),0),
         count(*) FILTER (WHERE i.quantity<=0 OR i.unit_cost<0 OR i.line_total<>round(i.quantity*i.unit_cost,4))
    INTO v_line_count,v_lines_subtotal,v_invalid
    FROM public.purchase_items i
   WHERE i.organization_id=p_organization_id AND i.purchase_id=p_purchase_id;
  IF v_line_count=0 OR v_invalid>0
     OR round(v_lines_subtotal,4)<>v_purchase.subtotal
     OR v_purchase.discount_amount<0
     OR v_purchase.discount_amount>v_purchase.subtotal
     OR v_purchase.total_amount<>round(v_purchase.subtotal-v_purchase.discount_amount,4)
     OR v_purchase.total_amount<=0 THEN
    RAISE EXCEPTION 'Purchase lines or header totals are invalid or inconsistent' USING ERRCODE='23514';
  END IF;

  SELECT count(*) INTO v_invalid
    FROM public.purchase_items i
    LEFT JOIN public.products p
      ON p.organization_id=i.organization_id AND p.id=i.product_id
    LEFT JOIN public.accounts a
      ON a.organization_id=p.organization_id AND a.id=p.inventory_account_id
   WHERE i.organization_id=p_organization_id AND i.purchase_id=p_purchase_id
     AND (p.id IS NULL OR p.status IS NOT TRUE OR a.id IS NULL
       OR a.account_type<>'asset' OR a.status<>'active' OR NOT a.is_postable
       );
  IF v_invalid>0 THEN
    RAISE EXCEPTION 'Every purchase product must be active and mapped to an active postable inventory asset account' USING ERRCODE='23514';
  END IF;

  PERFORM p.id
    FROM public.products p
    JOIN public.purchase_items i ON i.organization_id=p.organization_id AND i.product_id=p.id
   WHERE i.organization_id=p_organization_id AND i.purchase_id=p_purchase_id
   ORDER BY p.id
   FOR UPDATE OF p;

  PERFORM set_config('zero_erp.allow_workflow','on',true);

  INSERT INTO public.journal_entries(
    id,organization_id,entry_date,entry_type,status,reference_type,reference_id,
    description,created_by,created_at,updated_by,updated_at
  )
  VALUES(
    v_journal_id,p_organization_id,v_purchase.invoice_date,'purchase','draft',
    'purchase',p_purchase_id,'Purchase '||COALESCE(v_purchase.code,p_purchase_id::text),
    v_user_id,now(),v_user_id,now()
  );

  FOR v_account IN
    SELECT p.inventory_account_id AS account_id,sum(n.net_line_total) AS amount
      FROM private.purchase_net_lines(p_organization_id,p_purchase_id) n
      JOIN public.products p ON p.organization_id=p_organization_id AND p.id=n.product_id
     GROUP BY p.inventory_account_id
     ORDER BY p.inventory_account_id
  LOOP
    IF v_account.amount>0 THEN
      v_line_no:=v_line_no+1;
      INSERT INTO public.account_transactions(
        organization_id,journal_entry_id,account_id,line_number,description,debit,credit,created_by,updated_by
      )
      VALUES(
        p_organization_id,v_journal_id,v_account.account_id,v_line_no,'Inventory received',
        v_account.amount,0,v_user_id,v_user_id
      );
    END IF;
  END LOOP;

  v_line_no:=v_line_no+1;
  INSERT INTO public.account_transactions(
    organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by
  )
  VALUES(
    p_organization_id,v_journal_id,v_purchase.payable_account_id,v_line_no,'Purchase payable',
    0,v_purchase.total_amount,v_purchase.supplier_id,v_user_id,v_user_id
  );

  FOR v_product IN
    SELECT n.product_id,sum(n.quantity)::numeric(20,6) AS quantity,
           sum(n.net_line_total)::numeric(20,4) AS total_value
      FROM private.purchase_net_lines(p_organization_id,p_purchase_id) n
     GROUP BY n.product_id
     ORDER BY n.product_id
  LOOP
    SELECT b.* INTO v_balance
      FROM public.inventory_balances b
     WHERE b.organization_id=p_organization_id AND b.product_id=v_product.product_id
     FOR UPDATE;
    v_has_balance:=FOUND;

    v_new_qty:=COALESCE(v_balance.quantity,0)+v_product.quantity;
    v_new_value:=round(COALESCE(v_balance.inventory_value,0)+v_product.total_value,4);
    v_new_average:=round(v_new_value/v_new_qty,6);

    INSERT INTO public.inventory_transactions(
      organization_id,code,product_id,transaction_date,transaction_type,direction,
      quantity,unit_cost,total_value,reference_type,reference_id,unit_cost_before,
      average_cost_after,created_by
    )
    VALUES(
      p_organization_id,private.allocate_document_number(p_organization_id,'inventory_transactions'),
      v_product.product_id,v_purchase.invoice_date,'purchase','in',v_product.quantity,
      round(v_product.total_value/v_product.quantity,6),v_product.total_value,
      'purchase',p_purchase_id,CASE WHEN v_has_balance THEN v_balance.average_cost ELSE NULL END,
      v_new_average,v_user_id
    );

    IF v_has_balance THEN
      UPDATE public.inventory_balances
         SET quantity=v_new_qty,inventory_value=v_new_value,average_cost=v_new_average,
             updated_by=v_user_id,updated_at=now()
       WHERE organization_id=p_organization_id AND product_id=v_product.product_id;
    ELSE
      INSERT INTO public.inventory_balances(
        organization_id,product_id,quantity,average_cost,inventory_value,created_by,updated_by,updated_at
      )
      VALUES(
        p_organization_id,v_product.product_id,v_new_qty,v_new_average,v_new_value,
        v_user_id,v_user_id,now()
      );
    END IF;
  END LOOP;

  PERFORM public.post_journal_entry(p_organization_id,v_journal_id);

  UPDATE public.purchase
     SET code=COALESCE(code,private.allocate_document_number(p_organization_id,'purchase')),
         status='posted',confirmed_at=now(),confirmed_by=v_user_id,posted_by=v_user_id,
         posted_journal_entry_id=v_journal_id,updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_purchase_id AND status='draft';
  IF NOT FOUND THEN RAISE EXCEPTION 'Purchase posting failed' USING ERRCODE='23514'; END IF;

  RETURN v_journal_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.post_sales(p_organization_id uuid,p_sales_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid:=auth.uid();
  v_org_status text;
  v_sales public.sales%ROWTYPE;
  v_customer_status text;
  v_receivable_type text;
  v_line_count bigint;
  v_lines_subtotal numeric(20,4);
  v_invalid bigint;
  v_journal_id uuid:=gen_random_uuid();
  v_line_no integer:=0;
  v_account record;
  v_product record;
  v_balance public.inventory_balances%ROWTYPE;
  v_has_balance boolean;
  v_unit_cost numeric(20,6);
  v_cogs_total numeric(20,4);
  v_new_qty numeric(20,6);
  v_new_value numeric(20,4);
  v_new_average numeric(20,6);
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;

  SELECT o.status INTO v_org_status
    FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Sales posting requires an active organization' USING ERRCODE='23514';
  END IF;

  SELECT s.* INTO v_sales
    FROM public.sales s
   WHERE s.organization_id=p_organization_id AND s.id=p_sales_id
   FOR UPDATE;
  IF NOT FOUND OR v_sales.status<>'draft' OR v_sales.posted_journal_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Sale not found, not draft, or already posted' USING ERRCODE='23514';
  END IF;

  SELECT c.status INTO v_customer_status
    FROM public.contacts c
   WHERE c.organization_id=p_organization_id AND c.id=v_sales.customer_id;
  IF v_customer_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Sales customer is missing or inactive' USING ERRCODE='23514';
  END IF;

  SELECT a.account_type INTO v_receivable_type
    FROM public.accounts a
   WHERE a.organization_id=p_organization_id AND a.id=v_sales.receivable_account_id
     AND a.status='active' AND a.is_postable;
  IF v_receivable_type IS DISTINCT FROM 'asset' THEN
    RAISE EXCEPTION 'Sales receivable account must be an active postable asset account' USING ERRCODE='23514';
  END IF;

  SELECT count(*),COALESCE(sum(i.line_total),0),
         count(*) FILTER (WHERE i.quantity<=0 OR i.unit_price<0 OR i.line_total<>round(i.quantity*i.unit_price,4))
    INTO v_line_count,v_lines_subtotal,v_invalid
    FROM public.sales_items i
   WHERE i.organization_id=p_organization_id AND i.sales_id=p_sales_id;
  IF v_line_count=0 OR v_invalid>0
     OR round(v_lines_subtotal,4)<>v_sales.subtotal
     OR v_sales.discount_amount<0
     OR v_sales.discount_amount>v_sales.subtotal
     OR v_sales.total_amount<>round(v_sales.subtotal-v_sales.discount_amount,4)
     OR v_sales.total_amount<=0 THEN
    RAISE EXCEPTION 'Sales lines or header totals are invalid or inconsistent' USING ERRCODE='23514';
  END IF;

  SELECT count(*) INTO v_invalid
    FROM public.sales_items i
    LEFT JOIN public.products p
      ON p.organization_id=i.organization_id AND p.id=i.product_id
    LEFT JOIN public.accounts ia
      ON ia.organization_id=p.organization_id AND ia.id=p.inventory_account_id
    LEFT JOIN public.accounts ra
      ON ra.organization_id=p.organization_id AND ra.id=p.sales_account_id
    LEFT JOIN public.accounts ca
      ON ca.organization_id=p.organization_id AND ca.id=p.cogs_account_id
   WHERE i.organization_id=p_organization_id AND i.sales_id=p_sales_id
     AND (p.id IS NULL OR p.status IS NOT TRUE
       OR ia.id IS NULL OR ia.account_type<>'asset' OR ia.status<>'active' OR NOT ia.is_postable 
       OR ra.id IS NULL OR ra.account_type<>'income' OR ra.status<>'active' OR NOT ra.is_postable
       OR ca.id IS NULL OR ca.account_type<>'expense' OR ca.status<>'active' OR NOT ca.is_postable);
  IF v_invalid>0 THEN
    RAISE EXCEPTION 'Every sales product must have active postable inventory, income and COGS account mappings' USING ERRCODE='23514';
  END IF;

  PERFORM p.id
    FROM public.products p
    JOIN public.sales_items i ON i.organization_id=p.organization_id AND i.product_id=p.id
   WHERE i.organization_id=p_organization_id AND i.sales_id=p_sales_id
   ORDER BY p.id
   FOR UPDATE OF p;

  PERFORM set_config('zero_erp.allow_workflow','on',true);

  -- Lock and validate stock first; derive COGS from the moving-average balance.
  FOR v_product IN
    SELECT i.product_id,sum(i.quantity)::numeric(20,6) AS quantity
      FROM public.sales_items i
     WHERE i.organization_id=p_organization_id AND i.sales_id=p_sales_id
     GROUP BY i.product_id
     ORDER BY i.product_id
  LOOP
    SELECT b.* INTO v_balance
      FROM public.inventory_balances b
     WHERE b.organization_id=p_organization_id AND b.product_id=v_product.product_id
     FOR UPDATE;
    v_has_balance:=FOUND;
    IF NOT v_has_balance OR v_balance.quantity<v_product.quantity OR v_balance.quantity<=0 THEN
      RAISE EXCEPTION 'Insufficient inventory for product %',v_product.product_id USING ERRCODE='23514';
    END IF;

    IF v_product.quantity=v_balance.quantity THEN
      v_cogs_total:=v_balance.inventory_value;
      v_unit_cost:=round(v_balance.inventory_value/v_balance.quantity,6);
    ELSE
      v_unit_cost:=v_balance.average_cost;
      v_cogs_total:=round(v_product.quantity*v_unit_cost,4);
    END IF;

    WITH ranked AS (
      SELECT i.id,i.quantity,
             row_number() OVER (ORDER BY i.line_number,i.id) AS rn,
             count(*) OVER () AS cnt,
             round(i.quantity*v_unit_cost,4) AS provisional
        FROM public.sales_items i
       WHERE i.organization_id=p_organization_id AND i.sales_id=p_sales_id
         AND i.product_id=v_product.product_id
    ),
    adjusted AS (
      SELECT r.*,
             sum(CASE WHEN r.rn<r.cnt THEN r.provisional ELSE 0 END) OVER () AS prior_total
        FROM ranked r
    )
    UPDATE public.sales_items i
       SET cogs_unit_cost=v_unit_cost,
           cogs_total=CASE WHEN a.rn=a.cnt THEN round(v_cogs_total-a.prior_total,4)
                           ELSE a.provisional END
      FROM adjusted a
     WHERE i.id=a.id;
  END LOOP;

  INSERT INTO public.journal_entries(
    id,organization_id,entry_date,entry_type,status,reference_type,reference_id,
    description,created_by,created_at,updated_by,updated_at
  )
  VALUES(
    v_journal_id,p_organization_id,v_sales.invoice_date,'sale','draft',
    'sales',p_sales_id,'Sale '||COALESCE(v_sales.code,p_sales_id::text),
    v_user_id,now(),v_user_id,now()
  );

  v_line_no:=v_line_no+1;
  INSERT INTO public.account_transactions(
    organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by
  )
  VALUES(
    p_organization_id,v_journal_id,v_sales.receivable_account_id,v_line_no,'Customer receivable',
    v_sales.total_amount,0,v_sales.customer_id,v_user_id,v_user_id
  );

  FOR v_account IN
    SELECT p.sales_account_id AS account_id,sum(n.net_line_total) AS amount
      FROM private.sales_net_lines(p_organization_id,p_sales_id) n
      JOIN public.products p ON p.organization_id=p_organization_id AND p.id=n.product_id
     GROUP BY p.sales_account_id
     ORDER BY p.sales_account_id
  LOOP
    IF v_account.amount>0 THEN
      v_line_no:=v_line_no+1;
      INSERT INTO public.account_transactions(
        organization_id,journal_entry_id,account_id,line_number,description,debit,credit,created_by,updated_by
      )
      VALUES(
        p_organization_id,v_journal_id,v_account.account_id,v_line_no,'Sales revenue',
        0,v_account.amount,v_user_id,v_user_id
      );
    END IF;
  END LOOP;

  FOR v_account IN
    SELECT p.cogs_account_id AS account_id,sum(i.cogs_total) AS amount
      FROM public.sales_items i
      JOIN public.products p ON p.organization_id=i.organization_id AND p.id=i.product_id
     WHERE i.organization_id=p_organization_id AND i.sales_id=p_sales_id
     GROUP BY p.cogs_account_id
     ORDER BY p.cogs_account_id
  LOOP
    IF v_account.amount>0 THEN
      v_line_no:=v_line_no+1;
      INSERT INTO public.account_transactions(
        organization_id,journal_entry_id,account_id,line_number,description,debit,credit,created_by,updated_by
      )
      VALUES(
        p_organization_id,v_journal_id,v_account.account_id,v_line_no,'Cost of goods sold',
        v_account.amount,0,v_user_id,v_user_id
      );
    END IF;
  END LOOP;

  FOR v_account IN
    SELECT p.inventory_account_id AS account_id,sum(i.cogs_total) AS amount
      FROM public.sales_items i
      JOIN public.products p ON p.organization_id=i.organization_id AND p.id=i.product_id
     WHERE i.organization_id=p_organization_id AND i.sales_id=p_sales_id
     GROUP BY p.inventory_account_id
     ORDER BY p.inventory_account_id
  LOOP
    IF v_account.amount>0 THEN
      v_line_no:=v_line_no+1;
      INSERT INTO public.account_transactions(
        organization_id,journal_entry_id,account_id,line_number,description,debit,credit,created_by,updated_by
      )
      VALUES(
        p_organization_id,v_journal_id,v_account.account_id,v_line_no,'Inventory relieved',
        0,v_account.amount,v_user_id,v_user_id
      );
    END IF;
  END LOOP;

  FOR v_product IN
    SELECT i.product_id,sum(i.quantity)::numeric(20,6) AS quantity,
           sum(i.cogs_total)::numeric(20,4) AS total_value
      FROM public.sales_items i
     WHERE i.organization_id=p_organization_id AND i.sales_id=p_sales_id
     GROUP BY i.product_id
     ORDER BY i.product_id
  LOOP
    SELECT b.* INTO v_balance
      FROM public.inventory_balances b
     WHERE b.organization_id=p_organization_id AND b.product_id=v_product.product_id
     FOR UPDATE;
    v_new_qty:=v_balance.quantity-v_product.quantity;
    v_new_value:=CASE WHEN v_new_qty=0 THEN 0 ELSE round(v_balance.inventory_value-v_product.total_value,4) END;
    IF v_new_qty<0 OR v_new_value<0 THEN
      RAISE EXCEPTION 'Inventory balance would become negative for product %',v_product.product_id USING ERRCODE='23514';
    END IF;
    v_new_average:=CASE WHEN v_new_qty=0 THEN 0 ELSE round(v_new_value/v_new_qty,6) END;

    INSERT INTO public.inventory_transactions(
      organization_id,code,product_id,transaction_date,transaction_type,direction,
      quantity,unit_cost,total_value,reference_type,reference_id,unit_cost_before,
      average_cost_after,created_by
    )
    VALUES(
      p_organization_id,private.allocate_document_number(p_organization_id,'inventory_transactions'),
      v_product.product_id,v_sales.invoice_date,'sale','out',v_product.quantity,
      CASE WHEN v_product.quantity=0 THEN 0 ELSE round(v_product.total_value/v_product.quantity,6) END,
      v_product.total_value,'sales',p_sales_id,v_balance.average_cost,v_new_average,v_user_id
    );

    UPDATE public.inventory_balances
       SET quantity=v_new_qty,inventory_value=v_new_value,average_cost=v_new_average,
           updated_by=v_user_id,updated_at=now()
     WHERE organization_id=p_organization_id AND product_id=v_product.product_id;
  END LOOP;

  PERFORM public.post_journal_entry(p_organization_id,v_journal_id);

  UPDATE public.sales
     SET code=COALESCE(code,private.allocate_document_number(p_organization_id,'sales')),
         status='posted',confirmed_at=now(),confirmed_by=v_user_id,posted_by=v_user_id,
         posted_journal_entry_id=v_journal_id,updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_sales_id AND status='draft';
  IF NOT FOUND THEN RAISE EXCEPTION 'Sales posting failed' USING ERRCODE='23514'; END IF;

  RETURN v_journal_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.post_purchase(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.post_purchase(uuid,uuid) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.post_sales(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.post_sales(uuid,uuid) TO authenticated,service_role;

COMMIT;
