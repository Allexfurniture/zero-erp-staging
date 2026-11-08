# ZERO ERP staging-to-production migration notes

## Current staging branch

Branch: `fix/database-v1-hardening`

The current hardening work is committed to this branch. The newest ordered migrations are:

1. `20261108098000_zero_erp_return_reversals_and_rpc_grants.sql`
2. `20261108098100_zero_erp_secure_rpc_facade.sql`

The staging database has both changes applied and verified. The Supabase MCP migration history assigns remote version IDs independently of the local migration filename timestamps; do not assume the remote version strings will exactly match the filenames.

## Production safety

- The production project and the separate `allexfurniture` website database were not modified.
- Do not run the initial bootstrap migration against an existing/populated production database. It contains schema-drop/recreate operations intended only for an empty database.
- Do not run `supabase db push` blindly until production migration history has been reconciled with the repository and the production schema has been compared against the intended ZERO ERP baseline.
- Prepare a production rollout bundle from the intended baseline and the verified staging changes. Review every migration for destructive DDL and data assumptions before applying it.
- Apply the two latest migrations only after their prerequisites and migration-history state have been verified in the target database.

## Verification status on staging

- Database hardening smoke suite: passed.
- Real-life authenticated business lifecycle suite: passed.
- Control-account validation suite: passed.
- Purchase/sales return reversal lifecycle suite: passed.
- Cross-tenant RLS and posting authorization test: passed.
- Supabase security advisor: no findings.
- Supabase health advisor: no findings.

The remaining performance-advisor unused-index notices are informational on the lightly populated staging database. Foreign-key indexes were intentionally retained; lack of observed use in staging is not evidence that they should be dropped.
