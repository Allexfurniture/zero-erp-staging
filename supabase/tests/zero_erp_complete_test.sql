-- ZERO ERP schema/security regression gate.
-- This suite is intentionally read-only: it validates the deployed schema,
-- tenant security boundaries and critical accounting workflow guards.
-- End-to-end posting tests require isolated Auth fixtures and are run separately.

DO $$
DECLARE
  v_count integer;
BEGIN
  -- Every exposed public table must enforce row-level security.
  SELECT count(*) INTO v_count
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r' AND c.relrowsecurity;
  IF v_count <> (
    SELECT count(*) FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind='r'
  ) THEN
    RAISE EXCEPTION 'RLS regression: a public table has RLS disabled';
  END IF;

  -- Anonymous clients must not have direct table privileges.
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind='r'
      AND (has_table_privilege('anon',c.oid,'SELECT')
        OR has_table_privilege('anon',c.oid,'INSERT')
        OR has_table_privilege('anon',c.oid,'UPDATE')
        OR has_table_privilege('anon',c.oid,'DELETE')
        OR has_table_privilege('anon',c.oid,'TRUNCATE'))
  ) THEN
    RAISE EXCEPTION 'Security regression: anon has public table privileges';
  END IF;

  -- Authenticated users must not be able to bypass RLS or attach arbitrary triggers.
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind='r'
      AND (has_table_privilege('authenticated',c.oid,'TRUNCATE')
        OR has_table_privilege('authenticated',c.oid,'TRIGGER')
        OR has_table_privilege('authenticated',c.oid,'REFERENCES'))
  ) THEN
    RAISE EXCEPTION 'Security regression: authenticated retains unsafe table privileges';
  END IF;

  -- All public tables must have at least one explicit RLS policy.
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    LEFT JOIN pg_policies p ON p.schemaname=n.nspname AND p.tablename=c.relname
    WHERE n.nspname='public' AND c.relkind='r'
    GROUP BY c.relname
    HAVING count(p.policyname)=0
  ) THEN
    RAISE EXCEPTION 'RLS regression: a public table has no policy';
  END IF;

  -- Inventory ledger and opening-balance subledger remain read-only to app clients.
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public'
      AND tablename IN ('inventory_transactions','inventory_balances','opening_balance_items')
      AND cmd <> 'SELECT'
  ) THEN
    RAISE EXCEPTION 'Accounting security regression: protected ledger has a write policy';
  END IF;

  -- Critical workflow entry points and private implementations must exist.
  IF to_regprocedure('public.create_organization(text,text,text,text,text,text)') IS NULL
     OR to_regprocedure('private.create_organization(text,text,text,text,text,text)') IS NULL
     OR to_regprocedure('public.complete_organization_setup(uuid,jsonb,boolean)') IS NULL
     OR to_regprocedure('private.complete_organization_setup(uuid,jsonb,boolean)') IS NULL
     OR to_regprocedure('public.post_journal_entry(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Workflow regression: a required organization/accounting RPC is missing';
  END IF;

  IF NOT (
    SELECT p.prosecdef
    FROM pg_proc p
    WHERE p.oid=to_regprocedure('private.complete_organization_setup(uuid,jsonb,boolean)')
  ) THEN
    RAISE EXCEPTION 'Security regression: setup implementation must remain SECURITY DEFINER';
  END IF;

  -- One opening journal per organization and automatic AR/AP subledger materialization.
  IF to_regclass('public.journal_entries_one_opening_uidx') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_trigger
       WHERE tgname='journal_entries_materialize_opening_balances'
         AND NOT tgisinternal
     ) THEN
    RAISE EXCEPTION 'Accounting regression: opening journal uniqueness/materialization is missing';
  END IF;

  -- Preserve core accounting and inventory invariants.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='account_transactions_one_sided_amount')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='account_transactions_positive_line_amount')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='opening_balance_items_original_amount_check')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='inventory_balances_nonnegative_quantity')
     OR NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='inventory_transactions_positive_quantity') THEN
    RAISE EXCEPTION 'Accounting regression: a required amount/quantity constraint is missing';
  END IF;
END;
$$;
