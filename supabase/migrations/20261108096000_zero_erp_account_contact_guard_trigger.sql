DROP TRIGGER IF EXISTS accounts_used_definition_immutable ON public.accounts;
CREATE TRIGGER accounts_used_definition_immutable
BEFORE UPDATE OF code,account_type,normal_balance,is_control_account,is_postable,requires_contact
ON public.accounts
FOR EACH ROW EXECUTE FUNCTION private.enforce_used_account_definition_immutable();