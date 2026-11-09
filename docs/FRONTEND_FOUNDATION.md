# ZERO ERP frontend foundation

## Product decisions
- Enterprise ERP visual direction
- Light theme only
- English interface

## Application foundation
The App Router dashboard provides the initial workspace shell: responsive primary navigation, workspace context, global search, notification affordance, reporting-period selector, KPI preview cards, revenue visualization, quick actions, and recent transaction preview.

## Data boundary
The dashboard currently uses explicitly labelled sample preview data. It does not read or write business records. This avoids presenting invented values as live accounting data while the tenant-aware Supabase integration is being implemented.

## Supabase configuration
Copy `.env.example` to `.env.local` and provide the project's public URL and anon/publishable key:
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`

Never expose a service-role key in browser code or a `NEXT_PUBLIC_*` variable.

## Next implementation sequence
1. Generate and commit database types from the isolated staging project.
2. Implement Supabase SSR clients and authenticated session handling.
3. Resolve the active organization from the authenticated user's memberships.
4. Replace preview dashboard values with tenant-scoped, RLS-protected reads.
5. Build each module using the existing database RPCs for accounting workflows and posting operations.

No database migrations, policies, triggers, functions, or production resources are modified by this frontend foundation.
