# ZERO ERP frontend foundation

## Product constraints
- Minimal, responsive, data-dense light UI.
- Server-rendered pages and native forms; avoid unnecessary client state and UI dependencies.
- No placeholder KPIs, sample transactions, fabricated identities, or fake system status.

## Implemented
- Supabase SSR server client with cookie-backed sessions.
- Next.js 16 proxy refreshes auth claims and rotates session cookies.
- Email/password sign-up and sign-in through Supabase Auth.
- Organization creation through the existing `create_organization` RPC.
- Organization membership resolution through `organization_users`.
- Configuring organizations are routed to a creator-only setup workspace.
- Setup supports contacts, units, products, an editable opening journal draft, opening stock valuation, and explicit zero-inventory confirmation.
- Opening journal drafts are saved atomically through a creator-authorized RPC; activation uses the existing balanced-journal and inventory-reconciliation RPC.
- Active organization overview reads tenant-scoped counts, inventory valuation, and recent sales, purchases, and expenses from the live database.
- No service-role key is used by the application.

## Database workflow boundary
The canonical database requires a draft opening-balance journal with at least two balanced lines, active contacts for receivable/payable control-account balances, and opening stock value reconciled to Inventory Asset account 1140 before `complete_organization_setup` can activate an organization. The setup UI writes the draft through `save_opening_balance_draft` and delegates final posting and stock-ledger creation to the existing completion RPC.

## Environment
Set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` in the deployment environment. These are public project connection values; never add a service-role or secret key to a browser-exposed variable.

## Next implementation sequence
1. Implement the opening-balance and opening-stock editor using the existing schema and `complete_organization_setup` RPC.
2. Build contacts and product/UOM master-data screens.
3. Build sales, purchases, payments, expenses, journals, returns, and inventory workflows using the existing posting and reversal RPCs.
4. Add reports after validating accounting query definitions and tenant scoping.

Staging-only additive migrations revoke unnecessary authenticated TRUNCATE/TRIGGER/REFERENCES privileges and add the atomic opening-balance draft RPC. Existing tables, accounting triggers, RLS policies and posting rules are preserved. The read-only regression gate is stored at `supabase/tests/zero_erp_complete_test.sql`; end-to-end posting tests still require isolated Auth fixtures.

## Authentication
- Password sign-in and registration use Supabase Auth from server actions.
- Registration uses email confirmation; the confirmation code is exchanged for a cookie-backed session at `/auth/callback`.
- Password recovery uses `resetPasswordForEmail`, callback exchange, and authenticated `updateUser({ password })`.
- Callback destinations are restricted to same-origin relative paths.
- Auth pages redirect an already-authenticated user to the workspace.
- Setup and workspace routes verify the current user server-side.
- Sign-in failures use a generic response; password-reset responses do not disclose whether an email is registered.

## Supabase Auth dashboard requirement
For the staging project, ensure Supabase Authentication > URL Configuration includes this exact Redirect URL:
`https://zero-erp-staging-git-fea-83f77a-allexfurniturebd-4719s-projects.vercel.app/auth/callback`
The Site URL should be the stable staging URL above. The Vercel Preview environment variable `NEXT_PUBLIC_SITE_URL` is scoped only to branch `feat/enterprise-frontend-foundation`; it does not change Production environment configuration.
