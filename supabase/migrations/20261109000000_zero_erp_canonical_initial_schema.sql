-- ZERO ERP canonical initial database schema
-- Fresh, empty dedicated ZERO ERP Supabase project only.
-- Reconcile migration history and compare schemas before any existing-database deployment.
-- Supabase-managed auth/storage schemas and environment secrets are not included.
--
-- EXECUTION ORDER
-- 01-02  Core tables, constraints and tenant-safe relationships
-- 03-04  RLS policies and private security helpers
-- 05-09  Audit, numbering, defaults, provisioning and workflow guardrails
-- 10-11  Sequence permissions and organization tenant scope
-- 12-18  Purchase, sales, returns, inventory, payments and expenses
-- 19-21  Opening balances, control accounts and immutability
-- 22-24  Reversals, private implementations and RPC security facades
-- 25     Return-source integrity
--
-- Ordered function revisions are retained where later definitions harden earlier behavior.

-- ZERO ERP canonical initial database schema (squashed migration)
-- Intended for a NEW, EMPTY dedicated ZERO ERP Supabase database only.
-- Do not apply to an existing database or production without migration-history
-- reconciliation and a schema diff. Does not include Supabase-managed auth/storage
-- schemas or environment-specific secrets.

-- 01. CORE TABLES AND INITIAL SCHEMA

BEGIN;

-- 01.1. Core table definitions

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

-- 02. CONSTRAINTS AND TENANT-SAFE RELATIONSHIPS

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

-- 03. ROW-LEVEL SECURITY POLICIES

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

-- 04. PRIVATE SECURITY HELPERS

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated, service_role;
ALTER FUNCTION public.is_org_member(uuid) SET SCHEMA private;
ALTER FUNCTION public.is_org_creator(uuid) SET SCHEMA private;
GRANT EXECUTE ON FUNCTION private.is_org_member(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.is_org_creator(uuid) TO authenticated, service_role;

-- 05. AUDIT FIELDS, NUMBERING AND ORGANIZATION PROVISIONING

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

-- 05.1. Document-number overflow protection
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

-- 06. FOREIGN-KEY INDEXES AND POLICY TUNING

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

-- 07. AUDIT METADATA PROTECTION
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

-- 08. WORKFLOW AND DRAFT-INTEGRITY GUARDRAILS

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

-- 08.1. Parent-document move protection
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

-- 08.2. Opening-journal move protection
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

-- 09. ACCOUNTING DEFAULTS, SEQUENCES AND ORGANIZATION SETUP

alter table public.number_sequences
  add column increment_by bigint not null default 1;
alter table public.number_sequences
  add constraint number_sequences_increment_positive check (increment_by > 0);

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

-- 09.1. Expense-category sequence continuity

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

-- 09.2. Standardized sequence allocation

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

CREATE INDEX IF NOT EXISTS default_account_templates_parent_code_idx
  ON private.default_account_templates(parent_code)
  WHERE parent_code IS NOT NULL;

DROP POLICY IF EXISTS organizations_insert_creator ON public.organizations;
DROP POLICY IF EXISTS organizations_delete_creator ON public.organizations;

ALTER TABLE private.default_account_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.default_expense_category_templates ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA private FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA private FROM PUBLIC, anon, authenticated;

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
    FROM jsonb_to_recordset(p_inventory_items) AS x(product_id uuid,quantity numeric(20,6),unit_cost numeric(20,6));
  IF v_item_count<>v_distinct_products THEN
    RAISE EXCEPTION 'Inventory opening items contain duplicate products' USING ERRCODE='23514';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_to_recordset(p_inventory_items) AS x(product_id uuid,quantity numeric(20,6),unit_cost numeric(20,6))
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
      FROM jsonb_to_recordset(p_inventory_items) AS x(product_id uuid,quantity numeric(20,6),unit_cost numeric(20,6))
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
      FROM jsonb_to_recordset(p_inventory_items) AS x(product_id uuid,quantity numeric(20,6),unit_cost numeric(20,6))
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
  v_item_count bigint;
  v_distinct_products bigint;
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

-- 10. SEQUENCE RPC PERMISSIONS

BEGIN;

REVOKE ALL ON FUNCTION public.next_document_number(uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.next_document_number(uuid,text) TO service_role;

COMMIT;

-- 11. ORGANIZATION OWNERSHIP AND TENANT SCOPE

BEGIN;

ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS owner_user_id uuid;

UPDATE public.organizations
   SET owner_user_id = created_by
 WHERE owner_user_id IS NULL
   AND created_by IS NOT NULL;

DO $migration$
BEGIN
  IF EXISTS (SELECT 1 FROM public.organizations WHERE owner_user_id IS NULL) THEN
    RAISE EXCEPTION 'Cannot assign organization ownership: one or more organizations have no created_by user. Backfill owner_user_id explicitly before continuing.';
  END IF;
END;
$migration$;

ALTER TABLE public.organizations
  ALTER COLUMN owner_user_id SET NOT NULL;

DO $migration$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid='public.organizations'::regclass
       AND conname='organizations_owner_user_fk'
  ) THEN
    ALTER TABLE public.organizations
      ADD CONSTRAINT organizations_owner_user_fk
      FOREIGN KEY (owner_user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;
  END IF;
END;
$migration$;

CREATE INDEX IF NOT EXISTS organizations_owner_user_id_idx
  ON public.organizations(owner_user_id);

CREATE OR REPLACE FUNCTION private.is_org_creator(p_organization_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM public.organizations o
     WHERE o.id=p_organization_id
       AND o.owner_user_id=auth.uid()
  );
$function$;

REVOKE ALL ON FUNCTION private.is_org_creator(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_org_creator(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_organization(
  p_name text,
  p_phone text DEFAULT NULL,
  p_email text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_tin text DEFAULT NULL,
  p_bin text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_organization_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501';
  END IF;
  IF p_name IS NULL OR btrim(p_name)='' OR length(btrim(p_name))>200 THEN
    RAISE EXCEPTION 'A valid organization name is required' USING ERRCODE='22023';
  END IF;
  IF p_email IS NOT NULL AND length(btrim(p_email))>320 THEN
    RAISE EXCEPTION 'Organization email is too long' USING ERRCODE='22023';
  END IF;

  INSERT INTO public.organizations(
    name,phone,email,address,tin,bin,status,created_by,owner_user_id
  )
  VALUES (
    btrim(p_name),NULLIF(btrim(p_phone),''),NULLIF(lower(btrim(p_email)), ''),
    NULLIF(btrim(p_address),''),NULLIF(btrim(p_tin),''),NULLIF(btrim(p_bin),''),
    'configuring',v_user_id,v_user_id
  )
  RETURNING id INTO v_organization_id;

  INSERT INTO public.organization_users(organization_id,user_id,status,created_by)
  VALUES (v_organization_id,v_user_id,'active',v_user_id);

  PERFORM private.seed_organization_configuration(v_organization_id);
  RETURN v_organization_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_organization(text,text,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_organization(text,text,text,text,text,text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION private.enforce_organization_scope_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
    RAISE EXCEPTION 'organization_id is immutable; records cannot be transferred between organizations'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$function$;

DO $migration$
DECLARE
  v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY[
    'organization_users','accounts','units_of_measure','contacts','products',
    'expense_categories','number_sequences','journal_entries','account_transactions',
    'inventory_transactions','inventory_balances','purchase','purchase_items',
    'purchase_returns','purchase_return_items','sales','sales_items','sales_returns',
    'sales_return_items','expenses','payments','payment_allocations'
  ] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I',
      v_table||'_organization_scope_immutable',v_table);
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE OF organization_id ON public.%I FOR EACH ROW EXECUTE FUNCTION private.enforce_organization_scope_immutable()',
      v_table||'_organization_scope_immutable',v_table
    );
  END LOOP;
END;
$migration$;

CREATE OR REPLACE FUNCTION private.enforce_organization_owner_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $function$
BEGIN
  IF NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id THEN
    RAISE EXCEPTION 'Organization ownership can only change through a dedicated ownership-transfer workflow'
      USING ERRCODE='23514';
  END IF;
  IF NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION 'Organization created_by is immutable audit metadata'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS organizations_owner_immutable ON public.organizations;
CREATE TRIGGER organizations_owner_immutable
BEFORE UPDATE OF owner_user_id,created_by ON public.organizations
FOR EACH ROW EXECUTE FUNCTION private.enforce_organization_owner_immutable();

REVOKE ALL ON FUNCTION private.enforce_organization_scope_immutable() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.enforce_organization_owner_immutable() FROM PUBLIC, anon, authenticated;

COMMIT;

-- 12. PURCHASE AND SALES POSTING

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

-- 13. SOURCE-DOCUMENT REVERSAL GUARD

BEGIN;

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

  IF v_original.reference_type IS NOT NULL OR v_original.reference_id IS NOT NULL THEN
    RAISE EXCEPTION 'Referenced journals must be reversed through their source-document workflow'
      USING ERRCODE='23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.account_transactions t
     WHERE t.organization_id=p_organization_id AND t.journal_entry_id=p_journal_entry_id
  ) THEN
    RAISE EXCEPTION 'Journal entry has no lines to reverse' USING ERRCODE='23514';
  END IF;

  PERFORM set_config('zero_erp.allow_workflow','on',true);
  v_reversal_code:=private.allocate_document_number(p_organization_id,'journal_entries');
  INSERT INTO public.journal_entries(
    id,organization_id,code,entry_date,entry_type,status,reference_type,reference_id,
    description,reversal_of_id,reversal_reason,created_by,created_at,updated_by,updated_at
  )
  VALUES(
    v_reversal_id,p_organization_id,v_reversal_code,p_reversal_date,'reversal','draft',
    'journal_entry',v_original.id,
    'Reversal of '||COALESCE(v_original.code,v_original.id::text),
    v_original.id,btrim(p_reason),v_user_id,now(),v_user_id,now()
  );

  INSERT INTO public.account_transactions(
    organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by
  )
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

REVOKE ALL ON FUNCTION public.reverse_journal_entry(uuid,uuid,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reverse_journal_entry(uuid,uuid,date,text) TO authenticated,service_role;

COMMIT;

-- 14. DECIMAL PRECISION AND DISCOUNT ALLOCATION

BEGIN;
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
    FROM jsonb_to_recordset(p_inventory_items) AS x(product_id uuid,quantity numeric(20,6),unit_cost numeric(20,6));
  IF v_item_count<>v_distinct_products THEN
    RAISE EXCEPTION 'Inventory opening items contain duplicate products' USING ERRCODE='23514';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_to_recordset(p_inventory_items) AS x(product_id uuid,quantity numeric(20,6),unit_cost numeric(20,6))
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
      FROM jsonb_to_recordset(p_inventory_items) AS x(product_id uuid,quantity numeric(20,6),unit_cost numeric(20,6))
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
      FROM jsonb_to_recordset(p_inventory_items) AS x(product_id uuid,quantity numeric(20,6),unit_cost numeric(20,6))
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
CREATE OR REPLACE FUNCTION private.purchase_net_lines(p_organization_id uuid,p_purchase_id uuid)
RETURNS TABLE(item_id uuid,product_id uuid,quantity numeric,unit_cost numeric,line_total numeric,net_line_total numeric)
LANGUAGE sql STABLE SET search_path = ''
AS $function$
WITH header AS (
 SELECT p.subtotal,p.discount_amount FROM public.purchase p
 WHERE p.organization_id=p_organization_id AND p.id=p_purchase_id
), base AS (
 SELECT i.id AS item_id,i.product_id,i.quantity,i.unit_cost,i.line_total,i.line_number,
        h.subtotal,h.discount_amount,
        CASE WHEN h.subtotal=0 THEN 0 ELSE h.discount_amount*10000*i.line_total/h.subtotal END AS exact_discount_units,
        floor(CASE WHEN h.subtotal=0 THEN 0 ELSE h.discount_amount*10000*i.line_total/h.subtotal END) AS base_discount_units
 FROM public.purchase_items i CROSS JOIN header h
 WHERE i.organization_id=p_organization_id AND i.purchase_id=p_purchase_id
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
SELECT a.item_id,a.product_id,a.quantity,a.unit_cost,a.line_total,round(a.line_total-a.discount_units/10000,4)
FROM allocated a;
$function$;

CREATE OR REPLACE FUNCTION private.sales_net_lines(p_organization_id uuid,p_sales_id uuid)
RETURNS TABLE(item_id uuid,product_id uuid,quantity numeric,unit_price numeric,line_total numeric,net_line_total numeric)
LANGUAGE sql STABLE SET search_path = ''
AS $function$
WITH header AS (
 SELECT s.subtotal,s.discount_amount FROM public.sales s
 WHERE s.organization_id=p_organization_id AND s.id=p_sales_id
), base AS (
 SELECT i.id AS item_id,i.product_id,i.quantity,i.unit_price,i.line_total,i.line_number,
        h.subtotal,h.discount_amount,
        CASE WHEN h.subtotal=0 THEN 0 ELSE h.discount_amount*10000*i.line_total/h.subtotal END AS exact_discount_units,
        floor(CASE WHEN h.subtotal=0 THEN 0 ELSE h.discount_amount*10000*i.line_total/h.subtotal END) AS base_discount_units
 FROM public.sales_items i CROSS JOIN header h
 WHERE i.organization_id=p_organization_id AND i.sales_id=p_sales_id
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
SELECT a.item_id,a.product_id,a.quantity,a.unit_price,a.line_total,round(a.line_total-a.discount_units/10000,4)
FROM allocated a;
$function$;

REVOKE ALL ON FUNCTION private.purchase_net_lines(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION private.sales_net_lines(uuid,uuid) FROM PUBLIC,anon,authenticated;

COMMIT;

-- 15. PURCHASE AND SALES RETURN POSTING

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

-- 16. MASTER-DATA IMMUTABILITY

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

-- 17. INVENTORY ADJUSTMENTS

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
  IF p_items IS NULL OR jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items)=0 THEN
    RAISE EXCEPTION 'Inventory adjustment requires a non-empty JSON array' USING ERRCODE='22023';
  END IF;

  SELECT o.status INTO v_org_status
    FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Inventory adjustments require an active organization' USING ERRCODE='23514';
  END IF;

  SELECT count(*),count(DISTINCT x.product_id),
         count(*) FILTER (
           WHERE x.product_id IS NULL OR x.direction NOT IN ('in','out')
              OR x.quantity IS NULL OR x.quantity<=0
              OR (x.direction='in' AND (x.unit_cost IS NULL OR x.unit_cost<=0))
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

-- 18. PAYMENT POSTING AND ALLOCATION

BEGIN;

CREATE OR REPLACE FUNCTION public.post_payment(p_organization_id uuid,p_payment_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid:=auth.uid();
  v_org_status text;
  v_payment public.payments%ROWTYPE;
  v_account_type text;
  v_settlement_type text;
  v_journal_id uuid:=gen_random_uuid();
  v_alloc record;
  v_doc_contact uuid;
  v_doc_account uuid;
  v_doc_total numeric(20,4);
  v_returned numeric(20,4);
  v_previously_allocated numeric(20,4);
  v_allocated_total numeric(20,4);
  v_alloc_count bigint;
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;

  SELECT o.status INTO v_org_status
    FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Payment posting requires an active organization' USING ERRCODE='23514';
  END IF;

  SELECT p.* INTO v_payment
    FROM public.payments p
   WHERE p.organization_id=p_organization_id AND p.id=p_payment_id
   FOR UPDATE;
  IF NOT FOUND OR v_payment.status<>'draft' OR v_payment.posted_journal_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Payment not found, not draft, or already posted' USING ERRCODE='23514';
  END IF;
  IF v_payment.payment_type NOT IN ('receipt','payment') THEN
    RAISE EXCEPTION 'Payment type must be receipt or payment' USING ERRCODE='23514';
  END IF;
  IF v_payment.amount<=0 OR v_payment.contact_id IS NULL OR v_payment.settlement_account_id IS NULL THEN
    RAISE EXCEPTION 'Payment requires a positive amount, contact, and settlement account' USING ERRCODE='23514';
  END IF;

  SELECT a.account_type INTO v_account_type
    FROM public.accounts a
   WHERE a.organization_id=p_organization_id AND a.id=v_payment.account_id
     AND a.status='active' AND a.is_postable;
  IF (v_payment.payment_type='receipt' AND v_account_type IS DISTINCT FROM 'asset')
     OR (v_payment.payment_type='payment' AND v_account_type IS DISTINCT FROM 'liability') THEN
    RAISE EXCEPTION 'Receipt requires an active postable receivable asset account; payment requires an active postable payable liability account' USING ERRCODE='23514';
  END IF;

  SELECT a.account_type INTO v_settlement_type
    FROM public.accounts a
   WHERE a.organization_id=p_organization_id AND a.id=v_payment.settlement_account_id
     AND a.status='active' AND a.is_postable;
  IF v_settlement_type IS DISTINCT FROM 'asset' THEN
    RAISE EXCEPTION 'Settlement account must be an active postable asset account' USING ERRCODE='23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.contacts c
     WHERE c.organization_id=p_organization_id AND c.id=v_payment.contact_id AND c.status='active'
  ) THEN
    RAISE EXCEPTION 'Payment contact is missing or inactive' USING ERRCODE='23514';
  END IF;

  SELECT count(*),COALESCE(sum(pa.allocated_amount),0)
    INTO v_alloc_count,v_allocated_total
    FROM public.payment_allocations pa
   WHERE pa.organization_id=p_organization_id AND pa.payment_id=p_payment_id;
  IF v_allocated_total>v_payment.amount THEN
    RAISE EXCEPTION 'Payment allocations exceed payment amount' USING ERRCODE='23514';
  END IF;

  FOR v_alloc IN
    SELECT pa.document_type,pa.document_id,pa.allocated_amount
      FROM public.payment_allocations pa
     WHERE pa.organization_id=p_organization_id AND pa.payment_id=p_payment_id
     ORDER BY pa.document_type,pa.document_id
  LOOP
    IF v_payment.payment_type='receipt' AND v_alloc.document_type='sales' THEN
      SELECT s.customer_id,s.receivable_account_id,s.total_amount
        INTO v_doc_contact,v_doc_account,v_doc_total
        FROM public.sales s
       WHERE s.organization_id=p_organization_id AND s.id=v_alloc.document_id
       FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Receipt allocation references a missing sale' USING ERRCODE='23514'; END IF;
      IF NOT EXISTS(SELECT 1 FROM public.sales s WHERE s.organization_id=p_organization_id AND s.id=v_alloc.document_id AND s.status='posted') THEN
        RAISE EXCEPTION 'Receipt can only be allocated to a posted sale' USING ERRCODE='23514';
      END IF;
      SELECT COALESCE(sum(r.total_amount),0) INTO v_returned
        FROM public.sales_returns r
       WHERE r.organization_id=p_organization_id AND r.sales_id=v_alloc.document_id AND r.status='posted';
      SELECT COALESCE(sum(pa.allocated_amount),0) INTO v_previously_allocated
        FROM public.payment_allocations pa
        JOIN public.payments p ON p.organization_id=pa.organization_id AND p.id=pa.payment_id
       WHERE pa.organization_id=p_organization_id AND pa.document_type='sales'
         AND pa.document_id=v_alloc.document_id AND pa.payment_id<>p_payment_id
         AND p.payment_type='receipt' AND p.status='posted';
    ELSIF v_payment.payment_type='payment' AND v_alloc.document_type='purchase' THEN
      SELECT s.supplier_id,s.payable_account_id,s.total_amount
        INTO v_doc_contact,v_doc_account,v_doc_total
        FROM public.purchase s
       WHERE s.organization_id=p_organization_id AND s.id=v_alloc.document_id
       FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Payment allocation references a missing purchase' USING ERRCODE='23514'; END IF;
      IF NOT EXISTS(SELECT 1 FROM public.purchase s WHERE s.organization_id=p_organization_id AND s.id=v_alloc.document_id AND s.status='posted') THEN
        RAISE EXCEPTION 'Payment can only be allocated to a posted purchase' USING ERRCODE='23514';
      END IF;
      SELECT COALESCE(sum(r.total_amount),0) INTO v_returned
        FROM public.purchase_returns r
       WHERE r.organization_id=p_organization_id AND r.purchase_id=v_alloc.document_id AND r.status='posted';
      SELECT COALESCE(sum(pa.allocated_amount),0) INTO v_previously_allocated
        FROM public.payment_allocations pa
        JOIN public.payments p ON p.organization_id=pa.organization_id AND p.id=pa.payment_id
       WHERE pa.organization_id=p_organization_id AND pa.document_type='purchase'
         AND pa.document_id=v_alloc.document_id AND pa.payment_id<>p_payment_id
         AND p.payment_type='payment' AND p.status='posted';
    ELSE
      RAISE EXCEPTION 'Allocation document type does not match payment type' USING ERRCODE='23514';
    END IF;

    IF v_doc_contact IS DISTINCT FROM v_payment.contact_id
       OR v_doc_account IS DISTINCT FROM v_payment.account_id THEN
      RAISE EXCEPTION 'Allocation contact or control account does not match the source invoice' USING ERRCODE='23514';
    END IF;
    IF v_alloc.allocated_amount<=0
       OR v_alloc.allocated_amount>round(v_doc_total-v_returned-v_previously_allocated,4) THEN
      RAISE EXCEPTION 'Allocation exceeds the remaining invoice balance' USING ERRCODE='23514';
    END IF;
  END LOOP;

  PERFORM set_config('zero_erp.allow_workflow','on',true);
  INSERT INTO public.journal_entries(
    id,organization_id,entry_date,entry_type,status,reference_type,reference_id,
    description,created_by,created_at,updated_by,updated_at
  )
  VALUES(
    v_journal_id,p_organization_id,v_payment.payment_date,
    CASE WHEN v_payment.payment_type='receipt' THEN 'receipt' ELSE 'payment' END,
    'draft','payment',p_payment_id,
    COALESCE(v_payment.description,CASE WHEN v_payment.payment_type='receipt' THEN 'Customer receipt' ELSE 'Supplier payment' END),
    v_user_id,now(),v_user_id,now()
  );

  IF v_payment.payment_type='receipt' THEN
    INSERT INTO public.account_transactions(
      organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by
    ) VALUES
      (p_organization_id,v_journal_id,v_payment.settlement_account_id,1,'Cash/bank received',v_payment.amount,0,NULL,v_user_id,v_user_id),
      (p_organization_id,v_journal_id,v_payment.account_id,2,'Customer receivable settled',0,v_payment.amount,v_payment.contact_id,v_user_id,v_user_id);
  ELSE
    INSERT INTO public.account_transactions(
      organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by
    ) VALUES
      (p_organization_id,v_journal_id,v_payment.account_id,1,'Supplier payable settled',v_payment.amount,0,v_payment.contact_id,v_user_id,v_user_id),
      (p_organization_id,v_journal_id,v_payment.settlement_account_id,2,'Cash/bank paid',0,v_payment.amount,NULL,v_user_id,v_user_id);
  END IF;

  PERFORM public.post_journal_entry(p_organization_id,v_journal_id);

  UPDATE public.payments
     SET code=COALESCE(code,private.allocate_document_number(p_organization_id,'payments')),
         status='posted',confirmed_at=now(),confirmed_by=v_user_id,
         posted_by=v_user_id,posted_journal_entry_id=v_journal_id,
         updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_payment_id AND status='draft';
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment posting failed' USING ERRCODE='23514'; END IF;

  RETURN v_journal_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.post_payment(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.post_payment(uuid,uuid) TO authenticated;

COMMIT;

-- 18.1. Payment vocabulary and allocation constraints

BEGIN;
ALTER TABLE public.payments
  ADD CONSTRAINT payments_payment_type_check CHECK (payment_type IN ('receipt','payment'));
ALTER TABLE public.payment_allocations
  ADD CONSTRAINT payment_allocations_document_type_check CHECK (document_type IN ('sales','purchase'));
CREATE UNIQUE INDEX payment_allocations_one_invoice_per_payment_uidx
  ON public.payment_allocations(organization_id,payment_id,document_type,document_id);
COMMIT;

-- 19. OPENING-BALANCE SUBLEDGER

BEGIN;

CREATE TABLE public.opening_balance_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  opening_journal_entry_id uuid NOT NULL,
  opening_journal_line_id uuid NOT NULL UNIQUE,
  account_id uuid NOT NULL,
  contact_id uuid NOT NULL,
  balance_type text NOT NULL CHECK (balance_type IN ('receivable','payable')),
  description text,
  opening_date date NOT NULL,
  original_amount numeric(20,4) NOT NULL CHECK (original_amount > 0),
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT opening_balance_items_org_fk
    FOREIGN KEY (organization_id) REFERENCES public.organizations(id),
  CONSTRAINT opening_balance_items_journal_fk
    FOREIGN KEY (organization_id,opening_journal_entry_id)
    REFERENCES public.journal_entries(organization_id,id),
  CONSTRAINT opening_balance_items_line_fk
    FOREIGN KEY (opening_journal_line_id) REFERENCES public.account_transactions(id),
  CONSTRAINT opening_balance_items_account_fk
    FOREIGN KEY (organization_id,account_id) REFERENCES public.accounts(organization_id,id),
  CONSTRAINT opening_balance_items_contact_fk
    FOREIGN KEY (organization_id,contact_id) REFERENCES public.contacts(organization_id,id)
);

CREATE INDEX opening_balance_items_contact_idx
  ON public.opening_balance_items(organization_id,contact_id,balance_type);
CREATE INDEX opening_balance_items_journal_idx
  ON public.opening_balance_items(organization_id,opening_journal_entry_id);

ALTER TABLE public.opening_balance_items ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.opening_balance_items TO authenticated;
CREATE POLICY opening_balance_items_member_select
  ON public.opening_balance_items FOR SELECT TO authenticated
  USING (private.is_org_member(organization_id) OR private.is_org_creator(organization_id));

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
         AND (
           (a.code='1130' AND (t.debit<=0 OR t.credit<>0 OR c.status IS DISTINCT FROM 'active'))
           OR
           (a.code='2110' AND (t.credit<=0 OR t.debit<>0 OR c.status IS DISTINCT FROM 'active'))
         )
    ) THEN
      RAISE EXCEPTION 'Opening receivable lines must be debit balances and opening payable lines must be credit balances for active contacts'
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
       AND a.code='1130' AND t.debit>0 AND t.credit=0;

    INSERT INTO public.opening_balance_items(
      organization_id,opening_journal_entry_id,opening_journal_line_id,
      account_id,contact_id,balance_type,description,opening_date,original_amount,created_by
    )
    SELECT t.organization_id,NEW.id,t.id,t.account_id,t.contact_id,'payable',
           t.description,NEW.entry_date,t.credit,t.created_by
      FROM public.account_transactions t
      JOIN public.accounts a ON a.organization_id=t.organization_id AND a.id=t.account_id
     WHERE t.organization_id=NEW.organization_id AND t.journal_entry_id=NEW.id
       AND a.code='2110' AND t.credit>0 AND t.debit=0;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.materialize_opening_balance_items() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER journal_entries_materialize_opening_balances
AFTER UPDATE OF status ON public.journal_entries
FOR EACH ROW
EXECUTE FUNCTION private.materialize_opening_balance_items();

ALTER TABLE public.payment_allocations
  DROP CONSTRAINT payment_allocations_document_type_check;
ALTER TABLE public.payment_allocations
  ADD CONSTRAINT payment_allocations_document_type_check
  CHECK (document_type IN ('sales','purchase','opening_balance'));

CREATE OR REPLACE FUNCTION public.post_payment(p_organization_id uuid,p_payment_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid:=auth.uid();
  v_org_status text;
  v_payment public.payments%ROWTYPE;
  v_account_type text;
  v_settlement_type text;
  v_journal_id uuid:=gen_random_uuid();
  v_alloc record;
  v_doc_contact uuid;
  v_doc_account uuid;
  v_doc_total numeric(20,4);
  v_returned numeric(20,4);
  v_previously_allocated numeric(20,4);
  v_allocated_total numeric(20,4);
  v_doc_balance_type text;
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  SELECT o.status INTO v_org_status FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'active' THEN RAISE EXCEPTION 'Payment posting requires an active organization' USING ERRCODE='23514'; END IF;

  SELECT p.* INTO v_payment FROM public.payments p
   WHERE p.organization_id=p_organization_id AND p.id=p_payment_id FOR UPDATE;
  IF NOT FOUND OR v_payment.status<>'draft' OR v_payment.posted_journal_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Payment not found, not draft, or already posted' USING ERRCODE='23514';
  END IF;
  IF v_payment.payment_type NOT IN ('receipt','payment') THEN RAISE EXCEPTION 'Payment type must be receipt or payment' USING ERRCODE='23514'; END IF;
  IF v_payment.amount<=0 OR v_payment.contact_id IS NULL OR v_payment.settlement_account_id IS NULL THEN
    RAISE EXCEPTION 'Payment requires a positive amount, contact, and settlement account' USING ERRCODE='23514';
  END IF;

  SELECT a.account_type INTO v_account_type FROM public.accounts a
   WHERE a.organization_id=p_organization_id AND a.id=v_payment.account_id
     AND a.status='active' AND a.is_postable;
  IF (v_payment.payment_type='receipt' AND v_account_type IS DISTINCT FROM 'asset')
     OR (v_payment.payment_type='payment' AND v_account_type IS DISTINCT FROM 'liability') THEN
    RAISE EXCEPTION 'Receipt requires an active postable receivable asset account; payment requires an active postable payable liability account' USING ERRCODE='23514';
  END IF;

  SELECT a.account_type INTO v_settlement_type FROM public.accounts a
   WHERE a.organization_id=p_organization_id AND a.id=v_payment.settlement_account_id
     AND a.status='active' AND a.is_postable;
  IF v_settlement_type IS DISTINCT FROM 'asset' THEN RAISE EXCEPTION 'Settlement account must be an active postable asset account' USING ERRCODE='23514'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.contacts c WHERE c.organization_id=p_organization_id AND c.id=v_payment.contact_id AND c.status='active') THEN
    RAISE EXCEPTION 'Payment contact is missing or inactive' USING ERRCODE='23514';
  END IF;

  SELECT COALESCE(sum(pa.allocated_amount),0) INTO v_allocated_total
    FROM public.payment_allocations pa WHERE pa.organization_id=p_organization_id AND pa.payment_id=p_payment_id;
  IF v_allocated_total>v_payment.amount THEN RAISE EXCEPTION 'Payment allocations exceed payment amount' USING ERRCODE='23514'; END IF;

  FOR v_alloc IN
    SELECT pa.document_type,pa.document_id,pa.allocated_amount
      FROM public.payment_allocations pa
     WHERE pa.organization_id=p_organization_id AND pa.payment_id=p_payment_id
     ORDER BY pa.document_type,pa.document_id
  LOOP
    v_returned:=0;
    v_previously_allocated:=0;
    v_doc_balance_type:=NULL;

    IF v_payment.payment_type='receipt' AND v_alloc.document_type='sales' THEN
      SELECT s.customer_id,s.receivable_account_id,s.total_amount
        INTO v_doc_contact,v_doc_account,v_doc_total
        FROM public.sales s WHERE s.organization_id=p_organization_id AND s.id=v_alloc.document_id FOR UPDATE;
      IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.sales s WHERE s.organization_id=p_organization_id AND s.id=v_alloc.document_id AND s.status='posted') THEN
        RAISE EXCEPTION 'Receipt allocation must reference a posted sale' USING ERRCODE='23514';
      END IF;
      SELECT COALESCE(sum(r.total_amount),0) INTO v_returned FROM public.sales_returns r
       WHERE r.organization_id=p_organization_id AND r.sales_id=v_alloc.document_id AND r.status='posted';
      SELECT COALESCE(sum(pa.allocated_amount),0) INTO v_previously_allocated
        FROM public.payment_allocations pa JOIN public.payments p ON p.organization_id=pa.organization_id AND p.id=pa.payment_id
       WHERE pa.organization_id=p_organization_id AND pa.document_type='sales' AND pa.document_id=v_alloc.document_id
         AND pa.payment_id<>p_payment_id AND p.payment_type='receipt' AND p.status='posted';

    ELSIF v_payment.payment_type='payment' AND v_alloc.document_type='purchase' THEN
      SELECT s.supplier_id,s.payable_account_id,s.total_amount
        INTO v_doc_contact,v_doc_account,v_doc_total
        FROM public.purchase s WHERE s.organization_id=p_organization_id AND s.id=v_alloc.document_id FOR UPDATE;
      IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.purchase s WHERE s.organization_id=p_organization_id AND s.id=v_alloc.document_id AND s.status='posted') THEN
        RAISE EXCEPTION 'Payment allocation must reference a posted purchase' USING ERRCODE='23514';
      END IF;
      SELECT COALESCE(sum(r.total_amount),0) INTO v_returned FROM public.purchase_returns r
       WHERE r.organization_id=p_organization_id AND r.purchase_id=v_alloc.document_id AND r.status='posted';
      SELECT COALESCE(sum(pa.allocated_amount),0) INTO v_previously_allocated
        FROM public.payment_allocations pa JOIN public.payments p ON p.organization_id=pa.organization_id AND p.id=pa.payment_id
       WHERE pa.organization_id=p_organization_id AND pa.document_type='purchase' AND pa.document_id=v_alloc.document_id
         AND pa.payment_id<>p_payment_id AND p.payment_type='payment' AND p.status='posted';

    ELSIF v_payment.payment_type='receipt' AND v_alloc.document_type='opening_balance' THEN
      SELECT ob.contact_id,ob.account_id,ob.original_amount,ob.balance_type
        INTO v_doc_contact,v_doc_account,v_doc_total,v_doc_balance_type
        FROM public.opening_balance_items ob
       WHERE ob.organization_id=p_organization_id AND ob.id=v_alloc.document_id FOR UPDATE;
      IF NOT FOUND OR v_doc_balance_type IS DISTINCT FROM 'receivable' THEN
        RAISE EXCEPTION 'Receipt allocation must reference an opening receivable balance' USING ERRCODE='23514';
      END IF;
      SELECT COALESCE(sum(pa.allocated_amount),0) INTO v_previously_allocated
        FROM public.payment_allocations pa JOIN public.payments p ON p.organization_id=pa.organization_id AND p.id=pa.payment_id
       WHERE pa.organization_id=p_organization_id AND pa.document_type='opening_balance' AND pa.document_id=v_alloc.document_id
         AND pa.payment_id<>p_payment_id AND p.payment_type='receipt' AND p.status='posted';

    ELSIF v_payment.payment_type='payment' AND v_alloc.document_type='opening_balance' THEN
      SELECT ob.contact_id,ob.account_id,ob.original_amount,ob.balance_type
        INTO v_doc_contact,v_doc_account,v_doc_total,v_doc_balance_type
        FROM public.opening_balance_items ob
       WHERE ob.organization_id=p_organization_id AND ob.id=v_alloc.document_id FOR UPDATE;
      IF NOT FOUND OR v_doc_balance_type IS DISTINCT FROM 'payable' THEN
        RAISE EXCEPTION 'Supplier payment allocation must reference an opening payable balance' USING ERRCODE='23514';
      END IF;
      SELECT COALESCE(sum(pa.allocated_amount),0) INTO v_previously_allocated
        FROM public.payment_allocations pa JOIN public.payments p ON p.organization_id=pa.organization_id AND p.id=pa.payment_id
       WHERE pa.organization_id=p_organization_id AND pa.document_type='opening_balance' AND pa.document_id=v_alloc.document_id
         AND pa.payment_id<>p_payment_id AND p.payment_type='payment' AND p.status='posted';
    ELSE
      RAISE EXCEPTION 'Allocation document type does not match payment type' USING ERRCODE='23514';
    END IF;

    IF v_doc_contact IS DISTINCT FROM v_payment.contact_id OR v_doc_account IS DISTINCT FROM v_payment.account_id THEN
      RAISE EXCEPTION 'Allocation contact or control account does not match source balance' USING ERRCODE='23514';
    END IF;
    IF v_alloc.allocated_amount<=0 OR v_alloc.allocated_amount>round(v_doc_total-v_returned-v_previously_allocated,4) THEN
      RAISE EXCEPTION 'Allocation exceeds remaining invoice/opening balance' USING ERRCODE='23514';
    END IF;
  END LOOP;

  PERFORM set_config('zero_erp.allow_workflow','on',true);
  INSERT INTO public.journal_entries(id,organization_id,entry_date,entry_type,status,reference_type,reference_id,description,created_by,created_at,updated_by,updated_at)
  VALUES(v_journal_id,p_organization_id,v_payment.payment_date,
    CASE WHEN v_payment.payment_type='receipt' THEN 'receipt' ELSE 'payment' END,
    'draft','payment',p_payment_id,
    COALESCE(v_payment.description,CASE WHEN v_payment.payment_type='receipt' THEN 'Customer receipt' ELSE 'Supplier payment' END),
    v_user_id,now(),v_user_id,now());

  IF v_payment.payment_type='receipt' THEN
    INSERT INTO public.account_transactions(organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by)
    VALUES(p_organization_id,v_journal_id,v_payment.settlement_account_id,1,'Cash/bank received',v_payment.amount,0,NULL,v_user_id,v_user_id),
          (p_organization_id,v_journal_id,v_payment.account_id,2,'Customer receivable settled',0,v_payment.amount,v_payment.contact_id,v_user_id,v_user_id);
  ELSE
    INSERT INTO public.account_transactions(organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by)
    VALUES(p_organization_id,v_journal_id,v_payment.account_id,1,'Supplier payable settled',v_payment.amount,0,v_payment.contact_id,v_user_id,v_user_id),
          (p_organization_id,v_journal_id,v_payment.settlement_account_id,2,'Cash/bank paid',0,v_payment.amount,NULL,v_user_id,v_user_id);
  END IF;

  PERFORM public.post_journal_entry(p_organization_id,v_journal_id);
  UPDATE public.payments SET code=COALESCE(code,private.allocate_document_number(p_organization_id,'payments')),
    status='posted',confirmed_at=now(),confirmed_by=v_user_id,posted_by=v_user_id,posted_journal_entry_id=v_journal_id,
    updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_payment_id AND status='draft';
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment posting failed' USING ERRCODE='23514'; END IF;
  RETURN v_journal_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.post_payment(uuid,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.post_payment(uuid,uuid) TO authenticated;

COMMIT;

-- 19.1. Opening-balance lookup indexes

CREATE INDEX IF NOT EXISTS opening_balance_items_account_idx
  ON public.opening_balance_items(organization_id,account_id);

-- 20. CONTROL-ACCOUNT AND CONTACT RULES

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

  IF TG_TABLE_NAME IN ('sales','sales_returns') THEN
    v_contact_id:=NEW.customer_id;
  ELSIF TG_TABLE_NAME IN ('purchase','purchase_returns') THEN
    v_contact_id:=NEW.supplier_id;
  ELSE
    v_contact_id:=NEW.contact_id;
  END IF;

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

-- 21. ACCOUNT AND DOCUMENT IMMUTABILITY

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

-- 21.1. Account contact-dimension guard

DROP TRIGGER IF EXISTS accounts_used_definition_immutable ON public.accounts;
CREATE TRIGGER accounts_used_definition_immutable
BEFORE UPDATE OF code,account_type,normal_balance,is_control_account,is_postable,requires_contact
ON public.accounts
FOR EACH ROW EXECUTE FUNCTION private.enforce_used_account_definition_immutable();

-- 22. PAYMENT AND EXPENSE REVERSALS

BEGIN;

CREATE OR REPLACE FUNCTION private.reverse_source_journal(
  p_organization_id uuid,
  p_journal_entry_id uuid,
  p_source_type text,
  p_source_id uuid,
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
  PERFORM o.id FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization not found' USING ERRCODE='23503'; END IF;
  IF p_reversal_date IS NULL OR p_reason IS NULL OR btrim(p_reason)='' OR length(btrim(p_reason))>500 THEN
    RAISE EXCEPTION 'A reversal date and reason of 1-500 characters are required' USING ERRCODE='22023';
  END IF;
  IF p_source_type NOT IN ('payment','expense') OR p_source_id IS NULL THEN
    RAISE EXCEPTION 'Unsupported source document reversal type' USING ERRCODE='22023';
  END IF;

  SELECT o.status INTO v_org_status FROM public.organizations o
   WHERE o.id=p_organization_id FOR UPDATE;
  IF v_org_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Source document reversal requires an active organization' USING ERRCODE='23514';
  END IF;

  SELECT j.* INTO v_original FROM public.journal_entries j
   WHERE j.organization_id=p_organization_id AND j.id=p_journal_entry_id FOR UPDATE;
  IF NOT FOUND OR v_original.status<>'posted'
     OR v_original.reversal_of_id IS NOT NULL
     OR v_original.reversal_journal_entry_id IS NOT NULL
     OR v_original.reference_type IS DISTINCT FROM p_source_type
     OR v_original.reference_id IS DISTINCT FROM p_source_id THEN
    RAISE EXCEPTION 'Source journal is missing, already reversed, or does not match the source document' USING ERRCODE='23514';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.account_transactions t
     WHERE t.organization_id=p_organization_id AND t.journal_entry_id=p_journal_entry_id
  ) THEN
    RAISE EXCEPTION 'Source journal has no lines to reverse' USING ERRCODE='23514';
  END IF;

  PERFORM set_config('zero_erp.allow_workflow','on',true);
  v_reversal_code:=private.allocate_document_number(p_organization_id,'journal_entries');
  INSERT INTO public.journal_entries(
    id,organization_id,code,entry_date,entry_type,status,reference_type,reference_id,
    description,reversal_of_id,reversal_reason,created_by,created_at,updated_by,updated_at
  )
  VALUES(
    v_reversal_id,p_organization_id,v_reversal_code,p_reversal_date,'reversal','draft',
    'journal_entry',v_original.id,
    'Reversal of '||COALESCE(v_original.code,v_original.id::text),
    v_original.id,btrim(p_reason),v_user_id,now(),v_user_id,now()
  );

  INSERT INTO public.account_transactions(
    organization_id,journal_entry_id,account_id,line_number,description,debit,credit,contact_id,created_by,updated_by
  )
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
REVOKE ALL ON FUNCTION private.reverse_source_journal(uuid,uuid,text,uuid,date,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.reverse_payment(
  p_organization_id uuid,p_payment_id uuid,p_reversal_date date,p_reason text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid:=auth.uid();
  v_payment public.payments%ROWTYPE;
  v_reversal_id uuid;
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  PERFORM o.id FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization not found' USING ERRCODE='23503'; END IF;
  SELECT p.* INTO v_payment FROM public.payments p
   WHERE p.organization_id=p_organization_id AND p.id=p_payment_id FOR UPDATE;
  IF NOT FOUND OR v_payment.status<>'posted' OR v_payment.reversal_journal_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Only an unreversed posted payment can be reversed' USING ERRCODE='23514';
  END IF;

  v_reversal_id:=private.reverse_source_journal(
    p_organization_id,v_payment.posted_journal_entry_id,'payment',p_payment_id,p_reversal_date,p_reason
  );
  PERFORM set_config('zero_erp.allow_workflow','on',true);
  UPDATE public.payments
     SET status='reversed',reversal_journal_entry_id=v_reversal_id,
         reversed_at=now(),reversed_by=v_user_id,reversal_reason=btrim(p_reason),
         updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_payment_id AND status='posted';
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment reversal metadata could not be finalized' USING ERRCODE='23514'; END IF;
  RETURN v_reversal_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.reverse_payment(uuid,uuid,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reverse_payment(uuid,uuid,date,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.reverse_expense(
  p_organization_id uuid,p_expense_id uuid,p_reversal_date date,p_reason text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid:=auth.uid();
  v_expense public.expenses%ROWTYPE;
  v_reversal_id uuid;
BEGIN
  IF v_user_id IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  PERFORM o.id FROM public.organizations o WHERE o.id=p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization not found' USING ERRCODE='23503'; END IF;
  SELECT e.* INTO v_expense FROM public.expenses e
   WHERE e.organization_id=p_organization_id AND e.id=p_expense_id FOR UPDATE;
  IF NOT FOUND OR v_expense.status<>'posted' OR v_expense.reversal_journal_entry_id IS NOT NULL THEN
    RAISE EXCEPTION 'Only an unreversed posted expense can be reversed' USING ERRCODE='23514';
  END IF;

  v_reversal_id:=private.reverse_source_journal(
    p_organization_id,v_expense.posted_journal_entry_id,'expense',p_expense_id,p_reversal_date,p_reason
  );
  PERFORM set_config('zero_erp.allow_workflow','on',true);
  UPDATE public.expenses
     SET status='reversed',reversal_journal_entry_id=v_reversal_id,
         reversed_at=now(),reversed_by=v_user_id,reversal_reason=btrim(p_reason),
         updated_by=v_user_id,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_expense_id AND status='posted';
  IF NOT FOUND THEN RAISE EXCEPTION 'Expense reversal metadata could not be finalized' USING ERRCODE='23514'; END IF;
  RETURN v_reversal_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.reverse_expense(uuid,uuid,date,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reverse_expense(uuid,uuid,date,text) TO authenticated;

COMMIT;

-- 23. PURCHASE AND SALES RETURN REVERSALS

BEGIN;

CREATE OR REPLACE FUNCTION public.reverse_purchase_return(
  p_organization_id uuid, p_return_id uuid, p_reversal_date date, p_reason text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_user uuid:=auth.uid();
  v_return public.purchase_returns%ROWTYPE;
  v_source public.purchase%ROWTYPE;
  v_journal uuid;
  v_item record;
  v_balance public.inventory_balances%ROWTYPE;
  v_new_qty numeric(20,6);
  v_new_value numeric(20,4);
  v_avg numeric(20,6);
BEGIN
  IF v_user IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  PERFORM 1 FROM public.organizations WHERE id=p_organization_id AND status='active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization not found or inactive' USING ERRCODE='23514'; END IF;
  SELECT * INTO v_return FROM public.purchase_returns
   WHERE organization_id=p_organization_id AND id=p_return_id FOR UPDATE;
  IF NOT FOUND OR v_return.status<>'posted' OR v_return.reversal_journal_entry_id IS NOT NULL
     OR v_return.posted_journal_entry_id IS NULL THEN
    RAISE EXCEPTION 'Only an unreversed posted purchase return can be reversed' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_source FROM public.purchase
   WHERE organization_id=p_organization_id AND id=v_return.purchase_id FOR UPDATE;
  IF NOT FOUND OR v_source.status<>'posted' THEN
    RAISE EXCEPTION 'Source purchase is not posted' USING ERRCODE='23514';
  END IF;

  PERFORM p.id FROM public.products p
   JOIN (SELECT DISTINCT product_id FROM public.inventory_transactions
          WHERE organization_id=p_organization_id AND reference_type='journal_entry'
            AND reference_id=v_return.posted_journal_entry_id
            AND transaction_type='purchase_return') x ON x.product_id=p.id
   WHERE p.organization_id=p_organization_id ORDER BY p.id FOR UPDATE OF p;

  FOR v_item IN
    SELECT product_id, sum(quantity)::numeric(20,6) qty,
           sum(total_value)::numeric(20,4) val
      FROM public.inventory_transactions
     WHERE organization_id=p_organization_id AND reference_type='journal_entry'
       AND reference_id=v_return.posted_journal_entry_id
       AND transaction_type='purchase_return' AND direction='out'
     GROUP BY product_id ORDER BY product_id
  LOOP
    SELECT * INTO v_balance FROM public.inventory_balances
     WHERE organization_id=p_organization_id AND product_id=v_item.product_id FOR UPDATE;
    IF NOT FOUND THEN
      INSERT INTO public.inventory_balances(organization_id,product_id,quantity,average_cost,inventory_value,created_by,updated_by,updated_at)
      VALUES(p_organization_id,v_item.product_id,v_item.qty,
             CASE WHEN v_item.qty=0 THEN 0 ELSE round(v_item.val/v_item.qty,6) END,
             v_item.val,v_user,v_user,now());
      v_new_qty:=v_item.qty; v_new_value:=v_item.val;
    ELSE
      v_new_qty:=v_balance.quantity+v_item.qty;
      v_new_value:=round(v_balance.inventory_value+v_item.val,4);
      UPDATE public.inventory_balances
         SET quantity=v_new_qty,inventory_value=v_new_value,
             average_cost=CASE WHEN v_new_qty=0 THEN 0 ELSE round(v_new_value/v_new_qty,6) END,
             updated_by=v_user,updated_at=now()
       WHERE organization_id=p_organization_id AND product_id=v_item.product_id;
    END IF;
    v_avg:=CASE WHEN v_new_qty=0 THEN 0 ELSE round(v_new_value/v_new_qty,6) END;
    INSERT INTO public.inventory_transactions(
      organization_id,code,product_id,transaction_date,transaction_type,direction,quantity,unit_cost,total_value,
      reference_type,reference_id,unit_cost_before,average_cost_after,created_by
    ) VALUES (
      p_organization_id,private.allocate_document_number(p_organization_id,'inventory_transactions'),
      v_item.product_id,p_reversal_date,'purchase_return_reversal','in',v_item.qty,
      CASE WHEN v_item.qty=0 THEN 0 ELSE round(v_item.val/v_item.qty,6) END,v_item.val,
      'journal_entry',v_return.posted_journal_entry_id,v_balance.average_cost,v_avg,v_user
    );
  END LOOP;

  v_journal:=private.reverse_source_journal(
    p_organization_id,v_return.posted_journal_entry_id,'purchase_return',p_return_id,p_reversal_date,p_reason
  );
  PERFORM set_config('zero_erp.allow_workflow','on',true);
  UPDATE public.purchase_returns
     SET status='reversed',reversal_journal_entry_id=v_journal,reversed_at=now(),
         reversed_by=v_user,reversal_reason=btrim(p_reason),updated_by=v_user,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_return_id AND status='posted';
  IF NOT FOUND THEN RAISE EXCEPTION 'Purchase return reversal metadata could not be finalized' USING ERRCODE='23514'; END IF;
  RETURN v_journal;
END;
$function$;

CREATE OR REPLACE FUNCTION public.reverse_sales_return(
  p_organization_id uuid, p_return_id uuid, p_reversal_date date, p_reason text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_user uuid:=auth.uid();
  v_return public.sales_returns%ROWTYPE;
  v_source public.sales%ROWTYPE;
  v_journal uuid;
  v_item record;
  v_balance public.inventory_balances%ROWTYPE;
  v_new_qty numeric(20,6);
  v_new_value numeric(20,4);
  v_avg numeric(20,6);
BEGIN
  IF v_user IS NULL OR NOT (private.is_org_member(p_organization_id) OR private.is_org_creator(p_organization_id)) THEN
    RAISE EXCEPTION 'Not authorized for this organization' USING ERRCODE='42501';
  END IF;
  PERFORM 1 FROM public.organizations WHERE id=p_organization_id AND status='active' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization not found or inactive' USING ERRCODE='23514'; END IF;
  SELECT * INTO v_return FROM public.sales_returns
   WHERE organization_id=p_organization_id AND id=p_return_id FOR UPDATE;
  IF NOT FOUND OR v_return.status<>'posted' OR v_return.reversal_journal_entry_id IS NOT NULL
     OR v_return.posted_journal_entry_id IS NULL THEN
    RAISE EXCEPTION 'Only an unreversed posted sales return can be reversed' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_source FROM public.sales
   WHERE organization_id=p_organization_id AND id=v_return.sales_id FOR UPDATE;
  IF NOT FOUND OR v_source.status<>'posted' THEN
    RAISE EXCEPTION 'Source sale is not posted' USING ERRCODE='23514';
  END IF;

  PERFORM p.id FROM public.products p
   JOIN (SELECT DISTINCT product_id FROM public.inventory_transactions
          WHERE organization_id=p_organization_id AND reference_type='journal_entry'
            AND reference_id=v_return.posted_journal_entry_id
            AND transaction_type='sales_return') x ON x.product_id=p.id
   WHERE p.organization_id=p_organization_id ORDER BY p.id FOR UPDATE OF p;

  FOR v_item IN
    SELECT product_id, sum(quantity)::numeric(20,6) qty,
           sum(total_value)::numeric(20,4) val
      FROM public.inventory_transactions
     WHERE organization_id=p_organization_id AND reference_type='journal_entry'
       AND reference_id=v_return.posted_journal_entry_id
       AND transaction_type='sales_return' AND direction='in'
     GROUP BY product_id ORDER BY product_id
  LOOP
    SELECT * INTO v_balance FROM public.inventory_balances
     WHERE organization_id=p_organization_id AND product_id=v_item.product_id FOR UPDATE;
    IF NOT FOUND OR v_balance.quantity<v_item.qty OR v_balance.inventory_value<v_item.val THEN
      RAISE EXCEPTION 'Cannot reverse sales return: returned inventory has already been consumed or revalued for product %',v_item.product_id USING ERRCODE='23514';
    END IF;
    v_new_qty:=v_balance.quantity-v_item.qty;
    v_new_value:=round(v_balance.inventory_value-v_item.val,4);
    IF v_new_qty<0 OR v_new_value<0 THEN
      RAISE EXCEPTION 'Sales return reversal would create negative inventory' USING ERRCODE='23514';
    END IF;
    v_avg:=CASE WHEN v_new_qty=0 THEN 0 ELSE round(v_new_value/v_new_qty,6) END;
    UPDATE public.inventory_balances
       SET quantity=v_new_qty,inventory_value=v_new_value,average_cost=v_avg,
           updated_by=v_user,updated_at=now()
     WHERE organization_id=p_organization_id AND product_id=v_item.product_id;
    INSERT INTO public.inventory_transactions(
      organization_id,code,product_id,transaction_date,transaction_type,direction,quantity,unit_cost,total_value,
      reference_type,reference_id,unit_cost_before,average_cost_after,created_by
    ) VALUES (
      p_organization_id,private.allocate_document_number(p_organization_id,'inventory_transactions'),
      v_item.product_id,p_reversal_date,'sales_return_reversal','out',v_item.qty,
      CASE WHEN v_item.qty=0 THEN 0 ELSE round(v_item.val/v_item.qty,6) END,v_item.val,
      'journal_entry',v_return.posted_journal_entry_id,v_balance.average_cost,v_avg,v_user
    );
  END LOOP;

  v_journal:=private.reverse_source_journal(
    p_organization_id,v_return.posted_journal_entry_id,'sales_return',p_return_id,p_reversal_date,p_reason
  );
  PERFORM set_config('zero_erp.allow_workflow','on',true);
  UPDATE public.sales_returns
     SET status='reversed',reversal_journal_entry_id=v_journal,reversed_at=now(),
         reversed_by=v_user,reversal_reason=btrim(p_reason),updated_by=v_user,updated_at=now()
   WHERE organization_id=p_organization_id AND id=p_return_id AND status='posted';
  IF NOT FOUND THEN RAISE EXCEPTION 'Sales return reversal metadata could not be finalized' USING ERRCODE='23514'; END IF;
  RETURN v_journal;
END;
$function$;

DO $extend_reversal$
DECLARE v_def text;
BEGIN
  v_def:=pg_get_functiondef('private.reverse_source_journal(uuid,uuid,text,uuid,date,text)'::regprocedure);
  v_def:=replace(v_def,
    'IF p_source_type NOT IN (''payment'',''expense'') OR p_source_id IS NULL THEN',
    'IF p_source_type NOT IN (''payment'',''expense'',''purchase_return'',''sales_return'') OR p_source_id IS NULL THEN');
  IF position('purchase_return' in v_def)=0 OR position('sales_return' in v_def)=0 THEN
    RAISE EXCEPTION 'Could not safely extend source journal reversal types';
  END IF;
  EXECUTE v_def;
END;
$extend_reversal$;

CREATE POLICY private_templates_postgres_access
ON private.default_account_templates
FOR ALL TO postgres USING (true) WITH CHECK (true);
CREATE POLICY private_expense_templates_postgres_access
ON private.default_expense_category_templates
FOR ALL TO postgres USING (true) WITH CHECK (true);

REVOKE EXECUTE ON FUNCTION public.reverse_purchase_return(uuid,uuid,date,text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.reverse_sales_return(uuid,uuid,date,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reverse_purchase_return(uuid,uuid,date,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_sales_return(uuid,uuid,date,text) TO authenticated;

COMMIT;

-- 24. PRIVATE WORKFLOW IMPLEMENTATIONS AND PUBLIC RPC FACADES

BEGIN;
GRANT USAGE ON SCHEMA private TO authenticated;
REVOKE USAGE ON SCHEMA private FROM anon;

DO $secure_facade$
DECLARE r record; v_args text; v_result text; v_call text; v_sql text; i integer;
BEGIN
  FOR r IN
    SELECT p.oid,p.proname,p.pronargs,p.oid::regprocedure::text signature
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.prosecdef AND p.proname IN (
       'complete_organization_setup','create_organization','next_account_code','post_expense',
       'post_inventory_adjustment','post_journal_entry','post_payment','post_purchase',
       'post_purchase_return','post_sales','post_sales_return','reverse_expense',
       'reverse_journal_entry','reverse_payment','reverse_purchase_return','reverse_sales_return'
     )
     ORDER BY p.proname
  LOOP
    v_args:=pg_get_function_arguments(r.oid);
    v_result:=pg_get_function_result(r.oid);
    v_call:='';
    IF r.pronargs>0 THEN
      FOR i IN 1..r.pronargs LOOP
        v_call:=v_call||CASE WHEN i>1 THEN ',' ELSE '' END||'$'||i;
      END LOOP;
    END IF;
    EXECUTE format('ALTER FUNCTION %s SET SCHEMA private',r.signature);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION private.%I(%s) FROM PUBLIC, anon',r.proname,
      (SELECT string_agg(format_type(t,NULL),',' ORDER BY ord)
         FROM unnest((SELECT proargtypes::oid[] FROM pg_proc WHERE proname=r.proname AND pronamespace='private'::regnamespace))
              WITH ORDINALITY x(t,ord)));
    EXECUTE format('GRANT EXECUTE ON FUNCTION private.%I(%s) TO authenticated',r.proname,
      (SELECT string_agg(format_type(t,NULL),',' ORDER BY ord)
         FROM unnest((SELECT proargtypes::oid[] FROM pg_proc WHERE proname=r.proname AND pronamespace='private'::regnamespace))
              WITH ORDINALITY x(t,ord)));
    v_sql:=format(
      'CREATE OR REPLACE FUNCTION public.%I(%s) RETURNS %s LANGUAGE sql SECURITY INVOKER SET search_path TO '''' AS %L',
      r.proname,v_args,v_result,'SELECT private.'||quote_ident(r.proname)||'('||v_call||')'
    );
    EXECUTE v_sql;
    EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM PUBLIC, anon',r.proname,
      (SELECT string_agg(format_type(t,NULL),',' ORDER BY ord)
         FROM unnest((SELECT proargtypes::oid[] FROM pg_proc WHERE proname=r.proname AND pronamespace='private'::regnamespace))
              WITH ORDINALITY x(t,ord)));
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated',r.proname,
      (SELECT string_agg(format_type(t,NULL),',' ORDER BY ord)
         FROM unnest((SELECT proargtypes::oid[] FROM pg_proc WHERE proname=r.proname AND pronamespace='private'::regnamespace))
              WITH ORDINALITY x(t,ord)));
  END LOOP;
END;
$secure_facade$;

DO $verify_facade$
BEGIN
 IF EXISTS (
   SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.prosecdef
     AND p.proname IN ('complete_organization_setup','create_organization','next_account_code',
       'post_expense','post_inventory_adjustment','post_journal_entry','post_payment','post_purchase',
       'post_purchase_return','post_sales','post_sales_return','reverse_expense','reverse_journal_entry',
       'reverse_payment','reverse_purchase_return','reverse_sales_return')
 ) THEN RAISE EXCEPTION 'A privileged workflow implementation remains in the exposed public schema'; END IF;
 IF NOT has_function_privilege('authenticated','public.reverse_purchase_return(uuid,uuid,date,text)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.reverse_sales_return(uuid,uuid,date,text)','EXECUTE') THEN
   RAISE EXCEPTION 'Authenticated RPC facade grants are missing';
 END IF;
END;
$verify_facade$;
COMMIT;

BEGIN;

CREATE OR REPLACE FUNCTION private.enforce_purchase_return_source_integrity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM public.purchase_items pi
      JOIN public.purchase_returns pr
        ON pr.organization_id=NEW.organization_id
       AND pr.id=NEW.purchase_return_id
     WHERE pi.organization_id=NEW.organization_id
       AND pi.id=NEW.purchase_item_id
       AND pi.purchase_id=pr.purchase_id
       AND pi.product_id=NEW.product_id
  ) THEN
    RAISE EXCEPTION 'Purchase return item must match its source purchase line and product'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION private.enforce_sales_return_source_integrity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM public.sales_items si
      JOIN public.sales_returns sr
        ON sr.organization_id=NEW.organization_id
       AND sr.id=NEW.sales_return_id
     WHERE si.organization_id=NEW.organization_id
       AND si.id=NEW.sales_item_id
       AND si.sales_id=sr.sales_id
       AND si.product_id=NEW.product_id
  ) THEN
    RAISE EXCEPTION 'Sales return item must match its source sales line and product'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS purchase_return_items_source_integrity ON public.purchase_return_items;
CREATE TRIGGER purchase_return_items_source_integrity
BEFORE INSERT OR UPDATE OF organization_id,purchase_return_id,purchase_item_id,product_id
ON public.purchase_return_items
FOR EACH ROW EXECUTE FUNCTION private.enforce_purchase_return_source_integrity();

DROP TRIGGER IF EXISTS sales_return_items_source_integrity ON public.sales_return_items;
CREATE TRIGGER sales_return_items_source_integrity
BEFORE INSERT OR UPDATE OF organization_id,sales_return_id,sales_item_id,product_id
ON public.sales_return_items
FOR EACH ROW EXECUTE FUNCTION private.enforce_sales_return_source_integrity();

COMMIT;
