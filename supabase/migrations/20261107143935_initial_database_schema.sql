-- ZERO ERP V1 initial schema bootstrap.
-- Non-destructive: never drop shared Supabase schemas or existing data.
-- Apply only to the dedicated ZERO ERP project after verifying its app schema is empty.
BEGIN;

-- ===== Replayed: 20261107135206_zero_erp_v1_schema.sql =====
-- ZERO ERP V1 schema migration
-- Generated from docs/database/initial-database-schema-v1.sql.
-- Columns-only baseline: constraints, indexes, RLS policies, triggers, RPCs,
-- and seed/provisioning logic are intentionally deferred to later migrations.



-- ZERO ERP Initial Database Schema V1
-- Column definitions only: 23 retained legacy tables. No organization_setup table.
-- RBAC is excluded: no roles, permissions, or role-permission tables are included.
-- Access model: no RBAC tables. All active organization members may perform business operations.
-- Only the organization creator (organizations.created_by) may manage organization-level system data and memberships.
-- created_by records the authenticated user who created each applicable row; it is audit metadata, not an ownership permission.
-- No primary keys, foreign keys, indexes, checks, policies, triggers, or functions are defined here.
-- Legacy table columns and data types are copied from the existing live database catalog.
-- Opening setup uses existing master and transaction tables; no separate setup or opening table is used.

/*
 * ORGANIZATION LIFECYCLE AND PRE-ACTIVATION WORKFLOW (V1)
 * - New organizations start with status = 'configuring'.
 * - Supported lifecycle values: configuring, active, inactive.
 * - While configuring, users may create and maintain setup master data in
 *   contacts, units_of_measure, products, and accounts.
 * - While configuring, only the opening journal entry may be created in the
 *   accounting ledger. It remains Draft while the user edits opening balances.
 * - Receivable and payable opening amounts are lines in that same opening
 *   journal entry and must carry the relevant contacts.contact_id.
 * - Inventory opening quantities and unit costs are held only in the Setup
 *   Wizard's temporary client-side state before completion. They must not be
 *   written to inventory_transactions or inventory_balances before Complete.
 * - The Complete operation must validate the opening journal is balanced,
 *   validate contact/account mappings, and verify that the Inventory Asset
 *   amount in the opening journal equals the sum of product opening quantities
 *   multiplied by their unit costs. A zero inventory opening must be explicitly
 *   confirmed when the organization has no opening stock.
 * - On successful Complete, one atomic database transaction must post the
 *   opening journal, create all opening inventory_transactions, update
 *   inventory_balances, and set organizations.status = 'active'. If any step
 *   fails, the entire operation must roll back and the organization stays
 *   configuring.
 * - Before activation, normal operational documents (purchase, sales, returns,
 *   expenses, payments, and non-opening journal entries) must not be posted.
 * - Once active, opening entries cannot be created or changed. Corrections
 *   must use normal adjustment or reversal workflows. Inactive organizations
 *   cannot perform business write operations.
 * - Enforce these rules in database/RPC logic, not only in the UI. Lock the
 *   organization row during Complete to prevent concurrent or duplicate posting.
 * - No separate organization_setup table, setup-progress columns, or opening
 *   completion Boolean columns are used in this V1 design.
 */

CREATE TABLE public.organizations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  phone text,
  email text,
  address text,
  tin text,
  bin text,
  status text NOT NULL DEFAULT 'configuring'::text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- organizations.email must be globally unique across all organizations.
-- The unique constraint/index will be added in the constraints phase.

CREATE TABLE public.organization_users (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  user_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'active'::text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.accounts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  code text NOT NULL,
  account_name text NOT NULL,
  account_type text NOT NULL,
  parent_account_id uuid,
  normal_balance text NOT NULL,
  is_control_account boolean NOT NULL DEFAULT false,
  is_postable boolean NOT NULL DEFAULT true,
  status text NOT NULL DEFAULT 'active'::text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

/*
 * APPROVED ACCOUNTS BUSINESS RULES (V1)
 * - Account codes are generated automatically by the system, per organization.
 * - Account code ranges: Asset 1000-1999; Liability 2000-2999;
 *   Equity 3000-3999; Income 4000-4999; Expense 5000-5999.
 * - Account codes must be unique within an organization and must not be reused
 *   after deletion. Enforce uniqueness and generation atomically in the
 *   constraints/business-logic phase.
 * - Account names must be unique within an organization. Enforce this in the
 *   constraints phase (case-insensitive uniqueness is recommended).
 * - Approved default Chart of Accounts:
 *   1100 Current Assets (Asset, Debit, parent/non-postable)
 *     1110 Cash in Hand (Asset, Debit)
 *     1120 Bank Account (Asset, Debit)
 *     1130 Accounts Receivable (Asset, Debit)
 *   2100 Current Liabilities (Liability, Credit, parent/non-postable)
 *     2110 Accounts Payable (Liability, Credit)
 *   3100 Owner's Capital (Equity, Credit)
 *   3200 Opening Balance Equity (Equity, Credit)
 *   4100 Sales Revenue (Income, Credit)
 *   4200 Other Income (Income, Credit)
 *   5100 Cost of Goods Sold (Expense, Debit)
 *   5200 General Expenses (Expense, Debit)
 * - These are approved default records; seed/initialization logic is separate
 *   from this columns-only schema file.
 */

CREATE TABLE public.units_of_measure (
  id uuid NOT NULL,
  organization_id uuid NOT NULL,
  name text NOT NULL,
  status text NOT NULL,
  created_by uuid,
  created_at timestamp with time zone NOT NULL,
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL
);

CREATE TABLE public.contacts (
  id uuid NOT NULL,
  organization_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  phone text,
  email text,
  address text,
  status text NOT NULL,
  created_by uuid,
  created_at timestamp with time zone NOT NULL,
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL
);

CREATE TABLE public.products (
  id uuid NOT NULL,
  organization_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  unit_id uuid NOT NULL,
  inventory_account_id uuid,
  sales_account_id uuid,
  cogs_account_id uuid,
  status boolean NOT NULL,
  created_by uuid,
  created_at timestamp with time zone NOT NULL,
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL
);

CREATE TABLE public.expense_categories (
  id uuid NOT NULL,
  organization_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  expense_account_id uuid,
  status boolean NOT NULL,
  created_by uuid,
  created_at timestamp with time zone NOT NULL,
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL
);

/*
 * APPROVED DEFAULT EXPENSE CATEGORIES
 * Seed these 12 categories for each new organization. Each is linked to
 * account code 5200 (General Expenses):
 * EXP001 Salary & Wages
 * EXP002 Office Rent
 * EXP003 Electricity Bill
 * EXP004 Water Bill
 * EXP005 Internet & Telephone
 * EXP006 Transportation
 * EXP007 Office Supplies
 * EXP008 Marketing & Advertising
 * EXP009 Repair & Maintenance
 * EXP010 Entertainment
 * EXP011 Bank Charges
 * EXP012 Miscellaneous Expenses
 *
 * These are organization-scoped seed records, not column DEFAULT values.
 * Seed/initialization logic is separate from this columns-only schema file.
 */

/*
 * NUMBER SEQUENCE POLICY (V1)
 * All generated master codes and document numbers are allocated through
 * public.number_sequences, scoped by organization_id and document_type.
 * The target tables store the generated value in a consistently named
 * "code" column. Sequence allocation must be atomic and must never reuse
 * a previously issued number. The application/database logic that allocates
 * numbers is implemented separately from this columns-only schema.
 * Sequence-backed tables: accounts, contacts, products, expense_categories, expenses,
 * payments, purchase, sales, purchase_returns, sales_returns,
 * journal_entries, and inventory_transactions.
 */

/*
 * APPROVED NUMBER SEQUENCE CONFIGURATION (V1)
 * Automatically provision these 12 system-managed sequences for every
 * organization. Users cannot add, edit, or delete these configurations.
 * The system alone advances next_number atomically; prefix and padding
 * are fixed by the system configuration.
 *
 * document_type              prefix  next_number  padding
 * accounts                   ACC     1            6
 * contacts                   CON     1            6
 * products                   PRD     1            6
 * expense_categories         CAT     1            6
 * expenses                   EXP     1            6
 * payments                   PAY     1            6
 * purchase                   PUR     1            6
 * sales                      INV     1            6
 * purchase_returns           PR      1            6
 * sales_returns              SR      1            6
 * journal_entries            JE      1            6
 * inventory_transactions     ITX     1            6
 *
 * Provisioning and atomic number-allocation logic are implemented separately
 * from this columns-only schema file.
 */

CREATE TABLE public.number_sequences (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  document_type text NOT NULL,
  prefix text NOT NULL DEFAULT ''::text,
  next_number bigint NOT NULL DEFAULT 1,
  padding smallint NOT NULL DEFAULT 6,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.journal_entries (
  id uuid NOT NULL,
  organization_id uuid NOT NULL,
  code text,
  entry_date date NOT NULL,
  entry_type text NOT NULL,
  status text NOT NULL,
  confirmed_at timestamp with time zone,
  confirmed_by uuid,
  posted_by uuid,
  voided_at timestamp with time zone,
  voided_by uuid,
  void_reason text,
  reference_type text,
  reference_id uuid,
  description text,
  posted_at timestamp with time zone,
  reversal_of_id uuid,
  reversal_journal_entry_id uuid,
  reversed_at timestamp with time zone,
  reversed_by uuid,
  reversal_reason text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL,
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL
);

/*
 * APPROVED JOURNAL ENTRY WORKFLOW
 * Draft -> Confirmed -> Posted.
 * - The organization's single initial accounting entry uses entry_type =
 *   'opening_balance' and is editable only while its status is Draft and the
 *   organization is not active.
 * - That one opening journal includes cash, bank, contact-wise receivables,
 *   contact-wise payables, other opening account balances, and the Inventory
 *   Asset control-account amount. Receivable/payable lines use contact_id.
 * - The opening journal is the durable Draft record. Inventory opening input
 *   is not persisted to the inventory ledger until the Complete operation.
 * - On Complete, this journal is confirmed and posted as part of the same
 *   atomic operation that creates the opening inventory ledger rows.
 * - Only one opening_balance journal entry may exist per organization; enforce
 *   this with a unique partial index/constraint in the constraints phase.
 * confirmed_at and confirmed_by record the confirmation audit.
 * posted_at and posted_by record the ledger posting audit.
 * Posted entries are corrected through reversal entries, not direct edits.
 */

CREATE TABLE public.account_transactions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  journal_entry_id uuid NOT NULL,
  account_id uuid NOT NULL,
  line_number integer NOT NULL,
  description text,
  debit numeric(20,4) NOT NULL DEFAULT 0,
  credit numeric(20,4) NOT NULL DEFAULT 0,
  contact_id uuid,
  created_by uuid,
  updated_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone
);

/*
 * INVENTORY OPENING RULES (V1)
 * - Inventory opening uses transaction_type = 'opening' and direction = 'in'.
 * - Inventory opening input is temporary wizard data until the user selects
 *   Complete; do not insert draft rows into this immutable inventory ledger.
 * - During Complete, create one inventory_transactions row per product and
 *   reference all rows to the organization's opening journal entry using
 *   reference_type = 'journal_entry' and reference_id = journal_entries.id.
 * - Create these rows and update inventory_balances atomically with posting
 *   the opening journal and activating the organization.
 * - Do not add a status column to inventory_transactions. It stores posted,
 *   immutable inventory movements only; corrections use adjustment/reversal.
 */
CREATE TABLE public.inventory_transactions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  code text NOT NULL,
  product_id uuid NOT NULL,
  transaction_date date NOT NULL,
  transaction_type text NOT NULL,
  direction text NOT NULL,
  quantity numeric(20,6) NOT NULL,
  unit_cost numeric(20,6) NOT NULL DEFAULT 0,
  total_value numeric(20,4) NOT NULL DEFAULT 0,
  reference_type text,
  reference_id uuid,
  unit_cost_before numeric(20,6),
  average_cost_after numeric(20,6),
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.inventory_balances (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  product_id uuid NOT NULL,
  quantity numeric(20,6) NOT NULL DEFAULT 0,
  average_cost numeric(20,6) NOT NULL DEFAULT 0,
  inventory_value numeric(20,4) NOT NULL DEFAULT 0,
  created_by uuid,
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.purchase (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  code text,
  supplier_id uuid NOT NULL,
  invoice_date date NOT NULL,
  status text NOT NULL DEFAULT 'draft'::text,
  confirmed_at timestamp with time zone,
  confirmed_by uuid,
  posted_by uuid,
  voided_at timestamp with time zone,
  voided_by uuid,
  void_reason text,
  subtotal numeric(20,4) NOT NULL DEFAULT 0,
  discount_amount numeric(20,4) NOT NULL DEFAULT 0,
  total_amount numeric(20,4) NOT NULL DEFAULT 0,
  payable_account_id uuid NOT NULL,
  posted_journal_entry_id uuid,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.purchase_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  purchase_id uuid NOT NULL,
  line_number integer NOT NULL,
  product_id uuid NOT NULL,
  quantity numeric(20,6) NOT NULL,
  unit_cost numeric(20,6) NOT NULL,
  line_total numeric(20,4) NOT NULL,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.purchase_returns (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  code text,
  purchase_id uuid NOT NULL,
  supplier_id uuid NOT NULL,
  return_date date NOT NULL,
  status text NOT NULL DEFAULT 'draft'::text,
  confirmed_at timestamp with time zone,
  confirmed_by uuid,
  posted_by uuid,
  voided_at timestamp with time zone,
  voided_by uuid,
  void_reason text,
  subtotal numeric(20,4) NOT NULL DEFAULT 0,
  discount_amount numeric(20,4) NOT NULL DEFAULT 0,
  total_amount numeric(20,4) NOT NULL DEFAULT 0,
  payable_account_id uuid NOT NULL,
  purchase_return_variance_account_id uuid,
  posted_journal_entry_id uuid,
  reversal_journal_entry_id uuid,
  reversed_at timestamp with time zone,
  reversed_by uuid,
  reversal_reason text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.purchase_return_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  purchase_return_id uuid NOT NULL,
  line_number integer NOT NULL,
  purchase_item_id uuid NOT NULL,
  product_id uuid NOT NULL,
  quantity numeric(20,6) NOT NULL,
  unit_cost numeric(20,6) NOT NULL,
  line_total numeric(20,4) NOT NULL,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.sales (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  code text,
  customer_id uuid NOT NULL,
  invoice_date date NOT NULL,
  status text NOT NULL DEFAULT 'draft'::text,
  confirmed_at timestamp with time zone,
  confirmed_by uuid,
  posted_by uuid,
  voided_at timestamp with time zone,
  voided_by uuid,
  void_reason text,
  subtotal numeric(20,4) NOT NULL DEFAULT 0,
  discount_amount numeric(20,4) NOT NULL DEFAULT 0,
  total_amount numeric(20,4) NOT NULL DEFAULT 0,
  receivable_account_id uuid NOT NULL,
  posted_journal_entry_id uuid,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.sales_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  sales_id uuid NOT NULL,
  line_number integer NOT NULL,
  product_id uuid NOT NULL,
  quantity numeric(20,6) NOT NULL,
  unit_price numeric(20,6) NOT NULL,
  line_total numeric(20,4) NOT NULL,
  cogs_unit_cost numeric(20,6) NOT NULL DEFAULT 0,
  cogs_total numeric(20,4) NOT NULL DEFAULT 0,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.sales_returns (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  code text,
  sales_id uuid NOT NULL,
  customer_id uuid NOT NULL,
  return_date date NOT NULL,
  status text NOT NULL DEFAULT 'draft'::text,
  confirmed_at timestamp with time zone,
  confirmed_by uuid,
  posted_by uuid,
  voided_at timestamp with time zone,
  voided_by uuid,
  void_reason text,
  subtotal numeric(20,4) NOT NULL DEFAULT 0,
  discount_amount numeric(20,4) NOT NULL DEFAULT 0,
  total_amount numeric(20,4) NOT NULL DEFAULT 0,
  receivable_account_id uuid NOT NULL,
  posted_journal_entry_id uuid,
  reversal_journal_entry_id uuid,
  reversed_at timestamp with time zone,
  reversed_by uuid,
  reversal_reason text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.sales_return_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  sales_return_id uuid NOT NULL,
  line_number integer NOT NULL,
  sales_item_id uuid NOT NULL,
  product_id uuid NOT NULL,
  quantity numeric(20,6) NOT NULL,
  unit_price numeric(20,6) NOT NULL,
  line_total numeric(20,4) NOT NULL,
  cogs_unit_cost numeric(20,6) NOT NULL DEFAULT 0,
  cogs_total numeric(20,4) NOT NULL DEFAULT 0,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.expenses (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  code text,
  expense_category_id uuid NOT NULL,
  contact_id uuid,
  payable_account_id uuid,
  expense_date date NOT NULL,
  amount numeric(20,4) NOT NULL,
  description text,
  status text NOT NULL DEFAULT 'draft'::text,
  confirmed_at timestamp with time zone,
  confirmed_by uuid,
  posted_by uuid,
  voided_at timestamp with time zone,
  voided_by uuid,
  void_reason text,
  posted_journal_entry_id uuid,
  reversal_journal_entry_id uuid,
  reversed_at timestamp with time zone,
  reversed_by uuid,
  reversal_reason text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.payments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  code text,
  payment_type text NOT NULL,
  contact_id uuid,
  payment_date date NOT NULL,
  amount numeric(20,4) NOT NULL,
  account_id uuid NOT NULL,
  settlement_account_id uuid,
  status text NOT NULL DEFAULT 'draft'::text,
  confirmed_at timestamp with time zone,
  confirmed_by uuid,
  posted_by uuid,
  voided_at timestamp with time zone,
  voided_by uuid,
  void_reason text,
  posted_journal_entry_id uuid,
  reversal_journal_entry_id uuid,
  reversed_at timestamp with time zone,
  reversed_by uuid,
  reversal_reason text,
  description text,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE public.payment_allocations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  payment_id uuid NOT NULL,
  document_type text NOT NULL,
  document_id uuid NOT NULL,
  allocated_amount numeric(20,4) NOT NULL,
  created_by uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid,

  updated_at timestamp with time zone NOT NULL DEFAULT now()
);




-- ===== Replayed: 20261107140952_zero_erp_v1_integrity_foundation.sql =====
-- ZERO ERP V1 integrity foundation
-- Migration equivalent to the integrity foundation applied to zero-erp.
-- Adds primary/foreign keys, same-organization references, checks, unique indexes and safe defaults.

DO $$ DECLARE t text; has_col boolean; BEGIN FOREACH t IN ARRAY ARRAY['organizations','organization_users','accounts','units_of_measure','contacts','products','expense_categories','number_sequences','journal_entries','account_transactions','inventory_transactions','inventory_balances','purchase','purchase_items','purchase_returns','purchase_return_items','sales','sales_items','sales_returns','sales_return_items','expenses','payments','payment_allocations'] LOOP EXECUTE format('ALTER TABLE public.%I ALTER COLUMN id SET DEFAULT gen_random_uuid()',t); SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=t AND column_name='created_at') INTO has_col; IF has_col THEN EXECUTE format('ALTER TABLE public.%I ALTER COLUMN created_at SET DEFAULT now()',t); EXECUTE format('ALTER TABLE public.%I ALTER COLUMN created_at SET NOT NULL',t); END IF; SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=t AND column_name='updated_at') INTO has_col; IF has_col THEN EXECUTE format('ALTER TABLE public.%I ALTER COLUMN updated_at SET DEFAULT now()',t); EXECUTE format('ALTER TABLE public.%I ALTER COLUMN updated_at SET NOT NULL',t); END IF; END LOOP; END $$;
ALTER TABLE public.account_transactions ADD CONSTRAINT account_transactions_pkey PRIMARY KEY (id);
ALTER TABLE public.accounts ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);
ALTER TABLE public.contacts ADD CONSTRAINT contacts_pkey PRIMARY KEY (id);
ALTER TABLE public.expense_categories ADD CONSTRAINT expense_categories_pkey PRIMARY KEY (id);
ALTER TABLE public.expenses ADD CONSTRAINT expenses_pkey PRIMARY KEY (id);
ALTER TABLE public.inventory_balances ADD CONSTRAINT inventory_balances_pkey PRIMARY KEY (id);
ALTER TABLE public.inventory_transactions ADD CONSTRAINT inventory_transactions_pkey PRIMARY KEY (id);
ALTER TABLE public.journal_entries ADD CONSTRAINT journal_entries_pkey PRIMARY KEY (id);
ALTER TABLE public.number_sequences ADD CONSTRAINT number_sequences_pkey PRIMARY KEY (id);
ALTER TABLE public.organization_users ADD CONSTRAINT organization_users_pkey PRIMARY KEY (id);
ALTER TABLE public.organizations ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);
ALTER TABLE public.payment_allocations ADD CONSTRAINT payment_allocations_pkey PRIMARY KEY (id);
ALTER TABLE public.payments ADD CONSTRAINT payments_pkey PRIMARY KEY (id);
ALTER TABLE public.products ADD CONSTRAINT products_pkey PRIMARY KEY (id);
ALTER TABLE public.purchase ADD CONSTRAINT purchase_pkey PRIMARY KEY (id);
ALTER TABLE public.purchase_items ADD CONSTRAINT purchase_items_pkey PRIMARY KEY (id);
ALTER TABLE public.purchase_return_items ADD CONSTRAINT purchase_return_items_pkey PRIMARY KEY (id);
ALTER TABLE public.purchase_returns ADD CONSTRAINT purchase_returns_pkey PRIMARY KEY (id);
ALTER TABLE public.sales ADD CONSTRAINT sales_pkey PRIMARY KEY (id);
ALTER TABLE public.sales_items ADD CONSTRAINT sales_items_pkey PRIMARY KEY (id);
ALTER TABLE public.sales_return_items ADD CONSTRAINT sales_return_items_pkey PRIMARY KEY (id);
ALTER TABLE public.sales_returns ADD CONSTRAINT sales_returns_pkey PRIMARY KEY (id);
ALTER TABLE public.units_of_measure ADD CONSTRAINT units_of_measure_pkey PRIMARY KEY (id);
ALTER TABLE public.account_transactions ADD CONSTRAINT account_transactions_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.accounts ADD CONSTRAINT accounts_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.contacts ADD CONSTRAINT contacts_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.expense_categories ADD CONSTRAINT expense_categories_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.expenses ADD CONSTRAINT expenses_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.inventory_balances ADD CONSTRAINT inventory_balances_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.inventory_transactions ADD CONSTRAINT inventory_transactions_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.journal_entries ADD CONSTRAINT journal_entries_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.number_sequences ADD CONSTRAINT number_sequences_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.organization_users ADD CONSTRAINT organization_users_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.organization_users ADD CONSTRAINT organization_users_org_user_key UNIQUE (organization_id, user_id);
ALTER TABLE public.payment_allocations ADD CONSTRAINT payment_allocations_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.payments ADD CONSTRAINT payments_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.products ADD CONSTRAINT products_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.purchase ADD CONSTRAINT purchase_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.purchase_items ADD CONSTRAINT purchase_items_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.purchase_return_items ADD CONSTRAINT purchase_return_items_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.purchase_returns ADD CONSTRAINT purchase_returns_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.sales ADD CONSTRAINT sales_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.sales_items ADD CONSTRAINT sales_items_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.sales_return_items ADD CONSTRAINT sales_return_items_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.sales_returns ADD CONSTRAINT sales_returns_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.units_of_measure ADD CONSTRAINT units_of_measure_org_id_id_key UNIQUE (organization_id, id);
ALTER TABLE public.account_transactions ADD CONSTRAINT account_transactions_nonnegative_amounts CHECK (((debit >= (0)::numeric) AND (credit >= (0)::numeric)));
ALTER TABLE public.account_transactions ADD CONSTRAINT account_transactions_one_sided_amount CHECK ((NOT ((debit > (0)::numeric) AND (credit > (0)::numeric))));
ALTER TABLE public.expenses ADD CONSTRAINT expenses_nonnegative_amount CHECK ((amount >= (0)::numeric));
ALTER TABLE public.inventory_balances ADD CONSTRAINT inventory_balances_nonnegative_cost CHECK (((average_cost >= (0)::numeric) AND (inventory_value >= (0)::numeric)));
ALTER TABLE public.inventory_balances ADD CONSTRAINT inventory_balances_nonnegative_quantity CHECK ((quantity >= (0)::numeric));
ALTER TABLE public.inventory_transactions ADD CONSTRAINT inventory_transactions_nonnegative_cost CHECK (((unit_cost >= (0)::numeric) AND (total_value >= (0)::numeric)));
ALTER TABLE public.inventory_transactions ADD CONSTRAINT inventory_transactions_positive_quantity CHECK ((quantity > (0)::numeric));
ALTER TABLE public.number_sequences ADD CONSTRAINT number_sequences_next_number_positive CHECK ((next_number > 0));
ALTER TABLE public.number_sequences ADD CONSTRAINT number_sequences_padding_range CHECK (((padding >= 1) AND (padding <= 18)));
ALTER TABLE public.payment_allocations ADD CONSTRAINT payment_allocations_positive_amount CHECK ((allocated_amount > (0)::numeric));
ALTER TABLE public.payments ADD CONSTRAINT payments_nonnegative_amount CHECK ((amount >= (0)::numeric));
ALTER TABLE public.purchase_items ADD CONSTRAINT purchase_items_positive_quantity CHECK (((quantity > (0)::numeric) AND (unit_cost >= (0)::numeric) AND (line_total >= (0)::numeric)));
ALTER TABLE public.purchase_return_items ADD CONSTRAINT purchase_return_items_positive_quantity CHECK (((quantity > (0)::numeric) AND (unit_cost >= (0)::numeric) AND (line_total >= (0)::numeric)));
ALTER TABLE public.sales_items ADD CONSTRAINT sales_items_positive_quantity CHECK (((quantity > (0)::numeric) AND (unit_price >= (0)::numeric) AND (line_total >= (0)::numeric) AND (cogs_unit_cost >= (0)::numeric) AND (cogs_total >= (0)::numeric)));
ALTER TABLE public.sales_return_items ADD CONSTRAINT sales_return_items_positive_quantity CHECK (((quantity > (0)::numeric) AND (unit_price >= (0)::numeric) AND (line_total >= (0)::numeric) AND (cogs_unit_cost >= (0)::numeric) AND (cogs_total >= (0)::numeric)));
ALTER TABLE public.account_transactions ADD CONSTRAINT account_transactions_account_fk FOREIGN KEY (organization_id, account_id) REFERENCES accounts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.account_transactions ADD CONSTRAINT account_transactions_contact_fk FOREIGN KEY (organization_id, contact_id) REFERENCES contacts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.account_transactions ADD CONSTRAINT account_transactions_journal_fk FOREIGN KEY (organization_id, journal_entry_id) REFERENCES journal_entries(organization_id, id) ON DELETE CASCADE;
ALTER TABLE public.account_transactions ADD CONSTRAINT account_transactions_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.accounts ADD CONSTRAINT accounts_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.accounts ADD CONSTRAINT accounts_parent_fk FOREIGN KEY (organization_id, parent_account_id) REFERENCES accounts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.contacts ADD CONSTRAINT contacts_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.expense_categories ADD CONSTRAINT expense_categories_account_fk FOREIGN KEY (organization_id, expense_account_id) REFERENCES accounts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.expense_categories ADD CONSTRAINT expense_categories_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.expenses ADD CONSTRAINT expenses_category_fk FOREIGN KEY (organization_id, expense_category_id) REFERENCES expense_categories(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.expenses ADD CONSTRAINT expenses_contact_fk FOREIGN KEY (organization_id, contact_id) REFERENCES contacts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.expenses ADD CONSTRAINT expenses_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.expenses ADD CONSTRAINT expenses_payable_account_fk FOREIGN KEY (organization_id, payable_account_id) REFERENCES accounts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.expenses ADD CONSTRAINT expenses_posted_journal_fk FOREIGN KEY (organization_id, posted_journal_entry_id) REFERENCES journal_entries(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.expenses ADD CONSTRAINT expenses_reversal_journal_fk FOREIGN KEY (organization_id, reversal_journal_entry_id) REFERENCES journal_entries(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.inventory_balances ADD CONSTRAINT inventory_balances_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.inventory_balances ADD CONSTRAINT inventory_balances_product_fk FOREIGN KEY (organization_id, product_id) REFERENCES products(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.inventory_transactions ADD CONSTRAINT inventory_transactions_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.inventory_transactions ADD CONSTRAINT inventory_transactions_product_fk FOREIGN KEY (organization_id, product_id) REFERENCES products(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.journal_entries ADD CONSTRAINT journal_entries_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.journal_entries ADD CONSTRAINT journal_entries_reversal_entry_fk FOREIGN KEY (organization_id, reversal_journal_entry_id) REFERENCES journal_entries(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.journal_entries ADD CONSTRAINT journal_entries_reversal_of_fk FOREIGN KEY (organization_id, reversal_of_id) REFERENCES journal_entries(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.number_sequences ADD CONSTRAINT number_sequences_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.organization_users ADD CONSTRAINT organization_users_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.organization_users ADD CONSTRAINT organization_users_user_fk FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.payment_allocations ADD CONSTRAINT payment_allocations_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.payment_allocations ADD CONSTRAINT payment_allocations_payment_fk FOREIGN KEY (organization_id, payment_id) REFERENCES payments(organization_id, id) ON DELETE CASCADE;
ALTER TABLE public.payments ADD CONSTRAINT payments_account_fk FOREIGN KEY (organization_id, account_id) REFERENCES accounts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.payments ADD CONSTRAINT payments_contact_fk FOREIGN KEY (organization_id, contact_id) REFERENCES contacts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.payments ADD CONSTRAINT payments_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.payments ADD CONSTRAINT payments_posted_journal_fk FOREIGN KEY (organization_id, posted_journal_entry_id) REFERENCES journal_entries(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.payments ADD CONSTRAINT payments_reversal_journal_fk FOREIGN KEY (organization_id, reversal_journal_entry_id) REFERENCES journal_entries(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.payments ADD CONSTRAINT payments_settlement_account_fk FOREIGN KEY (organization_id, settlement_account_id) REFERENCES accounts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.products ADD CONSTRAINT products_cogs_account_fk FOREIGN KEY (organization_id, cogs_account_id) REFERENCES accounts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.products ADD CONSTRAINT products_inventory_account_fk FOREIGN KEY (organization_id, inventory_account_id) REFERENCES accounts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.products ADD CONSTRAINT products_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.products ADD CONSTRAINT products_sales_account_fk FOREIGN KEY (organization_id, sales_account_id) REFERENCES accounts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.products ADD CONSTRAINT products_unit_fk FOREIGN KEY (organization_id, unit_id) REFERENCES units_of_measure(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.purchase ADD CONSTRAINT purchase_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.purchase ADD CONSTRAINT purchase_payable_account_fk FOREIGN KEY (organization_id, payable_account_id) REFERENCES accounts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.purchase ADD CONSTRAINT purchase_posted_journal_fk FOREIGN KEY (organization_id, posted_journal_entry_id) REFERENCES journal_entries(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.purchase ADD CONSTRAINT purchase_supplier_fk FOREIGN KEY (organization_id, supplier_id) REFERENCES contacts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.purchase_items ADD CONSTRAINT purchase_items_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_items ADD CONSTRAINT purchase_items_product_fk FOREIGN KEY (organization_id, product_id) REFERENCES products(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.purchase_items ADD CONSTRAINT purchase_items_purchase_fk FOREIGN KEY (organization_id, purchase_id) REFERENCES purchase(organization_id, id) ON DELETE CASCADE;
ALTER TABLE public.purchase_return_items ADD CONSTRAINT purchase_return_items_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_return_items ADD CONSTRAINT purchase_return_items_product_fk FOREIGN KEY (organization_id, product_id) REFERENCES products(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.purchase_return_items ADD CONSTRAINT purchase_return_items_purchase_item_fk FOREIGN KEY (organization_id, purchase_item_id) REFERENCES purchase_items(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.purchase_return_items ADD CONSTRAINT purchase_return_items_return_fk FOREIGN KEY (organization_id, purchase_return_id) REFERENCES purchase_returns(organization_id, id) ON DELETE CASCADE;
ALTER TABLE public.purchase_returns ADD CONSTRAINT purchase_returns_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_returns ADD CONSTRAINT purchase_returns_payable_account_fk FOREIGN KEY (organization_id, payable_account_id) REFERENCES accounts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.purchase_returns ADD CONSTRAINT purchase_returns_posted_journal_fk FOREIGN KEY (organization_id, posted_journal_entry_id) REFERENCES journal_entries(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.purchase_returns ADD CONSTRAINT purchase_returns_purchase_fk FOREIGN KEY (organization_id, purchase_id) REFERENCES purchase(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.purchase_returns ADD CONSTRAINT purchase_returns_reversal_journal_fk FOREIGN KEY (organization_id, reversal_journal_entry_id) REFERENCES journal_entries(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.purchase_returns ADD CONSTRAINT purchase_returns_supplier_fk FOREIGN KEY (organization_id, supplier_id) REFERENCES contacts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.purchase_returns ADD CONSTRAINT purchase_returns_variance_account_fk FOREIGN KEY (organization_id, purchase_return_variance_account_id) REFERENCES accounts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.sales ADD CONSTRAINT sales_customer_fk FOREIGN KEY (organization_id, customer_id) REFERENCES contacts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.sales ADD CONSTRAINT sales_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.sales ADD CONSTRAINT sales_posted_journal_fk FOREIGN KEY (organization_id, posted_journal_entry_id) REFERENCES journal_entries(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.sales ADD CONSTRAINT sales_receivable_account_fk FOREIGN KEY (organization_id, receivable_account_id) REFERENCES accounts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.sales_items ADD CONSTRAINT sales_items_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.sales_items ADD CONSTRAINT sales_items_product_fk FOREIGN KEY (organization_id, product_id) REFERENCES products(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.sales_items ADD CONSTRAINT sales_items_sales_fk FOREIGN KEY (organization_id, sales_id) REFERENCES sales(organization_id, id) ON DELETE CASCADE;
ALTER TABLE public.sales_return_items ADD CONSTRAINT sales_return_items_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.sales_return_items ADD CONSTRAINT sales_return_items_product_fk FOREIGN KEY (organization_id, product_id) REFERENCES products(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.sales_return_items ADD CONSTRAINT sales_return_items_return_fk FOREIGN KEY (organization_id, sales_return_id) REFERENCES sales_returns(organization_id, id) ON DELETE CASCADE;
ALTER TABLE public.sales_return_items ADD CONSTRAINT sales_return_items_sales_item_fk FOREIGN KEY (organization_id, sales_item_id) REFERENCES sales_items(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.sales_returns ADD CONSTRAINT sales_returns_customer_fk FOREIGN KEY (organization_id, customer_id) REFERENCES contacts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.sales_returns ADD CONSTRAINT sales_returns_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE public.sales_returns ADD CONSTRAINT sales_returns_posted_journal_fk FOREIGN KEY (organization_id, posted_journal_entry_id) REFERENCES journal_entries(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.sales_returns ADD CONSTRAINT sales_returns_receivable_account_fk FOREIGN KEY (organization_id, receivable_account_id) REFERENCES accounts(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.sales_returns ADD CONSTRAINT sales_returns_reversal_journal_fk FOREIGN KEY (organization_id, reversal_journal_entry_id) REFERENCES journal_entries(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.sales_returns ADD CONSTRAINT sales_returns_sales_fk FOREIGN KEY (organization_id, sales_id) REFERENCES sales(organization_id, id) ON DELETE RESTRICT;
ALTER TABLE public.units_of_measure ADD CONSTRAINT units_of_measure_organization_fk FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
CREATE UNIQUE INDEX account_transactions_line_uidx ON public.account_transactions USING btree (organization_id, journal_entry_id, line_number);
CREATE UNIQUE INDEX accounts_code_uidx ON public.accounts USING btree (organization_id, code);
CREATE UNIQUE INDEX accounts_name_ci_uidx ON public.accounts USING btree (organization_id, lower(account_name));
CREATE UNIQUE INDEX contacts_code_uidx ON public.contacts USING btree (organization_id, code);
CREATE UNIQUE INDEX expense_categories_code_uidx ON public.expense_categories USING btree (organization_id, code);
CREATE UNIQUE INDEX expenses_code_uidx ON public.expenses USING btree (organization_id, code) WHERE (code IS NOT NULL);
CREATE UNIQUE INDEX inventory_balances_product_uidx ON public.inventory_balances USING btree (organization_id, product_id);
CREATE UNIQUE INDEX inventory_transactions_code_uidx ON public.inventory_transactions USING btree (organization_id, code);
CREATE UNIQUE INDEX journal_entries_code_uidx ON public.journal_entries USING btree (organization_id, code) WHERE (code IS NOT NULL);
CREATE UNIQUE INDEX journal_entries_one_opening_uidx ON public.journal_entries USING btree (organization_id) WHERE (entry_type = 'opening_balance'::text);
CREATE UNIQUE INDEX number_sequences_type_uidx ON public.number_sequences USING btree (organization_id, document_type);
CREATE UNIQUE INDEX organizations_email_ci_uidx ON public.organizations USING btree (lower(email)) WHERE (email IS NOT NULL);
CREATE UNIQUE INDEX payments_code_uidx ON public.payments USING btree (organization_id, code) WHERE (code IS NOT NULL);
CREATE UNIQUE INDEX products_code_uidx ON public.products USING btree (organization_id, code);
CREATE UNIQUE INDEX purchase_code_uidx ON public.purchase USING btree (organization_id, code) WHERE (code IS NOT NULL);
CREATE UNIQUE INDEX purchase_items_line_uidx ON public.purchase_items USING btree (organization_id, purchase_id, line_number);
CREATE UNIQUE INDEX purchase_return_items_line_uidx ON public.purchase_return_items USING btree (organization_id, purchase_return_id, line_number);
CREATE UNIQUE INDEX purchase_returns_code_uidx ON public.purchase_returns USING btree (organization_id, code) WHERE (code IS NOT NULL);
CREATE UNIQUE INDEX sales_code_uidx ON public.sales USING btree (organization_id, code) WHERE (code IS NOT NULL);
CREATE UNIQUE INDEX sales_items_line_uidx ON public.sales_items USING btree (organization_id, sales_id, line_number);
CREATE UNIQUE INDEX sales_return_items_line_uidx ON public.sales_return_items USING btree (organization_id, sales_return_id, line_number);
CREATE UNIQUE INDEX sales_returns_code_uidx ON public.sales_returns USING btree (organization_id, code) WHERE (code IS NOT NULL);
CREATE UNIQUE INDEX units_name_ci_uidx ON public.units_of_measure USING btree (organization_id, lower(name));



-- ===== Replayed: 20261107141128_zero_erp_v1_rls_security.sql =====
-- ZERO ERP V1 row-level security and organization access policies
-- Active members may operate business records; creator controls organization and system setup.

CREATE OR REPLACE FUNCTION public.is_org_member(p_organization_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
 SELECT EXISTS (SELECT 1 FROM public.organization_users ou
  WHERE ou.organization_id=p_organization_id AND ou.user_id=auth.uid() AND ou.status='active');
$$;
CREATE OR REPLACE FUNCTION public.is_org_creator(p_organization_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = ''
AS $$
 SELECT EXISTS (SELECT 1 FROM public.organizations o
  WHERE o.id=p_organization_id AND o.created_by=auth.uid());
$$;
REVOKE ALL ON FUNCTION public.is_org_member(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_org_creator(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_org_member(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_org_creator(uuid) TO authenticated, service_role;
GRANT USAGE ON SCHEMA public TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated, service_role;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
CREATE POLICY organizations_select_member_or_creator ON public.organizations FOR SELECT TO authenticated
 USING (created_by=(SELECT auth.uid()) OR public.is_org_member(id) OR public.is_org_creator(id));
CREATE POLICY organizations_insert_creator ON public.organizations FOR INSERT TO authenticated
 WITH CHECK (created_by=(SELECT auth.uid()));
CREATE POLICY organizations_update_creator ON public.organizations FOR UPDATE TO authenticated
 USING (public.is_org_creator(id)) WITH CHECK (public.is_org_creator(id));
CREATE POLICY organizations_delete_creator ON public.organizations FOR DELETE TO authenticated
 USING (public.is_org_creator(id));

ALTER TABLE public.organization_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY organization_users_select_member ON public.organization_users FOR SELECT TO authenticated
 USING (public.is_org_member(organization_id) OR public.is_org_creator(organization_id));
CREATE POLICY organization_users_insert_creator ON public.organization_users FOR INSERT TO authenticated
 WITH CHECK (public.is_org_creator(organization_id));
CREATE POLICY organization_users_update_creator ON public.organization_users FOR UPDATE TO authenticated
 USING (public.is_org_creator(organization_id)) WITH CHECK (public.is_org_creator(organization_id));
CREATE POLICY organization_users_delete_creator ON public.organization_users FOR DELETE TO authenticated
 USING (public.is_org_creator(organization_id));

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['accounts','units_of_measure','expense_categories','number_sequences'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (public.is_org_member(organization_id) OR public.is_org_creator(organization_id))',t||'_select_member',t);
  EXECUTE format('CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING (public.is_org_creator(organization_id)) WITH CHECK (public.is_org_creator(organization_id))',t||'_creator_manage',t);
 END LOOP;
END $$;

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['contacts','products','journal_entries','account_transactions','inventory_transactions','inventory_balances','purchase','purchase_items','purchase_returns','purchase_return_items','sales','sales_items','sales_returns','sales_return_items','expenses','payments','payment_allocations'] LOOP
  EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING (public.is_org_member(organization_id) OR public.is_org_creator(organization_id)) WITH CHECK (public.is_org_member(organization_id) OR public.is_org_creator(organization_id))',t||'_member_all',t);
 END LOOP;
END $$;


-- ===== Replayed: 20261107141158_zero_erp_v1_private_security_helpers.sql =====
-- Move security-definer RLS helpers outside the exposed Data API schemas.

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated, service_role;
ALTER FUNCTION public.is_org_member(uuid) SET SCHEMA private;
ALTER FUNCTION public.is_org_creator(uuid) SET SCHEMA private;
GRANT EXECUTE ON FUNCTION private.is_org_member(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.is_org_creator(uuid) TO authenticated, service_role;


-- ===== Replayed: 20261107141326_zero_erp_v1_audit_and_sequences.sql =====
-- ZERO ERP V1 audit fields and atomic document numbering

CREATE OR REPLACE FUNCTION private.apply_audit_fields()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
DECLARE v_row jsonb := to_jsonb(NEW); v_uid uuid := auth.uid();
BEGIN
 IF TG_OP='INSERT' THEN
  IF v_uid IS NOT NULL AND v_row ? 'created_by' AND v_row->>'created_by' IS NULL THEN
   v_row := v_row || jsonb_build_object('created_by',v_uid);
  END IF;
  IF v_uid IS NOT NULL AND v_row ? 'updated_by' AND v_row->>'updated_by' IS NULL THEN
   v_row := v_row || jsonb_build_object('updated_by',v_uid);
  END IF;
  IF v_row ? 'updated_at' THEN v_row := v_row || jsonb_build_object('updated_at',now()); END IF;
 ELSE
  IF v_row ? 'updated_at' THEN v_row := v_row || jsonb_build_object('updated_at',now()); END IF;
  IF v_uid IS NOT NULL AND v_row ? 'updated_by' THEN v_row := v_row || jsonb_build_object('updated_by',v_uid); END IF;
 END IF;
 NEW := jsonb_populate_record(NEW,v_row);
 RETURN NEW;
END;
$$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['organizations','organization_users','accounts','units_of_measure','contacts','products','expense_categories','number_sequences','journal_entries','account_transactions','inventory_balances','purchase','purchase_items','purchase_returns','purchase_return_items','sales','sales_items','sales_returns','sales_return_items','expenses','payments','payment_allocations'] LOOP
  EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION private.apply_audit_fields()',t||'_audit_fields',t);
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION public.next_document_number(p_organization_id uuid,p_document_type text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_prefix text; v_number bigint; v_padding smallint;
BEGIN
 IF auth.uid() IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
  RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
 END IF;
 IF p_document_type IS NULL OR btrim(p_document_type)='' THEN
  RAISE EXCEPTION 'Document type is required' USING ERRCODE='22023';
 END IF;
 UPDATE public.number_sequences SET next_number=next_number+1,updated_at=now()
 WHERE organization_id=p_organization_id AND document_type=p_document_type
 RETURNING prefix,next_number-1,padding INTO v_prefix,v_number,v_padding;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'Number sequence is not configured for document type %',p_document_type USING ERRCODE='P0002';
 END IF;
 RETURN v_prefix || CASE WHEN length(v_number::text)>=v_padding THEN v_number::text ELSE lpad(v_number::text,v_padding,'0') END;
END;
$$;
REVOKE ALL ON FUNCTION public.next_document_number(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.next_document_number(uuid,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.apply_audit_fields() TO authenticated, service_role;


-- ===== Replayed: 20261107141347_fix_document_number_overflow.sql =====
-- Prevent lpad truncation when a sequence number exceeds its configured padding.
CREATE OR REPLACE FUNCTION public.next_document_number(p_organization_id uuid,p_document_type text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE v_prefix text; v_number bigint; v_padding smallint;
BEGIN
 IF auth.uid() IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
  RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
 END IF;
 IF p_document_type IS NULL OR btrim(p_document_type)='' THEN
  RAISE EXCEPTION 'Document type is required' USING ERRCODE='22023';
 END IF;
 UPDATE public.number_sequences SET next_number=next_number+1,updated_at=now()
 WHERE organization_id=p_organization_id AND document_type=p_document_type
 RETURNING prefix,next_number-1,padding INTO v_prefix,v_number,v_padding;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'Number sequence is not configured for document type %',p_document_type USING ERRCODE='P0002';
 END IF;
 RETURN v_prefix || CASE WHEN length(v_number::text)>=v_padding THEN v_number::text ELSE lpad(v_number::text,v_padding,'0') END;
END;
$$;
REVOKE ALL ON FUNCTION public.next_document_number(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.next_document_number(uuid,text) TO authenticated, service_role;

-- ===== Replayed: 20261107141508_zero_erp_v1_fk_indexes_and_policy_tuning.sql =====
-- ZERO ERP V1 foreign-key index coverage and RLS policy tuning

DO $$
DECLARE r record; v_index_name text; v_columns text;
BEGIN
 FOR r IN
  SELECT c.oid,c.conrelid,t.relname AS table_name,
         array_agg(a.attname ORDER BY k.ord) AS column_names
  FROM pg_constraint c
  JOIN pg_class t ON t.oid=c.conrelid
  JOIN pg_namespace n ON n.oid=t.relnamespace
  CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attnum,ord)
  JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.attnum
  WHERE c.contype='f' AND n.nspname='public'
   AND NOT EXISTS (
    SELECT 1 FROM pg_index i WHERE i.indrelid=c.conrelid AND i.indisvalid
     AND (SELECT array_agg(x.attnum::smallint ORDER BY x.ord)
          FROM unnest(i.indkey) WITH ORDINALITY AS x(attnum,ord)
          WHERE x.ord<=cardinality(c.conkey))=c.conkey
   )
  GROUP BY c.oid,t.relname
 LOOP
  v_index_name:=left(r.table_name||'_'||array_to_string(r.column_names,'_')||'_fk_idx',63);
  SELECT string_agg(format('%I',col),',') INTO v_columns FROM unnest(r.column_names) AS col;
  EXECUTE format('CREATE INDEX %I ON public.%I (%s)',v_index_name,r.table_name,v_columns);
 END LOOP;
END $$;

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['accounts','units_of_measure','expense_categories','number_sequences'] LOOP
  EXECUTE format('DROP POLICY %I ON public.%I',t||'_creator_manage',t);
  EXECUTE format('CREATE POLICY %I ON public.%I FOR INSERT TO authenticated WITH CHECK (private.is_org_creator(organization_id))',t||'_creator_insert',t);
  EXECUTE format('CREATE POLICY %I ON public.%I FOR UPDATE TO authenticated USING (private.is_org_creator(organization_id)) WITH CHECK (private.is_org_creator(organization_id))',t||'_creator_update',t);
  EXECUTE format('CREATE POLICY %I ON public.%I FOR DELETE TO authenticated USING (private.is_org_creator(organization_id))',t||'_creator_delete',t);
 END LOOP;
END $$;

DROP POLICY inventory_transactions_member_all ON public.inventory_transactions;
CREATE POLICY inventory_transactions_member_select ON public.inventory_transactions
 FOR SELECT TO authenticated USING (private.is_org_member(organization_id) OR private.is_org_creator(organization_id));
CREATE POLICY inventory_transactions_member_insert ON public.inventory_transactions
 FOR INSERT TO authenticated WITH CHECK (private.is_org_member(organization_id) OR private.is_org_creator(organization_id));


-- ===== Replayed: 20261107141553_harden_audit_metadata.sql =====
-- Prevent client spoofing of audit columns and cross-organization row moves.
CREATE OR REPLACE FUNCTION private.apply_audit_fields()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
DECLARE v_row jsonb:=to_jsonb(NEW); v_old jsonb; v_uid uuid:=auth.uid();
BEGIN
 IF TG_OP='INSERT' THEN
  IF v_uid IS NOT NULL AND v_row ? 'created_by' THEN v_row:=v_row||jsonb_build_object('created_by',v_uid); END IF;
  IF v_uid IS NOT NULL AND v_row ? 'updated_by' THEN v_row:=v_row||jsonb_build_object('updated_by',v_uid); END IF;
  IF v_row ? 'updated_at' THEN v_row:=v_row||jsonb_build_object('updated_at',now()); END IF;
 ELSE
  v_old:=to_jsonb(OLD);
  IF v_row ? 'id' AND v_row->'id' IS DISTINCT FROM v_old->'id' THEN
   RAISE EXCEPTION 'Primary key is immutable' USING ERRCODE='22000';
  END IF;
  IF v_row ? 'organization_id' AND v_row->'organization_id' IS DISTINCT FROM v_old->'organization_id' THEN
   RAISE EXCEPTION 'organization_id is immutable' USING ERRCODE='22000';
  END IF;
  IF v_row ? 'created_by' THEN v_row:=v_row||jsonb_build_object('created_by',v_old->'created_by'); END IF;
  IF v_row ? 'updated_at' THEN v_row:=v_row||jsonb_build_object('updated_at',now()); END IF;
  IF v_uid IS NOT NULL AND v_row ? 'updated_by' THEN v_row:=v_row||jsonb_build_object('updated_by',v_uid); END IF;
 END IF;
 NEW:=jsonb_populate_record(NEW,v_row);
 RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS inventory_transactions_audit_fields ON public.inventory_transactions;
CREATE TRIGGER inventory_transactions_audit_fields BEFORE INSERT ON public.inventory_transactions
 FOR EACH ROW EXECUTE FUNCTION private.apply_audit_fields();

-- ===== Replayed: 20261107141702_zero_erp_v1_workflow_guardrails.sql =====
-- Draft-only document editing and controlled workflow transitions.

CREATE OR REPLACE FUNCTION private.enforce_draft_document()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
DECLARE v_old jsonb; v_new jsonb;
BEGIN
 IF current_user IN ('postgres','service_role') AND current_setting('zero_erp.allow_workflow',true)='on' THEN
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
 END IF;
 IF TG_OP='INSERT' THEN
  IF to_jsonb(NEW)->>'status' IS DISTINCT FROM 'draft' THEN
   RAISE EXCEPTION 'New documents must start in draft status' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
 ELSIF TG_OP='DELETE' THEN
  IF to_jsonb(OLD)->>'status' IS DISTINCT FROM 'draft' THEN
   RAISE EXCEPTION 'Only draft documents can be deleted' USING ERRCODE='23514';
  END IF;
  RETURN OLD;
 ELSE
  v_old:=to_jsonb(OLD); v_new:=to_jsonb(NEW);
  IF v_old->>'status' IS DISTINCT FROM 'draft' THEN
   RAISE EXCEPTION 'Non-draft documents are immutable outside workflow RPCs' USING ERRCODE='23514';
  END IF;
  IF v_new->>'status' IS DISTINCT FROM v_old->>'status' THEN
   RAISE EXCEPTION 'Document status can only change through workflow RPCs' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
 END IF;
END;
$$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['journal_entries','purchase','purchase_returns','sales','sales_returns','expenses','payments'] LOOP
  EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION private.enforce_draft_document()',t||'_draft_guard',t);
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION private.enforce_draft_line()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
DECLARE v_row jsonb; v_org uuid; v_parent uuid; v_status text; v_entry_type text; v_org_status text;
 v_table text:=TG_ARGV[0]; v_parent_column text:=TG_ARGV[1];
BEGIN
 IF current_user IN ('postgres','service_role') AND current_setting('zero_erp.allow_workflow',true)='on' THEN
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
 END IF;
 v_row:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 v_org:=(v_row->>'organization_id')::uuid; v_parent:=(v_row->>v_parent_column)::uuid;
 EXECUTE format('SELECT status FROM public.%I WHERE organization_id=$1 AND id=$2',v_table) INTO v_status USING v_org,v_parent;
 IF v_status IS DISTINCT FROM 'draft' THEN RAISE EXCEPTION 'Document lines can only be changed while the parent document is draft' USING ERRCODE='23514'; END IF;
 IF v_table='journal_entries' THEN
  EXECUTE 'SELECT entry_type FROM public.journal_entries WHERE organization_id=$1 AND id=$2' INTO v_entry_type USING v_org,v_parent;
  IF v_entry_type='opening_balance' THEN
   SELECT status INTO v_org_status FROM public.organizations WHERE id=v_org;
   IF v_org_status IS DISTINCT FROM 'configuring' THEN RAISE EXCEPTION 'Opening journal lines can only be changed while organization is configuring' USING ERRCODE='23514'; END IF;
  END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;
CREATE TRIGGER account_transactions_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON public.account_transactions
 FOR EACH ROW EXECUTE FUNCTION private.enforce_draft_line('journal_entries','journal_entry_id');
CREATE TRIGGER purchase_items_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON public.purchase_items
 FOR EACH ROW EXECUTE FUNCTION private.enforce_draft_line('purchase','purchase_id');
CREATE TRIGGER purchase_return_items_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON public.purchase_return_items
 FOR EACH ROW EXECUTE FUNCTION private.enforce_draft_line('purchase_returns','purchase_return_id');
CREATE TRIGGER sales_items_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON public.sales_items
 FOR EACH ROW EXECUTE FUNCTION private.enforce_draft_line('sales','sales_id');
CREATE TRIGGER sales_return_items_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON public.sales_return_items
 FOR EACH ROW EXECUTE FUNCTION private.enforce_draft_line('sales_returns','sales_return_id');
CREATE TRIGGER payment_allocations_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON public.payment_allocations
 FOR EACH ROW EXECUTE FUNCTION private.enforce_draft_line('payments','payment_id');

CREATE OR REPLACE FUNCTION private.enforce_organization_lifecycle()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
BEGIN
 IF NEW.status IS DISTINCT FROM OLD.status AND NOT (current_user IN ('postgres','service_role') AND current_setting('zero_erp.allow_workflow',true)='on') THEN
  RAISE EXCEPTION 'Organization lifecycle changes must use the setup completion workflow' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$$;
CREATE TRIGGER organizations_lifecycle_guard BEFORE UPDATE OF status ON public.organizations
 FOR EACH ROW EXECUTE FUNCTION private.enforce_organization_lifecycle();

DROP POLICY inventory_transactions_member_insert ON public.inventory_transactions;
DROP POLICY inventory_balances_member_all ON public.inventory_balances;
CREATE POLICY inventory_balances_member_select ON public.inventory_balances
 FOR SELECT TO authenticated USING (private.is_org_member(organization_id) OR private.is_org_creator(organization_id));


-- ===== Replayed: 20261107141715_fix_line_guard_parent_move.sql =====
-- Ensure a draft line cannot be moved away from a non-draft parent document.
CREATE OR REPLACE FUNCTION private.enforce_draft_line()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
DECLARE v_row jsonb; v_old jsonb; v_org uuid; v_parent uuid; v_old_parent uuid;
 v_status text; v_entry_type text; v_org_status text; v_table text:=TG_ARGV[0]; v_parent_column text:=TG_ARGV[1];
BEGIN
 IF current_user IN ('postgres','service_role') AND current_setting('zero_erp.allow_workflow',true)='on' THEN IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF; END IF;
 v_row:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 v_org:=(v_row->>'organization_id')::uuid; v_parent:=(v_row->>v_parent_column)::uuid;
 EXECUTE format('SELECT status FROM public.%I WHERE organization_id=$1 AND id=$2',v_table) INTO v_status USING v_org,v_parent;
 IF v_status IS DISTINCT FROM 'draft' THEN RAISE EXCEPTION 'Document lines can only be changed while the parent document is draft' USING ERRCODE='23514'; END IF;
 IF v_table='journal_entries' THEN
  EXECUTE 'SELECT entry_type FROM public.journal_entries WHERE organization_id=$1 AND id=$2' INTO v_entry_type USING v_org,v_parent;
  IF v_entry_type='opening_balance' THEN SELECT status INTO v_org_status FROM public.organizations WHERE id=v_org;
   IF v_org_status IS DISTINCT FROM 'configuring' THEN RAISE EXCEPTION 'Opening journal lines can only be changed while organization is configuring' USING ERRCODE='23514'; END IF;
  END IF;
 END IF;
 IF TG_OP='UPDATE' THEN
  v_old:=to_jsonb(OLD);
  IF v_old->>v_parent_column IS DISTINCT FROM v_row->>v_parent_column THEN
   v_old_parent:=(v_old->>v_parent_column)::uuid;
   EXECUTE format('SELECT status FROM public.%I WHERE organization_id=$1 AND id=$2',v_table) INTO v_status USING v_org,v_old_parent;
   IF v_status IS DISTINCT FROM 'draft' THEN RAISE EXCEPTION 'Lines belonging to a non-draft document cannot be moved' USING ERRCODE='23514'; END IF;
  END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;

-- ===== Replayed: 20261107141727_fix_line_guard_opening_move.sql =====
-- Also enforce the opening-journal configuring-state rule on the old parent when a line is moved.
CREATE OR REPLACE FUNCTION private.enforce_draft_line()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $$
DECLARE v_row jsonb; v_old jsonb; v_org uuid; v_parent uuid; v_old_parent uuid;
 v_status text; v_entry_type text; v_org_status text; v_table text:=TG_ARGV[0]; v_parent_column text:=TG_ARGV[1];
BEGIN
 IF current_user IN ('postgres','service_role') AND current_setting('zero_erp.allow_workflow',true)='on' THEN IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF; END IF;
 v_row:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 v_org:=(v_row->>'organization_id')::uuid; v_parent:=(v_row->>v_parent_column)::uuid;
 EXECUTE format('SELECT status FROM public.%I WHERE organization_id=$1 AND id=$2',v_table) INTO v_status USING v_org,v_parent;
 IF v_status IS DISTINCT FROM 'draft' THEN RAISE EXCEPTION 'Document lines can only be changed while the parent document is draft' USING ERRCODE='23514'; END IF;
 IF v_table='journal_entries' THEN
  EXECUTE 'SELECT entry_type FROM public.journal_entries WHERE organization_id=$1 AND id=$2' INTO v_entry_type USING v_org,v_parent;
  IF v_entry_type='opening_balance' THEN SELECT status INTO v_org_status FROM public.organizations WHERE id=v_org;
   IF v_org_status IS DISTINCT FROM 'configuring' THEN RAISE EXCEPTION 'Opening journal lines can only be changed while organization is configuring' USING ERRCODE='23514'; END IF;
  END IF;
 END IF;
 IF TG_OP='UPDATE' THEN
  v_old:=to_jsonb(OLD);
  IF v_old->>v_parent_column IS DISTINCT FROM v_row->>v_parent_column THEN
   v_old_parent:=(v_old->>v_parent_column)::uuid;
   EXECUTE format('SELECT status FROM public.%I WHERE organization_id=$1 AND id=$2',v_table) INTO v_status USING v_org,v_old_parent;
   IF v_status IS DISTINCT FROM 'draft' THEN RAISE EXCEPTION 'Lines belonging to a non-draft document cannot be moved' USING ERRCODE='23514'; END IF;
   IF v_table='journal_entries' THEN
    EXECUTE 'SELECT entry_type FROM public.journal_entries WHERE organization_id=$1 AND id=$2' INTO v_entry_type USING v_org,v_old_parent;
    IF v_entry_type='opening_balance' THEN SELECT status INTO v_org_status FROM public.organizations WHERE id=v_org;
     IF v_org_status IS DISTINCT FROM 'configuring' THEN RAISE EXCEPTION 'Opening journal lines cannot be moved after activation' USING ERRCODE='23514'; END IF;
    END IF;
   END IF;
  END IF;
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;

-- ===== Replayed: 20261107142619_zero_erp_v1_accounting_defaults_and_sequences.sql =====
-- ZERO ERP V1 accounting defaults and immutable sequence configuration.


alter table public.number_sequences
  add column increment_by bigint not null default 1;
alter table public.number_sequences
  add constraint number_sequences_increment_positive check (increment_by > 0);

-- Number sequence configuration is system-managed. Members may read it;
-- only SECURITY DEFINER workflows may create/configure/advance sequences.
drop policy if exists number_sequences_creator_delete on public.number_sequences;
drop policy if exists number_sequences_creator_insert on public.number_sequences;
drop policy if exists number_sequences_creator_update on public.number_sequences;

create table private.default_account_templates (
  code text primary key,
  account_name text not null,
  account_type text not null check (account_type in ('asset','liability','equity','income','expense')),
  normal_balance text not null check (normal_balance in ('debit','credit')),
  parent_code text references private.default_account_templates(code),
  is_control_account boolean not null default false,
  is_postable boolean not null default true
);

insert into private.default_account_templates
  (code, account_name, account_type, normal_balance, parent_code, is_control_account, is_postable)
values
  ('1100','Current Assets','asset','debit',null,false,false),
  ('1110','Cash in Hand','asset','debit','1100',false,true),
  ('1120','Bank Account','asset','debit','1100',false,true),
  ('1130','Accounts Receivable','asset','debit','1100',true,true),
  ('1140','Inventory Asset','asset','debit','1100',true,true),
  ('2100','Current Liabilities','liability','credit',null,false,false),
  ('2110','Accounts Payable','liability','credit','2100',true,true),
  ('3100','Owner''s Capital','equity','credit',null,false,true),
  ('3200','Opening Balance Equity','equity','credit',null,false,true),
  ('4100','Sales Revenue','income','credit',null,false,true),
  ('4200','Other Income','income','credit',null,false,true),
  ('5100','Cost of Goods Sold','expense','debit',null,false,true),
  ('5200','General Expenses','expense','debit',null,false,true);

create table private.default_expense_category_templates (
  code text primary key,
  name text not null
);

insert into private.default_expense_category_templates(code, name) values
  ('EXP001','Salary & Wages'),
  ('EXP002','Office Rent'),
  ('EXP003','Electricity Bill'),
  ('EXP004','Water Bill'),
  ('EXP005','Internet & Telephone'),
  ('EXP006','Transportation'),
  ('EXP007','Office Supplies'),
  ('EXP008','Marketing & Advertising'),
  ('EXP009','Repair & Maintenance'),
  ('EXP010','Entertainment'),
  ('EXP011','Bank Charges'),
  ('EXP012','Miscellaneous Expenses');

revoke all on private.default_account_templates from public, anon, authenticated;
revoke all on private.default_expense_category_templates from public, anon, authenticated;

-- Seed all standard accounts, expense categories, and fixed system sequences
-- for a newly-created organization. Called only from trusted provisioning RPCs.
create or replace function private.seed_organization_configuration(p_organization_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_organization_id is null
     or not exists (select 1 from public.organizations o where o.id = p_organization_id) then
    raise exception 'Organization does not exist' using errcode = '23503';
  end if;

  if exists (select 1 from public.accounts a where a.organization_id = p_organization_id)
     or exists (select 1 from public.number_sequences n where n.organization_id = p_organization_id) then
    raise exception 'Organization configuration has already been seeded' using errcode = '23505';
  end if;

  insert into public.accounts
    (organization_id, code, account_name, account_type, parent_account_id,
     normal_balance, is_control_account, is_postable, status)
  select p_organization_id, t.code, t.account_name, t.account_type, parent.id,
         t.normal_balance, t.is_control_account, t.is_postable, 'active'
    from private.default_account_templates t
    left join public.accounts parent
      on parent.organization_id = p_organization_id
     and parent.code = t.parent_code
   order by t.code;

  insert into public.expense_categories
    (organization_id, code, name, expense_account_id, status)
  select p_organization_id, c.code, c.name, a.id, true
    from private.default_expense_category_templates c
    join public.accounts a
      on a.organization_id = p_organization_id and a.code = '5200'
   order by c.code;

  insert into public.number_sequences
    (organization_id, document_type, prefix, next_number, padding, increment_by)
  values
    (p_organization_id,'account_asset','',1150,4,10),
    (p_organization_id,'account_liability','',2120,4,10),
    (p_organization_id,'account_equity','',3210,4,10),
    (p_organization_id,'account_income','',4210,4,10),
    (p_organization_id,'account_expense','',5210,4,10),
    (p_organization_id,'contacts','CON',1,6,1),
    (p_organization_id,'products','PRD',1,6,1),
    (p_organization_id,'expense_categories','CAT',1,6,1),
    (p_organization_id,'expenses','EXP',1,6,1),
    (p_organization_id,'payments','PAY',1,6,1),
    (p_organization_id,'purchase','PUR',1,6,1),
    (p_organization_id,'sales','INV',1,6,1),
    (p_organization_id,'purchase_returns','PR',1,6,1),
    (p_organization_id,'sales_returns','SR',1,6,1),
    (p_organization_id,'journal_entries','JE',1,6,1),
    (p_organization_id,'inventory_transactions','ITX',1,6,1);
end;
$function$;

revoke all on function private.seed_organization_configuration(uuid) from public, anon, authenticated;
grant usage on schema private to service_role;
grant execute on function private.seed_organization_configuration(uuid) to service_role;

-- Account codes are numeric, type-scoped, and constrained to their approved range.
create or replace function public.next_account_code(
  p_organization_id uuid,
  p_account_type text
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_sequence_type text;
begin
  v_sequence_type := case lower(btrim(coalesce(p_account_type,'')))
    when 'asset' then 'account_asset'
    when 'liability' then 'account_liability'
    when 'equity' then 'account_equity'
    when 'income' then 'account_income'
    when 'expense' then 'account_expense'
    else null
  end;

  if v_sequence_type is null then
    raise exception 'Unsupported account type' using errcode = '22023';
  end if;

  return public.next_document_number(p_organization_id, v_sequence_type);
end;
$function$;

revoke all on function public.next_account_code(uuid,text) from public, anon;
grant execute on function public.next_account_code(uuid,text) to authenticated, service_role;

-- Honor increment_by for all sequences and stop account-code allocation at
-- the upper bound of the approved account-type range.
create or replace function public.next_document_number(
  p_organization_id uuid,
  p_document_type text
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_prefix text;
  v_number bigint;
  v_padding smallint;
  v_increment bigint;
  v_max bigint;
begin
  if auth.uid() is null
     or not (private.is_org_member(p_organization_id) or private.is_org_creator(p_organization_id)) then
    raise exception 'Not authorized for this organization' using errcode = '42501';
  end if;
  if p_document_type is null or btrim(p_document_type) = '' then
    raise exception 'Document type is required' using errcode = '22023';
  end if;

  v_max := case p_document_type
    when 'account_asset' then 1999
    when 'account_liability' then 2999
    when 'account_equity' then 3999
    when 'account_income' then 4999
    when 'account_expense' then 5999
    else null
  end;

  update public.number_sequences
     set next_number = next_number + increment_by,
         updated_at = now()
   where organization_id = p_organization_id
     and document_type = p_document_type
     and (v_max is null or next_number <= v_max)
   returning prefix, next_number - increment_by, padding, increment_by
        into v_prefix, v_number, v_padding, v_increment;

  if not found then
    if v_max is not null then
      raise exception 'Account code range exhausted for type %', p_document_type
        using errcode = '22003';
    end if;
    raise exception 'Number sequence is not configured for document type %', p_document_type
      using errcode = 'P0002';
  end if;

  return v_prefix || case
    when length(v_number::text) >= v_padding then v_number::text
    else lpad(v_number::text, v_padding, '0')
  end;
end;
$function$;




-- ===== Replayed: 20261107143146_fix_expense_category_sequence_continuity.sql =====
-- Correct expense-category numbering: one continuous EXP sequence.


create or replace function private.allocate_document_number(
  p_organization_id uuid,
  p_document_type text
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_prefix text;
  v_number bigint;
  v_padding smallint;
  v_increment bigint;
  v_max bigint;
begin
  if p_document_type is null or btrim(p_document_type) = '' then
    raise exception 'Document type is required' using errcode = '22023';
  end if;
  v_max := case p_document_type
    when 'account_asset' then 1999 when 'account_liability' then 2999
    when 'account_equity' then 3999 when 'account_income' then 4999
    when 'account_expense' then 5999 else null end;
  update public.number_sequences
     set next_number = next_number + increment_by, updated_at = now()
   where organization_id = p_organization_id and document_type = p_document_type
     and (v_max is null or next_number <= v_max)
   returning prefix, next_number - increment_by, padding, increment_by
        into v_prefix, v_number, v_padding, v_increment;
  if not found then
    if v_max is not null then
      raise exception 'Account code range exhausted for type %', p_document_type using errcode = '22003';
    end if;
    raise exception 'Number sequence is not configured for document type %', p_document_type using errcode = 'P0002';
  end if;
  return v_prefix || case when length(v_number::text) >= v_padding then v_number::text
                          else lpad(v_number::text, v_padding, '0') end;
end;
$function$;

revoke all on function private.allocate_document_number(uuid,text) from public, anon, authenticated;
grant execute on function private.allocate_document_number(uuid,text) to service_role;

create or replace function public.next_document_number(p_organization_id uuid, p_document_type text)
returns text language plpgsql security definer set search_path = ''
as $function$
begin
  if auth.uid() is null or not (private.is_org_member(p_organization_id) or private.is_org_creator(p_organization_id)) then
    raise exception 'Not authorized for this organization' using errcode = '42501';
  end if;
  return private.allocate_document_number(p_organization_id, p_document_type);
end;
$function$;

create or replace function private.seed_organization_configuration(p_organization_id uuid)
returns void language plpgsql security definer set search_path = ''
as $function$
declare v_category record; v_category_code text;
begin
  if p_organization_id is null or not exists (select 1 from public.organizations o where o.id=p_organization_id) then
    raise exception 'Organization does not exist' using errcode = '23503';
  end if;
  if exists (select 1 from public.accounts a where a.organization_id=p_organization_id)
     or exists (select 1 from public.number_sequences n where n.organization_id=p_organization_id) then
    raise exception 'Organization configuration has already been seeded' using errcode = '23505';
  end if;

  insert into public.accounts
    (organization_id,code,account_name,account_type,parent_account_id,normal_balance,is_control_account,is_postable,status)
  select p_organization_id,t.code,t.account_name,t.account_type,parent.id,t.normal_balance,t.is_control_account,t.is_postable,'active'
    from private.default_account_templates t
    left join public.accounts parent on parent.organization_id=p_organization_id and parent.code=t.parent_code
   order by t.code;

  insert into public.number_sequences
    (organization_id,document_type,prefix,next_number,padding,increment_by)
  values
    (p_organization_id,'account_asset','',1150,4,10),
    (p_organization_id,'account_liability','',2120,4,10),
    (p_organization_id,'account_equity','',3210,4,10),
    (p_organization_id,'account_income','',4210,4,10),
    (p_organization_id,'account_expense','',5210,4,10),
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

  for v_category in select name from private.default_expense_category_templates order by code loop
    v_category_code := private.allocate_document_number(p_organization_id,'expense_categories');
    insert into public.expense_categories(organization_id,code,name,expense_account_id,status)
    select p_organization_id,v_category_code,v_category.name,a.id,true
      from public.accounts a where a.organization_id=p_organization_id and a.code='5200';
  end loop;
end;
$function$;

comment on column public.number_sequences.document_type is
  'Organization-scoped sequence key. expense_categories uses EXP001..., expenses uses EXP000001...';




-- ===== Replayed: 20261107143455_standardize_all_sequence_rules.sql =====
-- Standardize all ZERO ERP sequences on the same counter rule.
-- Every sequence uses the same allocator, advances by one, and applies its
-- configured prefix and padding. Only sequence configuration differs.


create or replace function private.seed_organization_configuration(p_organization_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_category record;
  v_category_code text;
begin
  if p_organization_id is null
     or not exists (select 1 from public.organizations o where o.id = p_organization_id) then
    raise exception 'Organization does not exist' using errcode = '23503';
  end if;
  if exists (select 1 from public.accounts a where a.organization_id = p_organization_id)
     or exists (select 1 from public.number_sequences n where n.organization_id = p_organization_id) then
    raise exception 'Organization configuration has already been seeded' using errcode = '23505';
  end if;

  insert into public.accounts
    (organization_id, code, account_name, account_type, parent_account_id,
     normal_balance, is_control_account, is_postable, status)
  select p_organization_id, t.code, t.account_name, t.account_type, parent.id,
         t.normal_balance, t.is_control_account, t.is_postable, 'active'
    from private.default_account_templates t
    left join public.accounts parent
      on parent.organization_id = p_organization_id and parent.code = t.parent_code
   order by t.code;

  -- All sequences advance by exactly one. Prefix and padding are configuration,
  -- not separate numbering logic. Account types retain their approved ranges.
  insert into public.number_sequences
    (organization_id, document_type, prefix, next_number, padding, increment_by)
  values
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

  for v_category in select name from private.default_expense_category_templates order by code loop
    v_category_code := private.allocate_document_number(p_organization_id, 'expense_categories');
    insert into public.expense_categories
      (organization_id, code, name, expense_account_id, status)
    select p_organization_id, v_category_code, v_category.name, a.id, true
      from public.accounts a where a.organization_id = p_organization_id and a.code = '5200';
  end loop;
end;
$function$;

alter table public.number_sequences
  add constraint number_sequences_increment_is_one check (increment_by = 1);

comment on column public.number_sequences.increment_by is
  'Standardized sequence rule: always 1. Each document_type has its own counter; prefix and padding are configurable.';




-- Production hardening: secure Data API grants and future object defaults.
REVOKE ALL ON SCHEMA public FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA public TO authenticated, service_role;
REVOKE CREATE ON SCHEMA public FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA private TO authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON TABLES FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated, service_role;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO authenticated, service_role;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.next_document_number(uuid,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.next_account_code(uuid,text) TO authenticated, service_role;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.is_org_member(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.is_org_creator(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.allocate_document_number(uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION private.seed_organization_configuration(uuid) TO service_role;

-- Seed account parents before children so the hierarchy is fully linked.
CREATE OR REPLACE FUNCTION private.seed_organization_configuration(p_organization_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
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
    (organization_id,code,account_name,account_type,parent_account_id,normal_balance,is_control_account,is_postable,status)
  SELECT p_organization_id,t.code,t.account_name,t.account_type,NULL,t.normal_balance,t.is_control_account,t.is_postable,'active'
    FROM private.default_account_templates t WHERE t.parent_code IS NULL ORDER BY t.code;

  INSERT INTO public.accounts
    (organization_id,code,account_name,account_type,parent_account_id,normal_balance,is_control_account,is_postable,status)
  SELECT p_organization_id,t.code,t.account_name,t.account_type,parent.id,t.normal_balance,t.is_control_account,t.is_postable,'active'
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

-- Atomic bootstrap of organization, creator membership, COA, categories and sequences.
CREATE OR REPLACE FUNCTION public.create_organization(
  p_name text, p_phone text DEFAULT NULL, p_email text DEFAULT NULL,
  p_address text DEFAULT NULL, p_tin text DEFAULT NULL, p_bin text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_user_id uuid := auth.uid(); v_organization_id uuid;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
  IF p_name IS NULL OR btrim(p_name)='' OR length(btrim(p_name))>200 THEN
    RAISE EXCEPTION 'A valid organization name is required' USING ERRCODE='22023';
  END IF;
  IF p_email IS NOT NULL AND length(btrim(p_email))>320 THEN
    RAISE EXCEPTION 'Organization email is too long' USING ERRCODE='22023';
  END IF;

  INSERT INTO public.organizations(name,phone,email,address,tin,bin,status,created_by)
  VALUES (btrim(p_name),NULLIF(btrim(p_phone),''),NULLIF(lower(btrim(p_email)), ''),
          NULLIF(btrim(p_address),''),NULLIF(btrim(p_tin),''),NULLIF(btrim(p_bin),''),'configuring',v_user_id)
  RETURNING id INTO v_organization_id;

  INSERT INTO public.organization_users(organization_id,user_id,status,created_by)
  VALUES (v_organization_id,v_user_id,'active',v_user_id);

  PERFORM private.seed_organization_configuration(v_organization_id);
  RETURN v_organization_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_organization(text,text,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_organization(text,text,text,text,text,text) TO authenticated, service_role;

-- Production catalog index for the self-referencing template foreign key.
CREATE INDEX IF NOT EXISTS default_account_templates_parent_code_idx
  ON private.default_account_templates(parent_code)
  WHERE parent_code IS NOT NULL;

-- Organizations must be provisioned only through create_organization(), which
-- atomically creates the creator membership, COA, categories and sequences.
-- Organization deletion is intentionally unavailable to application users;
-- use inactive status and a separately controlled retention/purge procedure.
DROP POLICY IF EXISTS organizations_insert_creator ON public.organizations;
DROP POLICY IF EXISTS organizations_delete_creator ON public.organizations;

-- Private seed catalogs are internal-only. RLS is enabled as defense in depth;
-- no client policies are defined, and SECURITY DEFINER seed functions execute
-- as the owning postgres role.
ALTER TABLE private.default_account_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.default_expense_category_templates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA private FROM PUBLIC, anon, authenticated;


-- ===== Production lifecycle, draft integrity, and controlled ledger writes =====

CREATE OR REPLACE FUNCTION private.enforce_master_data_write()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $function$
DECLARE v_org uuid; v_status text;
BEGIN
  IF current_user IN ('postgres','service_role') AND current_setting('zero_erp.allow_workflow',true)='on' THEN
    IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;
  v_org := CASE WHEN TG_OP='DELETE' THEN OLD.organization_id ELSE NEW.organization_id END;
  SELECT o.status INTO v_status FROM public.organizations o WHERE o.id=v_org;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Organization not found' USING ERRCODE='23503'; END IF;
  IF v_status='inactive' THEN RAISE EXCEPTION 'Inactive organizations are read-only' USING ERRCODE='23514'; END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$function$;

DO $function$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['accounts','contacts','products','units_of_measure','expense_categories'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I',t||'_organization_write_guard',t);
    EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION private.enforce_master_data_write()',t||'_organization_write_guard',t);
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION private.enforce_draft_document()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $function$
DECLARE
  v_row jsonb; v_old jsonb; v_org uuid; v_org_status text; v_entry_type text;
  v_field text;
BEGIN
  IF current_user IN ('postgres','service_role') AND current_setting('zero_erp.allow_workflow',true)='on' THEN
    IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;

  v_row := CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  v_org := (v_row->>'organization_id')::uuid;
  SELECT o.status INTO v_org_status FROM public.organizations o WHERE o.id=v_org;
  IF v_org_status IS NULL THEN RAISE EXCEPTION 'Organization not found' USING ERRCODE='23503'; END IF;
  IF v_org_status='inactive' THEN RAISE EXCEPTION 'Inactive organizations are read-only' USING ERRCODE='23514'; END IF;

  IF TG_TABLE_NAME='journal_entries' THEN
    v_entry_type := v_row->>'entry_type';
    IF v_org_status='configuring' AND v_entry_type IS DISTINCT FROM 'opening_balance' THEN
      RAISE EXCEPTION 'Only the opening journal may be created during organization setup' USING ERRCODE='23514';
    END IF;
    IF v_org_status='active' AND v_entry_type='opening_balance' THEN
      RAISE EXCEPTION 'Opening journal entries are locked after activation' USING ERRCODE='23514';
    END IF;
  ELSIF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Operational documents require an active organization' USING ERRCODE='23514';
  END IF;

  IF TG_OP='INSERT' THEN
    IF v_row->>'status' IS DISTINCT FROM 'draft' THEN
      RAISE EXCEPTION 'New documents must start in draft status' USING ERRCODE='23514';
    END IF;
    FOREACH v_field IN ARRAY ARRAY['confirmed_at','confirmed_by','posted_at','posted_by','voided_at','voided_by','void_reason','posted_journal_entry_id','reversal_of_id','reversal_journal_entry_id','reversed_at','reversed_by','reversal_reason'] LOOP
      IF v_row ? v_field AND v_row->v_field IS NOT NULL AND v_row->v_field <> 'null'::jsonb THEN
        RAISE EXCEPTION 'Workflow metadata is system-managed: %',v_field USING ERRCODE='23514';
      END IF;
    END LOOP;
    RETURN NEW;
  ELSIF TG_OP='DELETE' THEN
    IF to_jsonb(OLD)->>'status' IS DISTINCT FROM 'draft' THEN
      RAISE EXCEPTION 'Only draft documents can be deleted' USING ERRCODE='23514';
    END IF;
    RETURN OLD;
  ELSE
    v_old := to_jsonb(OLD);
    IF v_old->>'status' IS DISTINCT FROM 'draft' THEN
      RAISE EXCEPTION 'Non-draft documents are immutable outside workflow RPCs' USING ERRCODE='23514';
    END IF;
    IF v_row->>'status' IS DISTINCT FROM v_old->>'status' THEN
      RAISE EXCEPTION 'Document status can only change through workflow RPCs' USING ERRCODE='23514';
    END IF;
    IF TG_TABLE_NAME='journal_entries' AND v_row->>'entry_type' IS DISTINCT FROM v_old->>'entry_type' THEN
      RAISE EXCEPTION 'Journal entry type is immutable' USING ERRCODE='23514';
    END IF;
    FOREACH v_field IN ARRAY ARRAY['confirmed_at','confirmed_by','posted_at','posted_by','voided_at','voided_by','void_reason','posted_journal_entry_id','reversal_of_id','reversal_journal_entry_id','reversed_at','reversed_by','reversal_reason'] LOOP
      IF v_row ? v_field AND v_row->v_field IS DISTINCT FROM v_old->v_field THEN
        RAISE EXCEPTION 'Workflow metadata is system-managed: %',v_field USING ERRCODE='23514';
      END IF;
    END LOOP;
    RETURN NEW;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION private.enforce_draft_line()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $function$
DECLARE
  v_row jsonb; v_old jsonb; v_org uuid; v_parent uuid; v_old_parent uuid;
  v_status text; v_entry_type text; v_org_status text;
  v_table text:=TG_ARGV[0]; v_parent_column text:=TG_ARGV[1];
BEGIN
  IF current_user IN ('postgres','service_role') AND current_setting('zero_erp.allow_workflow',true)='on' THEN
    IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;
  v_row:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  v_org:=(v_row->>'organization_id')::uuid;
  v_parent:=(v_row->>v_parent_column)::uuid;
  SELECT o.status INTO v_org_status FROM public.organizations o WHERE o.id=v_org;
  IF v_org_status IS NULL THEN RAISE EXCEPTION 'Organization not found' USING ERRCODE='23503'; END IF;
  IF v_org_status='inactive' THEN RAISE EXCEPTION 'Inactive organizations are read-only' USING ERRCODE='23514'; END IF;

  EXECUTE format('SELECT status FROM public.%I WHERE organization_id=$1 AND id=$2',v_table)
    INTO v_status USING v_org,v_parent;
  IF v_status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'Document lines can only be changed while the parent document is draft' USING ERRCODE='23514';
  END IF;

  IF v_table='journal_entries' THEN
    EXECUTE 'SELECT entry_type FROM public.journal_entries WHERE organization_id=$1 AND id=$2'
      INTO v_entry_type USING v_org,v_parent;
    IF v_org_status='configuring' AND v_entry_type IS DISTINCT FROM 'opening_balance' THEN
      RAISE EXCEPTION 'Only opening journal lines may be changed during setup' USING ERRCODE='23514';
    END IF;
    IF v_org_status='active' AND v_entry_type='opening_balance' THEN
      RAISE EXCEPTION 'Opening journal lines are locked after activation' USING ERRCODE='23514';
    END IF;
  ELSIF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Operational document lines require an active organization' USING ERRCODE='23514';
  END IF;

  IF TG_OP='UPDATE' THEN
    v_old:=to_jsonb(OLD);
    IF v_old->>v_parent_column IS DISTINCT FROM v_row->>v_parent_column THEN
      v_old_parent:=(v_old->>v_parent_column)::uuid;
      EXECUTE format('SELECT status FROM public.%I WHERE organization_id=$1 AND id=$2',v_table)
        INTO v_status USING v_org,v_old_parent;
      IF v_status IS DISTINCT FROM 'draft' THEN
        RAISE EXCEPTION 'Lines belonging to a non-draft document cannot be moved' USING ERRCODE='23514';
      END IF;
      IF v_table='journal_entries' THEN
        EXECUTE 'SELECT entry_type FROM public.journal_entries WHERE organization_id=$1 AND id=$2'
          INTO v_entry_type USING v_org,v_old_parent;
        IF v_org_status='configuring' AND v_entry_type IS DISTINCT FROM 'opening_balance' THEN
          RAISE EXCEPTION 'Only opening journal lines may be moved during setup' USING ERRCODE='23514';
        END IF;
        IF v_org_status='active' AND v_entry_type='opening_balance' THEN
          RAISE EXCEPTION 'Opening journal lines cannot be moved after activation' USING ERRCODE='23514';
        END IF;
      END IF;
    END IF;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION private.enforce_inventory_workflow()
RETURNS trigger LANGUAGE plpgsql SET search_path = ''
AS $function$
BEGIN
  IF current_user IN ('postgres','service_role') AND current_setting('zero_erp.allow_workflow',true)='on' THEN
    IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;
  RAISE EXCEPTION 'Inventory ledger and balances can only be changed through controlled workflow RPCs'
    USING ERRCODE='42501';
END;
$function$;

DROP TRIGGER IF EXISTS inventory_transactions_workflow_guard ON public.inventory_transactions;
CREATE TRIGGER inventory_transactions_workflow_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.inventory_transactions
FOR EACH ROW EXECUTE FUNCTION private.enforce_inventory_workflow();

DROP TRIGGER IF EXISTS inventory_balances_workflow_guard ON public.inventory_balances;
CREATE TRIGGER inventory_balances_workflow_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.inventory_balances
FOR EACH ROW EXECUTE FUNCTION private.enforce_inventory_workflow();

CREATE OR REPLACE FUNCTION public.next_document_number(p_organization_id uuid, p_document_type text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE v_org_status text;
BEGIN
  IF auth.uid() IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  SELECT o.status INTO v_org_status FROM public.organizations o WHERE o.id=p_organization_id;
  IF v_org_status IS NULL OR v_org_status='inactive' THEN
    RAISE EXCEPTION 'Organization is unavailable for number allocation' USING ERRCODE='23514';
  END IF;
  IF p_document_type IN ('account_asset','account_liability','account_equity','account_income','account_expense')
     AND NOT private.is_org_creator(p_organization_id) THEN
    RAISE EXCEPTION 'Only the organization creator may allocate account codes' USING ERRCODE='42501';
  END IF;
  IF v_org_status='configuring' AND p_document_type NOT IN
    ('account_asset','account_liability','account_equity','account_income','account_expense','contacts','products','expense_categories','journal_entries') THEN
    RAISE EXCEPTION 'This document type is unavailable before organization activation' USING ERRCODE='23514';
  END IF;
  RETURN private.allocate_document_number(p_organization_id,p_document_type);
END;
$function$;



-- ===== Accounting constraints and atomic Setup Wizard completion =====

DO $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='account_transactions_positive_line_amount') THEN
    ALTER TABLE public.account_transactions ADD CONSTRAINT account_transactions_positive_line_amount
      CHECK (debit > 0 OR credit > 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='account_transactions_positive_line_number') THEN
    ALTER TABLE public.account_transactions ADD CONSTRAINT account_transactions_positive_line_number
      CHECK (line_number > 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='accounts_valid_type_and_normal_balance') THEN
    ALTER TABLE public.accounts ADD CONSTRAINT accounts_valid_type_and_normal_balance CHECK (
      (account_type='asset' AND normal_balance='debit') OR
      (account_type='liability' AND normal_balance='credit') OR
      (account_type='equity' AND normal_balance='credit') OR
      (account_type='income' AND normal_balance='credit') OR
      (account_type='expense' AND normal_balance='debit')
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='accounts_code_range_by_type') THEN
    ALTER TABLE public.accounts ADD CONSTRAINT accounts_code_range_by_type CHECK (
      length(code)=4 AND code ~ '^[0-9]{4}' AND
      ((account_type='asset' AND code BETWEEN '1000' AND '1999') OR
       (account_type='liability' AND code BETWEEN '2000' AND '2999') OR
       (account_type='equity' AND code BETWEEN '3000' AND '3999') OR
       (account_type='income' AND code BETWEEN '4000' AND '4999') OR
       (account_type='expense' AND code BETWEEN '5000' AND '5999'))
    );
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='organizations_valid_status') THEN
    ALTER TABLE public.organizations ADD CONSTRAINT organizations_valid_status
      CHECK (status IN ('configuring','active','inactive'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='accounts_valid_status') THEN
    ALTER TABLE public.accounts ADD CONSTRAINT accounts_valid_status CHECK (status IN ('active','inactive'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='contacts_valid_status') THEN
    ALTER TABLE public.contacts ADD CONSTRAINT contacts_valid_status CHECK (status IN ('active','inactive'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='units_valid_status') THEN
    ALTER TABLE public.units_of_measure ADD CONSTRAINT units_valid_status CHECK (status IN ('active','inactive'));
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.complete_organization_setup(
  p_organization_id uuid,
  p_inventory_items jsonb DEFAULT '[]'::jsonb,
  p_confirm_zero_inventory boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_org_status text;
  v_journal_id uuid;
  v_journal_code text;
  v_entry_date date;
  v_inventory_account_id uuid;
  v_debit numeric(20,4);
  v_credit numeric(20,4);
  v_inventory_debit numeric(20,4);
  v_inventory_credit numeric(20,4);
  v_inventory_total numeric(20,4);
  v_line_count bigint;
  v_bad_lines bigint;
  v_item_count bigint;
  v_distinct_products bigint;
  v_item record;
  v_total_value numeric(20,4);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';
  END IF;
  IF NOT private.is_org_creator(p_organization_id) THEN
    RAISE EXCEPTION 'Only the organization creator can complete setup' USING ERRCODE='42501';
  END IF;
  IF p_inventory_items IS NULL OR jsonb_typeof(p_inventory_items) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Inventory opening items must be a JSON array' USING ERRCODE='22023';
  END IF;

  SELECT o.status INTO v_org_status
    FROM public.organizations o
   WHERE o.id=p_organization_id
   FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'configuring' THEN
    RAISE EXCEPTION 'Organization is not in configuring state' USING ERRCODE='23514';
  END IF;

  SELECT j.id,j.code,j.entry_date
    INTO v_journal_id,v_journal_code,v_entry_date
    FROM public.journal_entries j
   WHERE j.organization_id=p_organization_id
     AND j.entry_type='opening_balance'
   FOR UPDATE;
  IF v_journal_id IS NULL THEN
    RAISE EXCEPTION 'An opening balance journal entry is required' USING ERRCODE='23514';
  END IF;
  IF EXISTS (SELECT 1 FROM public.journal_entries j WHERE j.id=v_journal_id AND j.status<>'draft') THEN
    RAISE EXCEPTION 'Opening balance journal must be draft before setup completion' USING ERRCODE='23514';
  END IF;

  SELECT count(*),COALESCE(sum(t.debit),0),COALESCE(sum(t.credit),0)
    INTO v_line_count,v_debit,v_credit
    FROM public.account_transactions t
   WHERE t.organization_id=p_organization_id AND t.journal_entry_id=v_journal_id;
  IF v_line_count < 2 OR v_debit <= 0 OR round(v_debit,4)<>round(v_credit,4) THEN
    RAISE EXCEPTION 'Opening journal must contain at least two lines and be balanced' USING ERRCODE='23514';
  END IF;

  SELECT count(*) INTO v_bad_lines
    FROM public.account_transactions t
    JOIN public.accounts a ON a.organization_id=t.organization_id AND a.id=t.account_id
   WHERE t.organization_id=p_organization_id AND t.journal_entry_id=v_journal_id
     AND (a.status<>'active' OR NOT a.is_postable
       OR (a.code IN ('1130','2110') AND t.contact_id IS NULL));
  IF v_bad_lines>0 THEN
    RAISE EXCEPTION 'Opening journal contains inactive/non-postable accounts or control-account lines without contacts' USING ERRCODE='23514';
  END IF;

  SELECT a.id INTO v_inventory_account_id
    FROM public.accounts a
   WHERE a.organization_id=p_organization_id AND a.code='1140'
     AND a.account_type='asset' AND a.is_postable AND a.status='active';
  IF v_inventory_account_id IS NULL THEN
    RAISE EXCEPTION 'Inventory Asset account 1140 is missing or not postable' USING ERRCODE='23514';
  END IF;

  SELECT count(*),count(DISTINCT x.product_id),
         COALESCE(sum(round(x.quantity*x.unit_cost,4)),0)
    INTO v_item_count,v_distinct_products,v_inventory_total
    FROM jsonb_to_recordset(p_inventory_items) AS x(product_id uuid,quantity numeric,unit_cost numeric);
  IF v_item_count<>v_distinct_products THEN
    RAISE EXCEPTION 'Inventory opening items contain duplicate products' USING ERRCODE='23514';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_to_recordset(p_inventory_items) AS x(product_id uuid,quantity numeric,unit_cost numeric)
    WHERE x.product_id IS NULL OR x.quantity IS NULL OR x.unit_cost IS NULL
       OR x.quantity<=0 OR x.unit_cost<0
  ) THEN
    RAISE EXCEPTION 'Each inventory item requires a product, positive quantity and nonnegative unit cost' USING ERRCODE='23514';
  END IF;
  IF v_item_count=0 AND NOT p_confirm_zero_inventory THEN
    RAISE EXCEPTION 'Explicit zero-inventory confirmation is required' USING ERRCODE='23514';
  END IF;
  IF EXISTS (
    SELECT 1
      FROM jsonb_to_recordset(p_inventory_items) AS x(product_id uuid,quantity numeric,unit_cost numeric)
      LEFT JOIN public.products p ON p.organization_id=p_organization_id AND p.id=x.product_id
     WHERE p.id IS NULL OR p.status IS NOT TRUE OR p.inventory_account_id IS DISTINCT FROM v_inventory_account_id
  ) THEN
    RAISE EXCEPTION 'Inventory items must reference active products mapped to Inventory Asset account 1140' USING ERRCODE='23514';
  END IF;

  SELECT COALESCE(sum(t.debit),0),COALESCE(sum(t.credit),0)
    INTO v_inventory_debit,v_inventory_credit
    FROM public.account_transactions t
   WHERE t.organization_id=p_organization_id AND t.journal_entry_id=v_journal_id
     AND t.account_id=v_inventory_account_id;
  IF round(v_inventory_debit,4)<>v_inventory_total OR v_inventory_credit<>0 THEN
    RAISE EXCEPTION 'Inventory Asset debit must equal the total opening inventory value' USING ERRCODE='23514';
  END IF;

  IF EXISTS (SELECT 1 FROM public.inventory_transactions WHERE organization_id=p_organization_id)
     OR EXISTS (SELECT 1 FROM public.inventory_balances WHERE organization_id=p_organization_id) THEN
    RAISE EXCEPTION 'Opening inventory ledger already exists; setup cannot be completed twice' USING ERRCODE='23505';
  END IF;

  -- Only this trusted SECURITY DEFINER transaction can pass workflow triggers.
  PERFORM set_config('zero_erp.allow_workflow','on',true);

  IF v_journal_code IS NULL THEN
    v_journal_code := private.allocate_document_number(p_organization_id,'journal_entries');
  END IF;

  FOR v_item IN
    SELECT x.product_id,x.quantity,x.unit_cost
      FROM jsonb_to_recordset(p_inventory_items) AS x(product_id uuid,quantity numeric,unit_cost numeric)
     ORDER BY x.product_id
  LOOP
    v_total_value := round(v_item.quantity*v_item.unit_cost,4);
    INSERT INTO public.inventory_transactions
      (organization_id,code,product_id,transaction_date,transaction_type,direction,
       quantity,unit_cost,total_value,reference_type,reference_id,unit_cost_before,
       average_cost_after,created_by)
    VALUES
      (p_organization_id,private.allocate_document_number(p_organization_id,'inventory_transactions'),
       v_item.product_id,v_entry_date,'opening','in',v_item.quantity,v_item.unit_cost,
       v_total_value,'journal_entry',v_journal_id,NULL,v_item.unit_cost,v_user_id);

    INSERT INTO public.inventory_balances
      (organization_id,product_id,quantity,average_cost,inventory_value,created_by,updated_by,updated_at)
    VALUES
      (p_organization_id,v_item.product_id,v_item.quantity,v_item.unit_cost,v_total_value,
       v_user_id,v_user_id,now());
  END LOOP;

  UPDATE public.journal_entries
     SET code=v_journal_code,status='posted',confirmed_at=now(),confirmed_by=v_user_id,
         posted_at=now(),posted_by=v_user_id,updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=v_journal_id AND status='draft';
  IF NOT FOUND THEN RAISE EXCEPTION 'Opening journal could not be posted' USING ERRCODE='23514'; END IF;

  UPDATE public.organizations
     SET status='active',updated_by=v_user_id,updated_at=now()
   WHERE id=p_organization_id AND status='configuring';
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization activation failed' USING ERRCODE='23514'; END IF;

  RETURN v_journal_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.complete_organization_setup(uuid,jsonb,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.complete_organization_setup(uuid,jsonb,boolean) TO authenticated,service_role;



-- ===== Controlled journal posting and reversal RPCs =====

CREATE UNIQUE INDEX IF NOT EXISTS journal_entries_one_reversal_uidx
  ON public.journal_entries(organization_id,reversal_of_id)
  WHERE reversal_of_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.post_journal_entry(
  p_organization_id uuid,
  p_journal_entry_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid:=auth.uid();
  v_org_status text;
  v_entry public.journal_entries%ROWTYPE;
  v_original public.journal_entries%ROWTYPE;
  v_line_count bigint;
  v_debit numeric(20,4);
  v_credit numeric(20,4);
  v_invalid bigint;
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  SELECT o.status INTO v_org_status FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Journal posting requires an active organization' USING ERRCODE='23514';
  END IF;

  SELECT j.* INTO v_entry FROM public.journal_entries j
   WHERE j.organization_id=p_organization_id AND j.id=p_journal_entry_id
   FOR UPDATE;
  IF NOT FOUND OR v_entry.status<>'draft' THEN
    RAISE EXCEPTION 'Journal entry not found or not draft' USING ERRCODE='23514';
  END IF;
  IF v_entry.entry_type='opening_balance' THEN
    RAISE EXCEPTION 'Opening journal entries can only be posted by setup completion' USING ERRCODE='23514';
  END IF;
  IF v_entry.reversal_of_id IS NOT NULL THEN
    IF v_entry.entry_type<>'reversal' THEN
      RAISE EXCEPTION 'Invalid reversal journal metadata' USING ERRCODE='23514';
    END IF;
    SELECT j.* INTO v_original
      FROM public.journal_entries j
     WHERE j.organization_id=p_organization_id AND j.id=v_entry.reversal_of_id
     FOR UPDATE;
    IF NOT FOUND OR v_original.status<>'posted'
       OR v_original.reversal_of_id IS NOT NULL
       OR v_original.reversal_journal_entry_id IS NOT NULL THEN
      RAISE EXCEPTION 'Reversal must reference an unreversed posted original journal' USING ERRCODE='23514';
    END IF;
    SELECT count(*) INTO v_invalid
      FROM (
        SELECT COALESCE(o.account_id,r.account_id) AS account_id,
               COALESCE(o.contact_id,r.contact_id) AS contact_id,
               COALESCE(o.debit,0) AS original_debit,
               COALESCE(o.credit,0) AS original_credit,
               COALESCE(r.debit,0) AS reversal_debit,
               COALESCE(r.credit,0) AS reversal_credit
          FROM (
            SELECT t.account_id,t.contact_id,sum(t.debit) AS debit,sum(t.credit) AS credit
              FROM public.account_transactions t
             WHERE t.organization_id=p_organization_id AND t.journal_entry_id=v_original.id
             GROUP BY t.account_id,t.contact_id
          ) o
          FULL JOIN (
            SELECT t.account_id,t.contact_id,sum(t.debit) AS debit,sum(t.credit) AS credit
              FROM public.account_transactions t
             WHERE t.organization_id=p_organization_id AND t.journal_entry_id=p_journal_entry_id
             GROUP BY t.account_id,t.contact_id
          ) r ON r.account_id=o.account_id AND r.contact_id IS NOT DISTINCT FROM o.contact_id
      ) x
     WHERE x.original_debit<>x.reversal_credit
        OR x.original_credit<>x.reversal_debit;
    IF v_invalid>0 THEN
      RAISE EXCEPTION 'Reversal lines must exactly invert the original journal by account and contact' USING ERRCODE='23514';
    END IF;
  ELSIF v_entry.entry_type='reversal' THEN
    RAISE EXCEPTION 'Reversal journal must reference an original journal' USING ERRCODE='23514';
  END IF;

  SELECT count(*),COALESCE(sum(t.debit),0),COALESCE(sum(t.credit),0)
    INTO v_line_count,v_debit,v_credit
    FROM public.account_transactions t
   WHERE t.organization_id=p_organization_id AND t.journal_entry_id=p_journal_entry_id;
  IF v_line_count<2 OR v_debit<=0 OR round(v_debit,4)<>round(v_credit,4) THEN
    RAISE EXCEPTION 'Journal entry must contain at least two lines and be balanced' USING ERRCODE='23514';
  END IF;

  SELECT count(*) INTO v_invalid
    FROM public.account_transactions t
    JOIN public.accounts a ON a.organization_id=t.organization_id AND a.id=t.account_id
   WHERE t.organization_id=p_organization_id AND t.journal_entry_id=p_journal_entry_id
     AND (a.status<>'active' OR NOT a.is_postable
       OR (a.code IN ('1130','2110') AND t.contact_id IS NULL));
  IF v_invalid>0 THEN
    RAISE EXCEPTION 'Journal entry contains inactive/non-postable accounts or missing control-account contacts' USING ERRCODE='23514';
  END IF;

  PERFORM set_config('zero_erp.allow_workflow','on',true);
  UPDATE public.journal_entries
     SET code=COALESCE(code,private.allocate_document_number(p_organization_id,'journal_entries')),
         status='posted',confirmed_at=COALESCE(confirmed_at,now()),
         confirmed_by=COALESCE(confirmed_by,v_user_id),posted_at=now(),
         posted_by=v_user_id,updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_journal_entry_id AND status='draft';
  IF NOT FOUND THEN RAISE EXCEPTION 'Journal posting failed' USING ERRCODE='23514'; END IF;
  RETURN p_journal_entry_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.reverse_journal_entry(
  p_organization_id uuid,
  p_journal_entry_id uuid,
  p_reversal_date date,
  p_reason text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid:=auth.uid();
  v_org_status text;
  v_original public.journal_entries%ROWTYPE;
  v_reversal_id uuid:=gen_random_uuid();
  v_reversal_code text;
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  IF p_reversal_date IS NULL OR p_reason IS NULL OR btrim(p_reason)='' OR length(btrim(p_reason))>500 THEN
    RAISE EXCEPTION 'A reversal date and reason of 1-500 characters are required' USING ERRCODE='22023';
  END IF;
  SELECT o.status INTO v_org_status FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Journal reversal requires an active organization' USING ERRCODE='23514';
  END IF;

  SELECT j.* INTO v_original FROM public.journal_entries j
   WHERE j.organization_id=p_organization_id AND j.id=p_journal_entry_id
   FOR UPDATE;
  IF NOT FOUND OR v_original.status<>'posted' OR v_original.reversal_of_id IS NOT NULL
     OR v_original.reversal_journal_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Only an unreversed posted journal entry can be reversed' USING ERRCODE='23514';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.account_transactions t
                  WHERE t.organization_id=p_organization_id AND t.journal_entry_id=p_journal_entry_id) THEN
    RAISE EXCEPTION 'Journal entry has no lines to reverse' USING ERRCODE='23514';
  END IF;

  PERFORM set_config('zero_erp.allow_workflow','on',true);
  v_reversal_code:=private.allocate_document_number(p_organization_id,'journal_entries');
  INSERT INTO public.journal_entries
    (id,organization_id,code,entry_date,entry_type,status,reference_type,reference_id,
     description,reversal_of_id,reversal_reason,created_by,created_at,updated_by,updated_at)
  VALUES
    (v_reversal_id,p_organization_id,v_reversal_code,p_reversal_date,'reversal','draft',
     'journal_entry',v_original.id,
     'Reversal of '||COALESCE(v_original.code,v_original.id::text),
     v_original.id,btrim(p_reason),v_user_id,now(),v_user_id,now());

  INSERT INTO public.account_transactions
    (organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by)
  SELECT t.organization_id,v_reversal_id,t.account_id,
         row_number() OVER (ORDER BY t.line_number,t.id)::integer,
         t.description,t.credit,t.debit,t.contact_id,v_user_id,v_user_id
    FROM public.account_transactions t
   WHERE t.organization_id=p_organization_id AND t.journal_entry_id=p_journal_entry_id;

  PERFORM public.post_journal_entry(p_organization_id,v_reversal_id);

  UPDATE public.journal_entries
     SET reversal_journal_entry_id=v_reversal_id,reversed_at=now(),
         reversed_by=v_user_id,reversal_reason=btrim(p_reason),
         updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_journal_entry_id;
  RETURN v_reversal_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.post_journal_entry(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.post_journal_entry(uuid,uuid) TO authenticated,service_role;
REVOKE ALL ON FUNCTION public.reverse_journal_entry(uuid,uuid,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reverse_journal_entry(uuid,uuid,date,text) TO authenticated,service_role;



-- ===== Expense posting workflow =====

CREATE OR REPLACE FUNCTION public.post_expense(
  p_organization_id uuid,
  p_expense_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid:=auth.uid();
  v_org_status text;
  v_expense public.expenses%ROWTYPE;
  v_expense_account uuid;
  v_credit_account uuid;
  v_credit_code text;
  v_credit_type text;
  v_journal_id uuid:=gen_random_uuid();
  v_journal_code text;
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  SELECT o.status INTO v_org_status FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Expense posting requires an active organization' USING ERRCODE='23514';
  END IF;

  SELECT e.* INTO v_expense FROM public.expenses e
   WHERE e.organization_id=p_organization_id AND e.id=p_expense_id
   FOR UPDATE;
  IF NOT FOUND OR v_expense.status<>'draft' OR v_expense.amount<=0 THEN
    RAISE EXCEPTION 'Expense not found, not draft, or has invalid amount' USING ERRCODE='23514';
  END IF;
  IF v_expense.posted_journal_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Expense has already been posted' USING ERRCODE='23505';
  END IF;

  SELECT c.expense_account_id INTO v_expense_account
    FROM public.expense_categories c
   WHERE c.organization_id=p_organization_id AND c.id=v_expense.expense_category_id
     AND c.status IS TRUE;
  IF v_expense_account IS NULL THEN
    RAISE EXCEPTION 'Expense category is inactive or has no mapped expense account' USING ERRCODE='23514';
  END IF;

  IF v_expense.payable_account_id IS NOT NULL THEN
    v_credit_account:=v_expense.payable_account_id;
  ELSE
    SELECT a.id INTO v_credit_account FROM public.accounts a
     WHERE a.organization_id=p_organization_id AND a.code='1110';
  END IF;

  SELECT a.code,a.account_type INTO v_credit_code,v_credit_type FROM public.accounts a
   WHERE a.organization_id=p_organization_id AND a.id=v_credit_account
     AND a.status='active' AND a.is_postable;
  IF v_credit_code IS NULL THEN
    RAISE EXCEPTION 'Expense settlement account is missing, inactive or not postable' USING ERRCODE='23514';
  END IF;
  IF v_credit_type NOT IN ('asset','liability') THEN
    RAISE EXCEPTION 'Expense settlement account must be an asset (cash/bank) or liability (payable)' USING ERRCODE='23514';
  END IF;
  IF v_credit_code='2110' AND v_expense.contact_id IS NULL THEN
    RAISE EXCEPTION 'Supplier/contact is required when expense is credited to Accounts Payable' USING ERRCODE='23514';
  END IF;

  SELECT a.id INTO v_expense_account FROM public.accounts a
   WHERE a.organization_id=p_organization_id AND a.id=v_expense_account
     AND a.account_type='expense' AND a.status='active' AND a.is_postable;
  IF v_expense_account IS NULL THEN
    RAISE EXCEPTION 'Expense account is inactive or not postable' USING ERRCODE='23514';
  END IF;

  PERFORM set_config('zero_erp.allow_workflow','on',true);
  v_journal_code:=private.allocate_document_number(p_organization_id,'journal_entries');
  INSERT INTO public.journal_entries
    (id,organization_id,code,entry_date,entry_type,status,reference_type,reference_id,description,created_by,created_at,updated_by,updated_at)
  VALUES
    (v_journal_id,p_organization_id,v_journal_code,v_expense.expense_date,'expense','draft',
     'expense',p_expense_id,COALESCE(v_expense.description,'Expense '||COALESCE(v_expense.code,p_expense_id::text)),
     v_user_id,now(),v_user_id,now());

  INSERT INTO public.account_transactions
    (organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by)
  VALUES
    (p_organization_id,v_journal_id,v_expense_account,1,v_expense.description,v_expense.amount,0,NULL,v_user_id,v_user_id),
    (p_organization_id,v_journal_id,v_credit_account,2,v_expense.description,0,v_expense.amount,v_expense.contact_id,v_user_id,v_user_id);

  PERFORM public.post_journal_entry(p_organization_id,v_journal_id);

  UPDATE public.expenses
     SET code=COALESCE(code,private.allocate_document_number(p_organization_id,'expenses')),
         status='posted',confirmed_at=now(),confirmed_by=v_user_id,
         posted_by=v_user_id,posted_journal_entry_id=v_journal_id,
         updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_expense_id AND status='draft';
  IF NOT FOUND THEN RAISE EXCEPTION 'Expense posting failed' USING ERRCODE='23514'; END IF;
  RETURN v_journal_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.post_expense(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.post_expense(uuid,uuid) TO authenticated,service_role;


COMMIT;
