-- ZERO ERP V1: close direct sequence-consumption RPC.
-- Document numbers are allocated inside trusted posting/setup workflows.
-- Account code allocation remains available through next_account_code(), which
-- validates organization creator authority through next_document_number().
BEGIN;

REVOKE ALL ON FUNCTION public.next_document_number(uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.next_document_number(uuid,text) TO service_role;

COMMIT;
