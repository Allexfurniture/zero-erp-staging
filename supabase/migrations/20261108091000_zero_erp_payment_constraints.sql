-- Constrain payment vocabulary and allocation identity.
BEGIN;
ALTER TABLE public.payments
  ADD CONSTRAINT payments_payment_type_check CHECK (payment_type IN ('receipt','payment'));
ALTER TABLE public.payment_allocations
  ADD CONSTRAINT payment_allocations_document_type_check CHECK (document_type IN ('sales','purchase'));
CREATE UNIQUE INDEX payment_allocations_one_invoice_per_payment_uidx
  ON public.payment_allocations(organization_id,payment_id,document_type,document_id);
COMMIT;