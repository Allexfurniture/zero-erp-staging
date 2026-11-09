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
- Configuring organizations are routed to a setup status screen.
- Active organization overview reads tenant-scoped counts, inventory valuation, and recent sales, purchases, and expenses from the live database.
- No service-role key is used by the application.

## Database workflow boundary
The canonical database requires a draft opening-balance journal with balanced account lines and opening stock reconciliation before `complete_organization_setup` can activate an organization. The current setup screen explains this gate and intentionally does not bypass it. The full opening-balance editor must be implemented against the exact RLS and trigger behavior before organizations can be activated from the UI.

## Environment
Set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` in the deployment environment. These are public project connection values; never add a service-role or secret key to a browser-exposed variable.

## Next implementation sequence
1. Implement the opening-balance and opening-stock editor using the existing schema and `complete_organization_setup` RPC.
2. Build contacts and product/UOM master-data screens.
3. Build sales, purchases, payments, expenses, journals, returns, and inventory workflows using the existing posting and reversal RPCs.
4. Add reports after validating accounting query definitions and tenant scoping.

No database schema, migration, RLS policy, trigger, RPC, or production resource was changed by this frontend work.
