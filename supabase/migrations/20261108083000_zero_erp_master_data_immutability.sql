-- ZERO ERP V1: freeze accounting and product master-data mappings after ledger use.
BEGIN;

CREATE OR REPLACE FUNCTION private.enforce_product_identity_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF (
       NEW.code IS DISTINCT FROM OLD.code
       OR NEW.unit_id IS DISTINCT FROM OLD.unit_id
       OR NEW.inventory_account_id IS DISTINCT FROM OLD.inventory_account_id
       OR NEW.sales_account_id IS DISTINCT FROM OLD.sales_account_id
       OR NEW.cogs_account_id IS DISTINCT FROM OLD.cogs_account_id
     )
     AND EXISTS (
       SELECT 1 FROM public.inventory_transactions t
        WHERE t.organization_id=OLD.organization_id AND t.product_id=OLD.id
     ) THEN
    RAISE EXCEPTION 'Product code, unit and account mappings are immutable after inventory ledger activity'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.enforce_used_account_definition_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  v_used boolean;
BEGIN
  v_used :=
    EXISTS (
      SELECT 1 FROM public.account_transactions t
       WHERE t.organization_id=OLD.organization_id AND t.account_id=OLD.id
    )
    OR EXISTS (
      SELECT 1 FROM public.products p
       WHERE p.organization_id=OLD.organization_id
         AND OLD.id IN (p.inventory_account_id,p.sales_account_id,p.cogs_account_id)
    )
    OR EXISTS (
      SELECT 1 FROM public.expense_categories c
       WHERE c.organization_id=OLD.organization_id AND c.expense_account_id=OLD.id
    );

  IF v_used AND (
       NEW.code IS DISTINCT FROM OLD.code
       OR NEW.account_type IS DISTINCT FROM OLD.account_type
       OR NEW.normal_balance IS DISTINCT FROM OLD.normal_balance
       OR NEW.is_control_account IS DISTINCT FROM OLD.is_control_account
       OR NEW.is_postable IS DISTINCT FROM OLD.is_postable
     ) THEN
    RAISE EXCEPTION 'Account code and posting definition are immutable after ledger or master-data use'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS products_identity_immutable ON public.products;
CREATE TRIGGER products_identity_immutable
BEFORE UPDATE OF code,unit_id,inventory_account_id,sales_account_id,cogs_account_id
ON public.products
FOR EACH ROW EXECUTE FUNCTION private.enforce_product_identity_immutable();

DROP TRIGGER IF EXISTS accounts_used_definition_immutable ON public.accounts;
CREATE TRIGGER accounts_used_definition_immutable
BEFORE UPDATE OF code,account_type,normal_balance,is_control_account,is_postable
ON public.accounts
FOR EACH ROW EXECUTE FUNCTION private.enforce_used_account_definition_immutable();

REVOKE ALL ON FUNCTION private.enforce_product_identity_immutable() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.enforce_used_account_definition_immutable() FROM PUBLIC,anon,authenticated;

COMMIT;
