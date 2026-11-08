-- ZERO ERP V1: explicit contact-control account semantics.
BEGIN;

ALTER TABLE public.accounts
  ADD COLUMN IF NOT EXISTS requires_contact boolean NOT NULL DEFAULT false;
ALTER TABLE private.default_account_templates
  ADD COLUMN IF NOT EXISTS requires_contact boolean NOT NULL DEFAULT false;

UPDATE public.accounts SET requires_contact=true
 WHERE code IN ('1130','2110') AND requires_contact=false;
UPDATE private.default_account_templates SET requires_contact=true
 WHERE code IN ('1130','2110') AND requires_contact=false;

ALTER TABLE public.accounts
  ADD CONSTRAINT accounts_requires_contact_control_check
  CHECK (NOT requires_contact OR (is_control_account AND account_type IN ('asset','liability')));
ALTER TABLE private.default_account_templates
  ADD CONSTRAINT default_account_templates_requires_contact_control_check
  CHECK (NOT requires_contact OR (is_control_account AND account_type IN ('asset','liability')));

CREATE OR REPLACE FUNCTION private.seed_organization_configuration(p_organization_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE v_category record; v_category_code text;
BEGIN
  IF p_organization_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=p_organization_id) THEN
    RAISE EXCEPTION 'Organization does not exist' USING ERRCODE='23503';
  END IF;
  IF EXISTS (SELECT 1 FROM public.accounts a WHERE a.organization_id=p_organization_id)
     OR EXISTS (SELECT 1 FROM public.number_sequences n WHERE n.organization_id=p_organization_id) THEN
    RAISE EXCEPTION 'Organization configuration has already been seeded' USING ERRCODE='23505';
  END IF;

  INSERT INTO public.accounts
    (organization_id,code,account_name,account_type,parent_account_id,normal_balance,
     is_control_account,is_postable,requires_contact,status)
  SELECT p_organization_id,t.code,t.account_name,t.account_type,NULL,t.normal_balance,
         t.is_control_account,t.is_postable,t.requires_contact,'active'
    FROM private.default_account_templates t WHERE t.parent_code IS NULL ORDER BY t.code;

  INSERT INTO public.accounts
    (organization_id,code,account_name,account_type,parent_account_id,normal_balance,
     is_control_account,is_postable,requires_contact,status)
  SELECT p_organization_id,t.code,t.account_name,t.account_type,parent.id,t.normal_balance,
         t.is_control_account,t.is_postable,t.requires_contact,'active'
    FROM private.default_account_templates t
    JOIN public.accounts parent ON parent.organization_id=p_organization_id AND parent.code=t.parent_code
   WHERE t.parent_code IS NOT NULL ORDER BY t.code;

  INSERT INTO public.number_sequences
    (organization_id,document_type,prefix,next_number,padding,increment_by)
  VALUES
    (p_organization_id,'account_asset','',1150,4,1),
    (p_organization_id,'account_liability','',2120,4,1),
    (p_organization_id,'account_equity','',3210,4,1),
    (p_organization_id,'account_income','',4210,4,1),
    (p_organization_id,'account_expense','',5210,4,1),
    (p_organization_id,'contacts','CON',1,6,1),
    (p_organization_id,'products','PRD',1,6,1),
    (p_organization_id,'expense_categories','EXP',1,3,1),
    (p_organization_id,'expenses','EXP',1,6,1),
    (p_organization_id,'payments','PAY',1,6,1),
    (p_organization_id,'purchase','PUR',1,6,1),
    (p_organization_id,'sales','INV',1,6,1),
    (p_organization_id,'purchase_returns','PR',1,6,1),
    (p_organization_id,'sales_returns','SR',1,6,1),
    (p_organization_id,'journal_entries','JE',1,6,1),
    (p_organization_id,'inventory_transactions','ITX',1,6,1);

  FOR v_category IN SELECT name FROM private.default_expense_category_templates ORDER BY code LOOP
    v_category_code := private.allocate_document_number(p_organization_id,'expense_categories');
    INSERT INTO public.expense_categories(organization_id,code,name,expense_account_id,status)
    SELECT p_organization_id,v_category_code,v_category.name,a.id,true
      FROM public.accounts a WHERE a.organization_id=p_organization_id AND a.code='5200';
  END LOOP;
END;
$function$;

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
                WHERE c.organization_id=OLD.organization_id AND c.expense_account_id=OLD.id);

  IF v_used AND (
       NEW.code IS DISTINCT FROM OLD.code
       OR NEW.account_type IS DISTINCT FROM OLD.account_type
       OR NEW.normal_balance IS DISTINCT FROM OLD.normal_balance
       OR NEW.is_control_account IS DISTINCT FROM OLD.is_control_account
       OR NEW.is_postable IS DISTINCT FROM OLD.is_postable
       OR NEW.requires_contact IS DISTINCT FROM OLD.requires_contact
     ) THEN
    RAISE EXCEPTION 'Account code and posting definition are immutable after ledger or master-data use'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.enforce_account_transaction_contact()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE v_requires_contact boolean;
BEGIN
  SELECT a.requires_contact INTO v_requires_contact
    FROM public.accounts a
   WHERE a.organization_id=NEW.organization_id AND a.id=NEW.account_id;
  IF v_requires_contact IS TRUE AND (
       NEW.contact_id IS NULL
       OR NOT EXISTS (
         SELECT 1 FROM public.contacts c
          WHERE c.organization_id=NEW.organization_id
            AND c.id=NEW.contact_id AND c.status='active'
       )
     ) THEN
    RAISE EXCEPTION 'This control account requires an active customer or supplier contact'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.enforce_account_transaction_contact() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER account_transactions_require_contact
BEFORE INSERT OR UPDATE OF account_id,contact_id,organization_id ON public.account_transactions
FOR EACH ROW EXECUTE FUNCTION private.enforce_account_transaction_contact();

CREATE OR REPLACE FUNCTION private.enforce_document_control_account()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
DECLARE
  v_account_id uuid;
  v_expected_type text;
  v_account_type text;
  v_requires_contact boolean;
  v_contact_id uuid;
BEGIN
  IF TG_TABLE_NAME IN ('sales','sales_returns') THEN
    v_account_id:=NEW.receivable_account_id;
    v_expected_type:='asset';
  ELSIF TG_TABLE_NAME IN ('purchase','purchase_returns') THEN
    v_account_id:=NEW.payable_account_id;
    v_expected_type:='liability';
  ELSIF TG_TABLE_NAME='payments' THEN
    v_account_id:=NEW.account_id;
    v_expected_type:=CASE WHEN NEW.payment_type='receipt' THEN 'asset' ELSE 'liability' END;
  ELSIF TG_TABLE_NAME='expenses' THEN
    IF NEW.payable_account_id IS NULL THEN RETURN NEW; END IF;
    v_account_id:=NEW.payable_account_id;
    v_expected_type:='liability';
  ELSE
    RAISE EXCEPTION 'Unsupported document table for control account validation';
  END IF;

  v_contact_id:=NEW.contact_id;
  IF TG_TABLE_NAME IN ('sales','sales_returns') THEN v_contact_id:=NEW.customer_id; END IF;
  IF TG_TABLE_NAME IN ('purchase','purchase_returns') THEN v_contact_id:=NEW.supplier_id; END IF;

  SELECT a.account_type,a.requires_contact INTO v_account_type,v_requires_contact
    FROM public.accounts a
   WHERE a.organization_id=NEW.organization_id AND a.id=v_account_id
     AND a.status='active' AND a.is_postable;
  IF v_account_type IS DISTINCT FROM v_expected_type OR v_requires_contact IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Document must use an active postable % control account configured to require a contact',v_expected_type
      USING ERRCODE='23514';
  END IF;
  IF v_contact_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.contacts c
     WHERE c.organization_id=NEW.organization_id AND c.id=v_contact_id AND c.status='active'
  ) THEN
    RAISE EXCEPTION 'Receivable/payable document requires an active matching contact'
      USING ERRCODE='23514';
  END IF;

  IF TG_TABLE_NAME='payments' THEN
    IF NEW.settlement_account_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.accounts a
       WHERE a.organization_id=NEW.organization_id AND a.id=NEW.settlement_account_id
         AND a.account_type='asset' AND a.status='active' AND a.is_postable
    ) THEN
      RAISE EXCEPTION 'Payment settlement account must be an active postable asset account'
        USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.enforce_document_control_account() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER sales_receivable_control_account
BEFORE INSERT OR UPDATE OF receivable_account_id,customer_id,organization_id ON public.sales
FOR EACH ROW EXECUTE FUNCTION private.enforce_document_control_account();
CREATE TRIGGER purchase_payable_control_account
BEFORE INSERT OR UPDATE OF payable_account_id,supplier_id,organization_id ON public.purchase
FOR EACH ROW EXECUTE FUNCTION private.enforce_document_control_account();
CREATE TRIGGER sales_return_receivable_control_account
BEFORE INSERT OR UPDATE OF receivable_account_id,customer_id,organization_id ON public.sales_returns
FOR EACH ROW EXECUTE FUNCTION private.enforce_document_control_account();
CREATE TRIGGER purchase_return_payable_control_account
BEFORE INSERT OR UPDATE OF payable_account_id,supplier_id,organization_id ON public.purchase_returns
FOR EACH ROW EXECUTE FUNCTION private.enforce_document_control_account();
CREATE TRIGGER payments_control_account
BEFORE INSERT OR UPDATE OF account_id,contact_id,payment_type,settlement_account_id,organization_id ON public.payments
FOR EACH ROW EXECUTE FUNCTION private.enforce_document_control_account();
CREATE TRIGGER expenses_payable_control_account
BEFORE INSERT OR UPDATE OF payable_account_id,contact_id,organization_id ON public.expenses
FOR EACH ROW EXECUTE FUNCTION private.enforce_document_control_account();

CREATE OR REPLACE FUNCTION private.materialize_opening_balance_items()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  IF NEW.entry_type='opening_balance' AND OLD.status='draft' AND NEW.status='posted' THEN
    IF EXISTS (
      SELECT 1
        FROM public.account_transactions t
        JOIN public.accounts a ON a.organization_id=t.organization_id AND a.id=t.account_id
        LEFT JOIN public.contacts c ON c.organization_id=t.organization_id AND c.id=t.contact_id
       WHERE t.organization_id=NEW.organization_id AND t.journal_entry_id=NEW.id
         AND a.requires_contact
         AND (
           (a.account_type='asset' AND (t.debit<=0 OR t.credit<>0 OR c.status IS DISTINCT FROM 'active'))
           OR
           (a.account_type='liability' AND (t.credit<=0 OR t.debit<>0 OR c.status IS DISTINCT FROM 'active'))
         )
    ) THEN
      RAISE EXCEPTION 'Opening receivables must be debit balances and opening payables must be credit balances for active contacts'
        USING ERRCODE='23514';
    END IF;

    INSERT INTO public.opening_balance_items(
      organization_id,opening_journal_entry_id,opening_journal_line_id,
      account_id,contact_id,balance_type,description,opening_date,original_amount,created_by
    )
    SELECT t.organization_id,NEW.id,t.id,t.account_id,t.contact_id,'receivable',
           t.description,NEW.entry_date,t.debit,t.created_by
      FROM public.account_transactions t
      JOIN public.accounts a ON a.organization_id=t.organization_id AND a.id=t.account_id
     WHERE t.organization_id=NEW.organization_id AND t.journal_entry_id=NEW.id
       AND a.requires_contact AND a.account_type='asset' AND t.debit>0 AND t.credit=0;

    INSERT INTO public.opening_balance_items(
      organization_id,opening_journal_entry_id,opening_journal_line_id,
      account_id,contact_id,balance_type,description,opening_date,original_amount,created_by
    )
    SELECT t.organization_id,NEW.id,t.id,t.account_id,t.contact_id,'payable',
           t.description,NEW.entry_date,t.credit,t.created_by
      FROM public.account_transactions t
      JOIN public.accounts a ON a.organization_id=t.organization_id AND a.id=t.account_id
     WHERE t.organization_id=NEW.organization_id AND t.journal_entry_id=NEW.id
       AND a.requires_contact AND a.account_type='liability' AND t.credit>0 AND t.debit=0;
  END IF;
  RETURN NEW;
END;
$function$;

COMMIT;