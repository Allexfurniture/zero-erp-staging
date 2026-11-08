-- ZERO ERP V1: explicit organization ownership and immutable tenant scope.
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
