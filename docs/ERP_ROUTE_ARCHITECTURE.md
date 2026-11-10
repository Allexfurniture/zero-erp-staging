# ZERO ERP — Database-Grounded Module & Route Architecture

**Status:** Proposed canonical frontend information architecture  
**Source of truth:** Inspected staging database `klvudsdllwgbakgdingg` and active branch `feat/enterprise-frontend-foundation`  
**Inspection mode:** Read-only. No database objects or application routes were changed as part of the inspection.

## 1. Architecture rules

1. Database tables, constraints, RLS policies, triggers and RPCs define what the UI may do.
2. Every tenant-owned read and write must resolve the active organization on the server and rely on RLS as a second enforcement layer.
3. Use plural, lowercase resource paths. Use UUID primary keys for internal detail routes; display document codes in the UI, not as route identifiers, because draft document codes may be null.
4. Use query parameters for list filters, not for identity or authorization: `?status=draft`, `?type=receipt`, `?from=YYYY-MM-DD&to=YYYY-MM-DD`, `?q=...`, `?page=2`.
5. A posted document is read-only. Use only the matching database posting/reversal RPCs. Do not expose direct ledger writes.
6. Do not add menus for schema concepts that do not exist (for example Contact Type, Product Category, Warehouses, Tax Setup, or Role Management).
7. Keep list, detail and form pages light and data-dense. Tabs belong inside a detail page unless a subresource has its own meaningful workflow.

## 2. Main navigation

| Order | Module | Database basis | Navigation contents |
|---|---|---|---|
| 1 | Dashboard | organizations, organization_users, sales, purchase, expenses, contacts, products, inventory_balances, accounts | Operational overview |
| 2 | Contacts | contacts and contact_id references in transactions/ledger | All Contacts, Contact Ledger |
| 3 | Sales | sales, sales_items, sales_returns, sales_return_items | Sales, Sales Returns |
| 4 | Purchases | purchase, purchase_items, purchase_returns, purchase_return_items | Purchases, Purchase Returns |
| 5 | Inventory | products, units_of_measure, inventory_balances, inventory_transactions | Products, Stock, Stock Movements, Adjustments, Units |
| 6 | Expenses | expenses, expense_categories | Expenses, Expense Categories |
| 7 | Payments | payments, payment_allocations | Payments & Receipts, Allocations |
| 8 | Accounting | accounts, journal_entries, account_transactions, opening_balance_items | Chart of Accounts, Journal Entries, Opening Balances, Reversals |
| 9 | Reports | derived from posted source documents and ledger tables | Financial, Sales, Purchase, Expense, Inventory, Receivable/Payable, Allocation reports |
| 10 | Settings | organizations, organization_users, number_sequences | Organization, Team (membership view only until role/invitation support exists) |

**Explicitly excluded:** “Master Data” as a top-level module; separate Customer and Supplier modules; a separate top-level Products module. Contacts is an independent identity module. Products belong under Inventory. A Contact can be selected in sales, purchase, payments, expenses and accounting without being assigned a permanent customer/supplier type.

## 3. Canonical route tree

### Public and workspace entry

| URL | Page / behavior |
|---|---|
| `/` | Redirect to `/dashboard` after authentication |
| `/login` | Sign in |
| `/signup` | Registration |
| `/forgot-password` | Request password reset |
| `/reset-password` | Set a new password |
| `/auth/callback` | Auth callback handler; not a navigation page |
| `/dashboard` | Active organization dashboard |
| `/organizations` | Organization chooser when the user has multiple memberships |
| `/setup` | Creator-only initial organization setup while status is `configuring` |

There is no organization slug column. Do not invent `/org/[slug]` routes. Resolve the organization from a server-verified active membership; if multiple organizations exist, use a server-validated organization selection. Never trust an organization ID from a query string as authorization.

### Contacts

| URL | Page / behavior |
|---|---|
| `/contacts` | Contact register; search and active/inactive filters |
| `/contacts/new` | Create one identity |
| `/contacts/[contactId]` | Contact profile and transaction summary |
| `/contacts/[contactId]/ledger` | Contact-linked account transaction ledger |

Contact profile tabs can show Sales, Purchases, Receipts/Payments and Expenses where those records reference the same Contact ID. Do not store or display a permanent Customer/Supplier type.

### Sales

| URL | Page / behavior |
|---|---|
| `/sales` | Sales register |
| `/sales/new` | Draft sales invoice |
| `/sales/[saleId]` | Sales detail; draft edit, posted read-only |
| `/sales/returns` | Sales return register |
| `/sales/[saleId]/returns/new` | Create return against a specific posted sale |
| `/sales/returns/[returnId]` | Sales return detail |

A return requires a source sale and source sales lines. Keep the source-sale relationship explicit in the create route. Posting must use `post_sales` or `post_sales_return`.

### Purchases

| URL | Page / behavior |
|---|---|
| `/purchases` | Purchase register |
| `/purchases/new` | Draft purchase |
| `/purchases/[purchaseId]` | Purchase detail; draft edit, posted read-only |
| `/purchases/returns` | Purchase return register |
| `/purchases/[purchaseId]/returns/new` | Create return against a specific posted purchase |
| `/purchases/returns/[returnId]` | Purchase return detail |

A return requires a source purchase and source purchase lines. Posting must use `post_purchase` or `post_purchase_return`.

### Inventory

| URL | Page / behavior |
|---|---|
| `/inventory` | Inventory overview |
| `/inventory/products` | Product register |
| `/inventory/products/new` | Create product |
| `/inventory/products/[productId]` | Product profile and current stock |
| `/inventory/products/[productId]/ledger` | Product movement history |
| `/inventory/stock` | Current stock and valuation from `inventory_balances` |
| `/inventory/transactions` | Stock movement register from `inventory_transactions` |
| `/inventory/adjustments` | Adjustment history grouped by the adjustment journal reference |
| `/inventory/adjustments/new` | Post a controlled stock adjustment |
| `/inventory/adjustments/[journalEntryId]` | Adjustment journal and linked movement detail |
| `/inventory/units` | Units of measure list/create |

There is no adjustment header table. Adjustment posting is an atomic `post_inventory_adjustment` RPC that creates journal and inventory ledger effects. The adjustment detail route is therefore keyed by its journal entry ID. Inventory balances and transactions are read-only to application users; never write them directly. Moving-average cost is maintained by database workflows. Product code, unit and account mappings become immutable after inventory ledger activity.

There is no Product Category table; do not add category filters or category settings until a schema change is approved.

### Expenses

| URL | Page / behavior |
|---|---|
| `/expenses` | Expense register |
| `/expenses/new` | Draft expense |
| `/expenses/[expenseId]` | Expense detail |
| `/expenses/categories` | Expense category list and creator-managed configuration |

Expenses are single-amount documents linked to an expense category and optionally a Contact/payable account. Posting uses `post_expense`; reversal uses `reverse_expense`.

### Payments

| URL | Page / behavior |
|---|---|
| `/payments` | Combined receipt/payment register |
| `/payments/new?type=receipt` | Customer receipt workflow |
| `/payments/new?type=payment` | Supplier payment workflow |
| `/payments/[paymentId]` | Payment/receipt detail |
| `/payments/allocations` | Allocation overview across payments |
| `/payments/[paymentId]/allocations` | Allocate one draft payment to eligible documents |

The database stores both directions in `payments.payment_type` (`receipt` or `payment`). Allocation document types are constrained to `sales`, `purchase` and `opening_balance`. Allocation states (unallocated/partial/full) are derived from amounts; they are not stored statuses.

**Backend prerequisite:** there is no dedicated allocation/unallocation RPC and `payment_allocations.document_id` is polymorphic without a document foreign key. Before enabling allocation writes, add and test an atomic server-side workflow that validates organization, payment type, contact, control account, posted source document/opening balance, returns, remaining balance, duplicate allocation and concurrent allocation. The existing `post_payment` RPC revalidates the allocation set at posting time; it is not a substitute for safe allocation editing.

### Accounting

| URL | Page / behavior |
|---|---|
| `/accounting/accounts` | Chart of Accounts |
| `/accounting/accounts/new` | Create account (creator-only database policy) |
| `/accounting/accounts/[accountId]` | Account detail |
| `/accounting/accounts/[accountId]/ledger` | Account ledger |
| `/accounting/journals` | Journal register |
| `/accounting/journals/new` | Manual draft journal |
| `/accounting/journals/[journalId]` | Journal detail and lines |
| `/accounting/opening-balances` | Read-only opening-balance/subledger view after setup |
| `/accounting/reversals` | Reversal register derived from journal/source reversal metadata |

The canonical ledger is `account_transactions`; it is not a free-form UI write target. Journal posting uses `post_journal_entry`. Opening balances are entered only during creator-controlled `/setup`, saved through `save_opening_balance_draft`, and posted/activated through `complete_organization_setup`. The `opening_balance_items` table is a read-only materialized subledger for receivable/payable opening lines.

Referenced source journals must be reversed through their source workflow. Manual journal reversal uses `reverse_journal_entry`. Expense/payment/return reversal uses the matching source reversal RPC.

### Reports

| URL | Report source |
|---|---|
| `/reports/trial-balance` | Posted journal lines grouped by account |
| `/reports/profit-and-loss` | Posted income and expense account lines |
| `/reports/balance-sheet` | Posted asset, liability and equity account lines |
| `/reports/general-ledger` | Account transactions with account/date filters |
| `/reports/receivables` | Sales, sales returns, receipts/allocations and opening receivable items |
| `/reports/payables` | Purchases, purchase returns, payments/allocations and opening payable items |
| `/reports/sales` | Sales register and sales return data |
| `/reports/purchases` | Purchase register and purchase return data |
| `/reports/expenses` | Expense register/category summaries |
| `/reports/inventory/valuation` | Inventory balances |
| `/reports/inventory/movements` | Inventory transactions |
| `/reports/payment-allocations` | Payment allocations joined to their validated source documents |

No public/private views currently exist. Reports must be implemented as tenant-scoped read queries, include only posted accounting effects where appropriate, and explicitly account for reversals and returns. Do not present draft, voided or reversed source documents as posted activity.

### Settings

| URL | Page / behavior |
|---|---|
| `/settings/organization` | Organization profile (creator-controlled updates) |
| `/settings/team` | Organization membership list |

The membership table has status but no role/permission column and no invitation workflow. Therefore this route must not pretend to offer role-based access control or invitations. Document-number sequences are readable but have no authenticated write policy; do not expose an editable numbering settings page. Units and expense categories live in their functional modules, not in a generic master-data/settings area.

## 4. Route transitions and access rules

1. Unauthenticated request to a private route → `/login`.
2. Authenticated user with no organization → organization creation/selection flow.
3. Organization in `configuring` state → creator to `/setup`; non-creator cannot complete setup.
4. Setup completion requires a balanced opening journal (at least two lines), correct active/postable accounts, active Contacts for receivable/payable balances, and opening Inventory Asset debit equal to opening stock value; zero stock requires explicit confirmation.
5. Active organization → `/dashboard`.
6. Inactive organization → read-only/unavailable state; no operational create/post actions.
7. Draft documents can be edited/deleted only while draft and within organization scope. Posting is performed by the matching RPC.
8. Posted documents are immutable outside supported reversal workflows.
9. Do not expose a Void action yet: although several tables carry void metadata, the inspected public RPC set has no document-void workflow.
10. Every detail page must resolve its record by both the active `organization_id` and its UUID. Never fetch by UUID alone.

## 5. Database-backed capabilities not present

Do not add these as current modules/pages until schema and business workflows are designed and approved:

- Contact type/role master (Customer/Supplier); permanent type is not present.
- Product categories, variants, barcode/SKU metadata beyond the current product code.
- Multiple warehouses, locations or inter-warehouse transfers.
- Sales quotations/orders, delivery challans, purchase orders or GRN.
- Tax/VAT configuration or tax line model.
- Bank statement import/reconciliation.
- Payroll, fixed assets, manufacturing/BOM, project costing.
- Currency/exchange-rate model.
- Role/permission management and user invitation workflow.
- Editable document numbering.
- Dedicated allocation RPC/workflow.

## 6. Verified database constraints relevant to UI

- All 24 public tables have RLS enabled and policies.
- Anonymous role has no direct public-table privileges.
- Authenticated role lacks TRUNCATE, TRIGGER and REFERENCES privileges.
- Inventory ledger/balance and opening-balance subledger have SELECT-only RLS policies and workflow triggers block direct writes.
- Organization membership is checked through active `organization_users` rows; organization creator is checked through `organizations.owner_user_id`.
- Organization status transitions are restricted to the setup completion workflow; organization ownership and tenant scope are immutable.
- Account code/type/normal-balance/control-account definition cannot be changed after ledger or source-document use.
- Product code/unit/account mappings cannot be changed after inventory activity.
- Sales/purchase discount allocation is distributed deterministically to four decimal places by database helper functions.
- Sales COGS uses moving-average inventory cost; returns restore source-line cost and are capped by unreturned source quantities/values.
- Payment posting validates allocation direction, source document status, contact, control account, returns and previously posted allocations.

## 7. Inspection and verification notes

- Staging organization currently inspected is in `configuring` state. It has 13 accounts, 12 expense categories, 16 number sequences, and no operational documents, Contacts, Products or inventory ledger rows.
- Migration history contains the canonical initial schema plus the authenticated-privilege and opening-balance-draft migrations.
- The read-only `zero_erp_complete_test.sql` regression checks passed against staging.
- Supabase health advisor returned no findings.
- Security advisor returned one warning: Leaked Password Protection is disabled. Enable it in Supabase Auth password security settings.
- Performance advisor reported 32 unused indexes. The operational tables are mostly empty, so these indexes should not be dropped based on this early usage signal.
- This document defines navigation and route intent only. It does not claim that the listed pages have been implemented.
