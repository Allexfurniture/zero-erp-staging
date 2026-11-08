-- ZERO ERP V1: correct inventory-adjustment JSON validation counters.
BEGIN;
CREATE OR REPLACE FUNCTION public.post_inventory_adjustment(
  p_organization_id uuid,
  p_adjustment_date date,
  p_reason text,
  p_items jsonb,
  p_gain_account_id uuid DEFAULT NULL,
  p_loss_account_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid:=auth.uid();
  v_org_status text;
  v_item record;
  v_balance public.inventory_balances%ROWTYPE;
  v_has_balance boolean;
  v_inventory_account_id uuid;
  v_account_type text;
  v_journal_id uuid:=gen_random_uuid();
  v_line_no integer:=0;
  v_new_qty numeric(20,6);
  v_new_value numeric(20,4);
  v_new_average numeric(20,6);
  v_total_value numeric(20,4);
  v_unit_cost numeric(20,6);
  v_direction text;
  v_quantity numeric(20,6);
  v_unit_cost_input numeric(20,6);
  v_has_in boolean;
  v_has_out boolean;
  v_invalid bigint;
  v_item_count bigint;
  v_distinct_products bigint;
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  IF p_adjustment_date IS NULL OR p_reason IS NULL OR btrim(p_reason)='' OR length(btrim(p_reason))>500 THEN
    RAISE EXCEPTION 'An adjustment date and reason of 1-500 characters are required' USING ERRCODE='22023';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Inventory adjustment items must be a JSON array' USING ERRCODE='22023';
  END IF;
  IF jsonb_array_length(p_items)=0 THEN
    RAISE EXCEPTION 'Inventory adjustment requires a non-empty JSON array' USING ERRCODE='22023';
  END IF;

  SELECT o.status INTO v_org_status
    FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Inventory adjustments require an active organization' USING ERRCODE='23514';
  END IF;

  SELECT count(*),count(DISTINCT x.product_id),
         count(*) FILTER (
           WHERE x.product_id IS NULL OR x.direction IS NULL OR x.direction NOT IN ('in','out')
              OR x.quantity IS NULL OR x.quantity<=0
              OR (x.direction='in' AND (x.unit_cost IS NULL OR x.unit_cost<=0))
              OR (x.direction='out' AND x.unit_cost IS NOT NULL AND x.unit_cost<0)
         )
    INTO v_item_count,v_distinct_products,v_invalid
    FROM jsonb_to_recordset(p_items) AS x(
      product_id uuid,direction text,quantity numeric(20,6),unit_cost numeric(20,6)
    );
  IF v_item_count<>v_distinct_products OR v_invalid>0 THEN
    RAISE EXCEPTION 'Adjustment items require unique products, direction in/out, positive quantity and positive unit cost for increases' USING ERRCODE='23514';
  END IF;

  SELECT bool_or(x.direction='in'),bool_or(x.direction='out')
    INTO v_has_in,v_has_out
    FROM jsonb_to_recordset(p_items) AS x(
      product_id uuid,direction text,quantity numeric(20,6),unit_cost numeric(20,6)
    );

  IF v_has_in THEN
    SELECT a.account_type INTO v_account_type
      FROM public.accounts a
     WHERE a.organization_id=p_organization_id AND a.id=p_gain_account_id
       AND a.status='active' AND a.is_postable;
    IF v_account_type IS DISTINCT FROM 'income' THEN
      RAISE EXCEPTION 'Inventory increase requires an active postable income account for the adjustment gain' USING ERRCODE='23514';
    END IF;
  END IF;
  IF v_has_out THEN
    SELECT a.account_type INTO v_account_type
      FROM public.accounts a
     WHERE a.organization_id=p_organization_id AND a.id=p_loss_account_id
       AND a.status='active' AND a.is_postable;
    IF v_account_type IS DISTINCT FROM 'expense' THEN
      RAISE EXCEPTION 'Inventory decrease requires an active postable expense account for the adjustment loss' USING ERRCODE='23514';
    END IF;
  END IF;

  SELECT count(*) INTO v_invalid
    FROM jsonb_to_recordset(p_items) AS x(
      product_id uuid,direction text,quantity numeric(20,6),unit_cost numeric(20,6)
    )
    LEFT JOIN public.products p
      ON p.organization_id=p_organization_id AND p.id=x.product_id
    LEFT JOIN public.accounts a
      ON a.organization_id=p.organization_id AND a.id=p.inventory_account_id
   WHERE p.id IS NULL OR p.status IS NOT TRUE OR a.id IS NULL
      OR a.account_type<>'asset' OR a.status<>'active' OR NOT a.is_postable;
  IF v_invalid>0 THEN
    RAISE EXCEPTION 'Every adjustment product must map to an active postable inventory asset account' USING ERRCODE='23514';
  END IF;

  PERFORM p.id
    FROM public.products p
    JOIN jsonb_to_recordset(p_items) AS x(
      product_id uuid,direction text,quantity numeric(20,6),unit_cost numeric(20,6)
    ) ON x.product_id=p.id
   WHERE p.organization_id=p_organization_id
   ORDER BY p.id FOR UPDATE OF p;

  PERFORM set_config('zero_erp.allow_workflow','on',true);
  INSERT INTO public.journal_entries(
    id,organization_id,entry_date,entry_type,status,reference_type,reference_id,
    description,created_by,created_at,updated_by,updated_at
  )
  VALUES(
    v_journal_id,p_organization_id,p_adjustment_date,'inventory_adjustment','draft',
    'inventory_adjustment',v_journal_id,btrim(p_reason),v_user_id,now(),v_user_id,now()
  );

  FOR v_item IN
    SELECT x.product_id,x.direction,x.quantity,x.unit_cost,p.inventory_account_id
      FROM jsonb_to_recordset(p_items) AS x(
        product_id uuid,direction text,quantity numeric(20,6),unit_cost numeric(20,6)
      )
      JOIN public.products p ON p.organization_id=p_organization_id AND p.id=x.product_id
     ORDER BY x.product_id
  LOOP
    v_direction:=v_item.direction;
    v_quantity:=v_item.quantity;
    v_unit_cost_input:=v_item.unit_cost;
    v_inventory_account_id:=v_item.inventory_account_id;

    SELECT b.* INTO v_balance
      FROM public.inventory_balances b
     WHERE b.organization_id=p_organization_id AND b.product_id=v_item.product_id
     FOR UPDATE;
    v_has_balance:=FOUND;

    IF v_direction='out' AND (NOT v_has_balance OR v_balance.quantity<v_quantity OR v_balance.quantity<=0) THEN
      RAISE EXCEPTION 'Insufficient inventory for adjustment product %',v_item.product_id USING ERRCODE='23514';
    END IF;

    IF v_direction='in' THEN
      v_unit_cost:=v_unit_cost_input;
      v_total_value:=round(v_quantity*v_unit_cost,4);
      v_new_qty:=COALESCE(v_balance.quantity,0)+v_quantity;
      v_new_value:=round(COALESCE(v_balance.inventory_value,0)+v_total_value,4);
    ELSE
      v_total_value:=CASE WHEN v_quantity=v_balance.quantity
                          THEN v_balance.inventory_value
                          ELSE round(v_quantity*v_balance.average_cost,4) END;
      IF v_total_value<=0 THEN
        RAISE EXCEPTION 'Cannot adjust out inventory with zero carrying value' USING ERRCODE='23514';
      END IF;
      v_unit_cost:=round(v_total_value/v_quantity,6);
      v_new_qty:=v_balance.quantity-v_quantity;
      v_new_value:=CASE WHEN v_new_qty=0 THEN 0 ELSE round(v_balance.inventory_value-v_total_value,4) END;
    END IF;

    IF v_total_value<=0 THEN
      RAISE EXCEPTION 'Inventory adjustment value must be greater than zero' USING ERRCODE='23514';
    END IF;
    v_new_average:=CASE WHEN v_new_qty=0 THEN 0 ELSE round(v_new_value/v_new_qty,6) END;

    IF v_direction='in' THEN
      v_line_no:=v_line_no+1;
      INSERT INTO public.account_transactions(
        organization_id,journal_entry_id,account_id,line_number,description,debit,credit,created_by,updated_by
      )
      VALUES(p_organization_id,v_journal_id,v_inventory_account_id,v_line_no,'Inventory increase',
             v_total_value,0,v_user_id,v_user_id);
      v_line_no:=v_line_no+1;
      INSERT INTO public.account_transactions(
        organization_id,journal_entry_id,account_id,line_number,description,debit,credit,created_by,updated_by
      )
      VALUES(p_organization_id,v_journal_id,p_gain_account_id,v_line_no,'Inventory adjustment gain',
             0,v_total_value,v_user_id,v_user_id);
    ELSE
      v_line_no:=v_line_no+1;
      INSERT INTO public.account_transactions(
        organization_id,journal_entry_id,account_id,line_number,description,debit,credit,created_by,updated_by
      )
      VALUES(p_organization_id,v_journal_id,p_loss_account_id,v_line_no,'Inventory adjustment loss',
             v_total_value,0,v_user_id,v_user_id);
      v_line_no:=v_line_no+1;
      INSERT INTO public.account_transactions(
        organization_id,journal_entry_id,account_id,line_number,description,debit,credit,created_by,updated_by
      )
      VALUES(p_organization_id,v_journal_id,v_inventory_account_id,v_line_no,'Inventory decrease',
             0,v_total_value,v_user_id,v_user_id);
    END IF;

    INSERT INTO public.inventory_transactions(
      organization_id,code,product_id,transaction_date,transaction_type,direction,
      quantity,unit_cost,total_value,reference_type,reference_id,unit_cost_before,
      average_cost_after,created_by
    )
    VALUES(
      p_organization_id,private.allocate_document_number(p_organization_id,'inventory_transactions'),
      v_item.product_id,p_adjustment_date,'adjustment',v_direction,v_quantity,v_unit_cost,
      v_total_value,'journal_entry',v_journal_id,
      CASE WHEN v_has_balance THEN v_balance.average_cost ELSE NULL END,
      v_new_average,v_user_id
    );

    IF v_has_balance THEN
      UPDATE public.inventory_balances
         SET quantity=v_new_qty,inventory_value=v_new_value,average_cost=v_new_average,
             updated_by=v_user_id,updated_at=now()
       WHERE organization_id=p_organization_id AND product_id=v_item.product_id;
    ELSE
      INSERT INTO public.inventory_balances(
        organization_id,product_id,quantity,average_cost,inventory_value,created_by,updated_by,updated_at
      )
      VALUES(p_organization_id,v_item.product_id,v_new_qty,v_new_average,v_new_value,v_user_id,v_user_id,now());
    END IF;
  END LOOP;

  PERFORM public.post_journal_entry(p_organization_id,v_journal_id);
  RETURN v_journal_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.post_inventory_adjustment(uuid,date,text,jsonb,uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.post_inventory_adjustment(uuid,date,text,jsonb,uuid,uuid) TO authenticated,service_role;
COMMIT;