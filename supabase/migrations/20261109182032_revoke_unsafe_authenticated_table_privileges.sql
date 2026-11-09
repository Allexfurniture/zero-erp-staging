-- Remove table privileges that bypass RLS or allow untrusted DDL hooks.
-- Application DML remains governed by existing grants, RLS policies and triggers.
REVOKE TRUNCATE, TRIGGER, REFERENCES ON ALL TABLES IN SCHEMA public FROM authenticated;

-- Keep future public tables aligned with the same least-privilege baseline.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE TRUNCATE, TRIGGER, REFERENCES ON TABLES FROM authenticated;
