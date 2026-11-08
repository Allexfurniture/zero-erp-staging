-- ZERO ERP V1: enforce source-document integrity for purchase and sales returns.
BEGIN;

CREATE OR REPLACE FUNCTION private.validate_purchase_return_header()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  v_supplier_id uuid;
  v_source_status text;
BEGIN
  SELECT p.supplier_id,p.status
    INTO v_supplier_id,v_source_status
    FROM public.purchase p
   WHERE p.organization_id=NEW.organization_id AND p.id=NEW.purchase_id;
  IF NOT FOUND OR v_source_status IS DISTINCT FROM 'posted' THEN
    RAISE EXCEPTION 'A purchase return must reference a posted purchase in the same organization'
      USING ERRCODE='23514';
  END IF;
  IF NEW.supplier_id IS DISTINCT FROM v_supplier_id THEN
    RAISE EXCEPTION 'Purchase return supplier must match the source purchase supplier'
      USING ERRCODE='23514';
  END IF;
  IF TG_OP='UPDATE' AND NEW.purchase_id IS DISTINCT FROM OLD.purchase_id
     AND EXISTS (
       SELECT 1 FROM public.purchase_return_items i
        WHERE i.organization_id=OLD.organization_id AND i.purchase_return_id=OLD.id
     ) THEN
    RAISE EXCEPTION 'Source purchase cannot change after return lines have been added'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.validate_sales_return_header()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  v_customer_id uuid;
  v_source_status text;
BEGIN
  SELECT s.customer_id,s.status
    INTO v_customer_id,v_source_status
    FROM public.sales s
   WHERE s.organization_id=NEW.organization_id AND s.id=NEW.sales_id;
  IF NOT FOUND OR v_source_status IS DISTINCT FROM 'posted' THEN
    RAISE EXCEPTION 'A sales return must reference a posted sale in the same organization'
      USING ERRCODE='23514';
  END IF;
  IF NEW.customer_id IS DISTINCT FROM v_customer_id THEN
    RAISE EXCEPTION 'Sales return customer must match the source sale customer'
      USING ERRCODE='23514';
  END IF;
  IF TG_OP='UPDATE' AND NEW.sales_id IS DISTINCT FROM OLD.sales_id
     AND EXISTS (
       SELECT 1 FROM public.sales_return_items i
        WHERE i.organization_id=OLD.organization_id AND i.sales_return_id=OLD.id
     ) THEN
    RAISE EXCEPTION 'Source sale cannot change after return lines have been added'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.validate_purchase_return_item_source()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  v_source_product uuid;
  v_source_unit_cost numeric(20,6);
BEGIN
  SELECT i.product_id,i.unit_cost
    INTO v_source_product,v_source_unit_cost
    FROM public.purchase_return_items ri
    JOIN public.purchase_returns r
      ON r.organization_id=ri.organization_id AND r.id=ri.purchase_return_id
    JOIN public.purchase p
      ON p.organization_id=r.organization_id AND p.id=r.purchase_id AND p.status='posted'
    JOIN public.purchase_items i
      ON i.organization_id=p.organization_id AND i.purchase_id=p.id AND i.id=NEW.purchase_item_id
   WHERE ri.id=NEW.id;
  IF TG_OP='INSERT' THEN
    SELECT i.product_id,i.unit_cost
      INTO v_source_product,v_source_unit_cost
      FROM public.purchase_returns r
      JOIN public.purchase p
        ON p.organization_id=r.organization_id AND p.id=r.purchase_id AND p.status='posted'
      JOIN public.purchase_items i
        ON i.organization_id=p.organization_id AND i.purchase_id=p.id AND i.id=NEW.purchase_item_id
     WHERE r.organization_id=NEW.organization_id AND r.id=NEW.purchase_return_id;
  ELSE
    SELECT i.product_id,i.unit_cost
      INTO v_source_product,v_source_unit_cost
      FROM public.purchase_returns r
      JOIN public.purchase p
        ON p.organization_id=r.organization_id AND p.id=r.purchase_id AND p.status='posted'
      JOIN public.purchase_items i
        ON i.organization_id=p.organization_id AND i.purchase_id=p.id AND i.id=NEW.purchase_item_id
     WHERE r.organization_id=NEW.organization_id AND r.id=NEW.purchase_return_id;
  END IF;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Purchase return item must reference a line from the return header source purchase'
      USING ERRCODE='23514';
  END IF;
  IF NEW.product_id IS DISTINCT FROM v_source_product
     OR NEW.unit_cost IS DISTINCT FROM v_source_unit_cost
     OR NEW.line_total<>round(NEW.quantity*NEW.unit_cost,4) THEN
    RAISE EXCEPTION 'Purchase return product, cost and line total must match the source purchase line'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.validate_sales_return_item_source()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  v_source_product uuid;
  v_source_unit_price numeric(20,6);
BEGIN
  SELECT i.product_id,i.unit_price
    INTO v_source_product,v_source_unit_price
    FROM public.sales_returns r
    JOIN public.sales s
      ON s.organization_id=r.organization_id AND s.id=r.sales_id AND s.status='posted'
    JOIN public.sales_items i
      ON i.organization_id=s.organization_id AND i.sales_id=s.id AND i.id=NEW.sales_item_id
   WHERE r.organization_id=NEW.organization_id AND r.id=NEW.sales_return_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sales return item must reference a line from the return header source sale'
      USING ERRCODE='23514';
  END IF;
  IF NEW.product_id IS DISTINCT FROM v_source_product
     OR NEW.unit_price IS DISTINCT FROM v_source_unit_price
     OR NEW.line_total<>round(NEW.quantity*NEW.unit_price,4) THEN
    RAISE EXCEPTION 'Sales return product, price and line total must match the source sales line'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS purchase_returns_source_guard ON public.purchase_returns;
CREATE TRIGGER purchase_returns_source_guard
BEFORE INSERT OR UPDATE OF organization_id,purchase_id,supplier_id ON public.purchase_returns
FOR EACH ROW EXECUTE FUNCTION private.validate_purchase_return_header();

DROP TRIGGER IF EXISTS sales_returns_source_guard ON public.sales_returns;
CREATE TRIGGER sales_returns_source_guard
BEFORE INSERT OR UPDATE OF organization_id,sales_id,customer_id ON public.sales_returns
FOR EACH ROW EXECUTE FUNCTION private.validate_sales_return_header();

DROP TRIGGER IF EXISTS purchase_return_items_source_guard ON public.purchase_return_items;
CREATE TRIGGER purchase_return_items_source_guard
BEFORE INSERT OR UPDATE OF organization_id,purchase_return_id,purchase_item_id,product_id,quantity,unit_cost,line_total
ON public.purchase_return_items
FOR EACH ROW EXECUTE FUNCTION private.validate_purchase_return_item_source();

DROP TRIGGER IF EXISTS sales_return_items_source_guard ON public.sales_return_items;
CREATE TRIGGER sales_return_items_source_guard
BEFORE INSERT OR UPDATE OF organization_id,sales_return_id,sales_item_id,product_id,quantity,unit_price,line_total
ON public.sales_return_items
FOR EACH ROW EXECUTE FUNCTION private.validate_sales_return_item_source();

REVOKE ALL ON FUNCTION private.validate_purchase_return_header() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.validate_sales_return_header() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.validate_purchase_return_item_source() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.validate_sales_return_item_source() FROM PUBLIC,anon,authenticated;

COMMIT;
