-- ZERO ERP V1: move privileged workflow implementations behind invoker RPC facades.
BEGIN;
-- Move privileged workflow implementations out of the exposed API schema.
-- Public RPC names remain as SECURITY INVOKER facades; the private implementations
-- retain explicit auth.uid()/organization-membership checks.
GRANT USAGE ON SCHEMA private TO authenticated;
REVOKE USAGE ON SCHEMA private FROM anon;

DO $secure_facade$
DECLARE r record; v_args text; v_result text; v_call text; v_sql text; v_sig text; i integer;
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
