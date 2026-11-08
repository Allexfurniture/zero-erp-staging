-- Keep account posting semantics immutable once any source document references the account.
CREATE OR REPLACE FUNCTION private.enforce_used_account_definition_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE v_used boolean;
BEGIN
  v_used :=
    EXISTS (SELECT 1 FROM public.account_transactions t
             WHERE t.organization_id=OLD.organization_id AND t.account_id=OLD.id)
    OR EXISTS (SELECT 1 FROM public.products p
                WHERE p.organization_id=OLD.organization_id
                  AND OLD.id IN (p.inventory_account_id,p.sales_account_id,p.cogs_account_id))
    OR EXISTS (SELECT 1 FROM public.expense_categories c
                WHERE c.organization_id=OLD.organization_id AND c.expense_account_id=OLD.id)
    OR EXISTS (SELECT 1 FROM public.sales s
                WHERE s.organization_id=OLD.organization_id AND s.receivable_account_id=OLD.id)
    OR EXISTS (SELECT 1 FROM public.purchase p
                WHERE p.organization_id=OLD.organization_id AND p.payable_account_id=OLD.id)
    OR EXISTS (SELECT 1 FROM public.sales_returns r
                WHERE r.organization_id=OLD.organization_id AND r.receivable_account_id=OLD.id)
    OR EXISTS (SELECT 1 FROM public.purchase_returns r
                WHERE r.organization_id=OLD.organization_id
                  AND OLD.id IN (r.payable_account_id,r.purchase_return_variance_account_id))
    OR EXISTS (SELECT 1 FROM public.payments p
                WHERE p.organization_id=OLD.organization_id
                  AND OLD.id IN (p.account_id,p.settlement_account_id))
    OR EXISTS (SELECT 1 FROM public.expenses e
                WHERE e.organization_id=OLD.organization_id AND e.payable_account_id=OLD.id)
    OR EXISTS (SELECT 1 FROM public.opening_balance_items ob
                WHERE ob.organization_id=OLD.organization_id AND ob.account_id=OLD.id);

  IF v_used AND (
       NEW.code IS DISTINCT FROM OLD.code
       OR NEW.account_type IS DISTINCT FROM OLD.account_type
       OR NEW.normal_balance IS DISTINCT FROM OLD.normal_balance
       OR NEW.is_control_account IS DISTINCT FROM OLD.is_control_account
       OR NEW.is_postable IS DISTINCT FROM OLD.is_postable
       OR NEW.requires_contact IS DISTINCT FROM OLD.requires_contact
     ) THEN
    RAISE EXCEPTION 'Account code and posting definition are immutable after ledger or source-document use'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$function$;