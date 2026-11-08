-- Cover the opening balance subledger account foreign key for joins/deletes.
CREATE INDEX IF NOT EXISTS opening_balance_items_account_idx
  ON public.opening_balance_items(organization_id,account_id);