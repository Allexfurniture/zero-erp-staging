# ZERO ERP canonical database migration notes

## Canonical migration

The repository now contains exactly one file in `supabase/migrations/`:

`20261109000000_zero_erp_canonical_initial_schema.sql`

This is a squashed, ordered replay of the ZERO ERP migration SQL retained in the repository. It includes the baseline schema, tenant ownership and RLS, accounting and inventory posting, returns, opening-balance subledger, control-account guards, reversals, and secure RPC facades.

The source migration markers are preserved in the file so each section can be traced to its source migration. The old individual migration files were removed from the active migrations directory after consolidation. Git history retains the prior commits.

The repository contained two migration-history entries not represented by separate source files: `zero_erp_return_source_integrity` and `zero_erp_inventory_adjustment_validation_fix`. Their resulting constraints and inventory-adjustment validation logic are present in the consolidated SQL via later retained migration content. The repository also contained a duplicate migration blob for the inventory-control-account fix; it was not replayed twice.

## Important migration-history warning

The live staging database still has its original 22 applied migration-history records. The repository now has one local migration file. This is intentional for a clean-install baseline, but the local and remote migration histories are no longer a direct one-to-one match.

- Use the canonical migration only to initialize a new, empty, dedicated ZERO ERP database.
- Do not run `supabase db push` against the existing staging or production database until migration history is explicitly reconciled.
- Do not apply the canonical migration to an already initialized database; its DDL is a fresh-install replay and is not an in-place upgrade.
- For existing environments, compare the live schema and reconcile migration history separately. Do not reset or drop existing data to make the histories match.

## Production safety

- The production project and the separate `allexfurniture` website database were not modified.
- No production migration has been applied.
- The canonical file is not a production upgrade script. Review and test it on a separate empty database before using it for a new installation.

## Staging verification

Before consolidation, all four SQL regression suites passed, including the return-reversal lifecycle and cross-tenant RLS/posting isolation tests. Security and health advisors reported no findings. The live staging database was inspected while creating the canonical file; it has 22 migration-history entries.

A clean-database replay of the single consolidated file has not yet been performed. Therefore the file is consolidated and repository-checked, but not yet certified as a clean-install replay.
