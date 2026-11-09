import { redirect } from "next/navigation";
import { signOut } from "../actions";
import { createClient } from "../../lib/supabase/server";
import { createSetupContact, createSetupProduct, createSetupUnit } from "./actions";
import { OpeningBalanceEditor } from "./opening-balance-editor";

const errors: Record<string, string> = {
  permission: "Only the organization owner can complete setup.",
  invalid_input: "Review the opening balance fields and try again.",
  balances: "The opening journal could not be saved. Check account and contact assignments.",
  inventory_mismatch: "The Inventory Asset debit must equal the total opening stock value.",
  zero_inventory: "Confirm zero inventory or enter opening stock items.",
  journal_unbalanced: "The opening journal needs at least two lines and equal debit and credit totals.",
  contact: "Receivable and payable opening balances require an active contact.",
  setup_failed: "Organization setup could not be completed. Review the entries and try again.",
  contact_input: "Enter a contact name and valid contact details.",
  contact_create: "Could not create the contact. Check for duplicate codes or invalid details.",
  unit_input: "Enter a unit name.",
  unit_create: "Could not create the unit. The name may already exist.",
  product_input: "Enter a product name and select a unit.",
  product_accounts: "The default inventory, sales or cost-of-goods-sold accounts are unavailable.",
  product_create: "Could not create the product. Please try again.",
};

export default async function SetupPage({ searchParams }: { searchParams: Promise<{ error?: string; saved?: string; created?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: memberships } = await supabase
    .from("organization_users")
    .select("organization_id")
    .eq("user_id", user.id)
    .eq("status", "active");
  const ids = (memberships ?? []).map((row) => row.organization_id);
  const { data: organizations } = ids.length
    ? await supabase.from("organizations").select("id,name,status,owner_user_id").in("id", ids)
    : { data: [] };
  const organization = organizations?.find((item) => item.status === "configuring");

  if (!organization) return <main className="auth-page"><section className="auth-card">
    <h1>No setup is pending</h1><p className="muted">Your organization is either active or unavailable.</p>
    <a href="/">Return to workspace</a>
    <form action={signOut}><button className="text-button" type="submit">Sign out</button></form>
  </section></main>;

  const [{ data: accounts }, { data: contacts }, { data: units }, { data: products }, { data: journal }, { count: categoryCount }] = await Promise.all([
    supabase.from("accounts").select("id,code,account_name,is_postable").eq("organization_id", organization.id).eq("status", "active").order("code"),
    supabase.from("contacts").select("id,code,name").eq("organization_id", organization.id).eq("status", "active").order("name"),
    supabase.from("units_of_measure").select("id,name").eq("organization_id", organization.id).eq("status", "active").order("name"),
    supabase.from("products").select("id,code,name").eq("organization_id", organization.id).eq("status", true).order("name"),
    supabase.from("journal_entries").select("id,entry_date,description,status").eq("organization_id", organization.id).eq("entry_type", "opening_balance").maybeSingle(),
    supabase.from("expense_categories").select("id", { count: "exact", head: true }).eq("organization_id", organization.id),
  ]);

  const { data: journalLines } = journal
    ? await supabase.from("account_transactions").select("account_id,debit,credit,contact_id,description").eq("organization_id", organization.id).eq("journal_entry_id", journal.id).order("line_number")
    : { data: [] };

  const isOwner = organization.owner_user_id === user.id;
  const postableAccounts = (accounts ?? []).filter((account) => account.is_postable);
  const setupDate = journal?.entry_date ?? new Date().toISOString().slice(0, 10);
  const createdMessage = params.created === "contact" ? "Contact created."
    : params.created === "unit" ? "Unit created."
    : params.created === "product" ? "Product created."
    : null;

  return <main className="auth-page setup-page"><section className="setup-card setup-workspace">
    <div className="brand auth-brand"><span className="brand-mark">Z</span><span className="brand-copy"><strong>ZERO</strong><small>ERP WORKSPACE</small></span></div>
    <span className="eyebrow">ORGANIZATION SETUP</span>
    <h1>{organization.name}</h1>
    <p className="muted">Prepare opening balances and stock before activating this organization. ZERO ERP will not post incomplete or unbalanced opening entries.</p>

    {params.error && <p className="form-error" role="alert">{errors[params.error] ?? "Something went wrong. Review the form and try again."}</p>}
    {params.saved && <p className="form-success" role="status">Opening journal draft saved.</p>}
    {createdMessage && <p className="form-success" role="status">{createdMessage}</p>}

    <div className="setup-stats"><div><strong>{accounts?.length ?? 0}</strong><span>Accounts</span></div><div><strong>{categoryCount ?? 0}</strong><span>Expense categories</span></div><div><strong>{products?.length ?? 0}</strong><span>Products</span></div><div><strong>{contacts?.length ?? 0}</strong><span>Contacts</span></div></div>

    {!isOwner ? <div className="setup-note"><strong>Owner approval required</strong><p>Only the organization owner can add opening balances and activate this workspace. Ask the owner to complete setup.</p></div> : <>
      <section className="setup-master-section">
        <div className="setup-section-heading"><div><h2>Master data</h2><p>Add the contacts and products needed for opening balances</p></div></div>
        <div className="setup-master-grid">
          <section className="setup-master-card">
            <h3>New contact</h3>
            <p>Customers and suppliers for receivable and payable balances</p>
            <form action={createSetupContact} className="setup-mini-form">
              <input type="hidden" name="organization_id" value={organization.id} />
              <label>Name<input name="name" required maxLength={160} placeholder="Contact name" /></label>
              <div className="form-grid"><label>Phone<input name="phone" type="tel" maxLength={40} /></label><label>Email<input name="email" type="email" maxLength={320} /></label></div>
              <button className="secondary-button" type="submit">Add contact</button>
            </form>
          </section>
          <section className="setup-master-card">
            <h3>New unit</h3>
            <p>Units of measurement for inventory products</p>
            <form action={createSetupUnit} className="setup-mini-form">
              <input type="hidden" name="organization_id" value={organization.id} />
              <label>Unit name<input name="name" required maxLength={80} placeholder="e.g. Piece, Box, Kg" /></label>
              <button className="secondary-button" type="submit">Add unit</button>
            </form>
          </section>
          <section className="setup-master-card">
            <h3>New product</h3>
            <p>Uses the standard Inventory 1140, Sales 4100 and COGS 5100 accounts</p>
            <form action={createSetupProduct} className="setup-mini-form">
              <input type="hidden" name="organization_id" value={organization.id} />
              <label>Product name<input name="name" required maxLength={160} placeholder="Product name" /></label>
              <label>Unit<select name="unit_id" required disabled={!units?.length}><option value="">Select unit</option>{(units ?? []).map((unit) => <option key={unit.id} value={unit.id}>{unit.name}</option>)}</select></label>
              <button className="secondary-button" type="submit" disabled={!units?.length}>Add product</button>
              {!units?.length && <span className="setup-hint">Create a unit before adding products.</span>}
            </form>
          </section>
        </div>
      </section>

      <section className="setup-opening-section">
        <div className="setup-section-heading"><div><h2>Opening balances</h2><p>Enter the organization's balances as of the opening date</p></div></div>
        {journal?.status !== "draft" && journal ? <p className="setup-inline-note">An opening journal already exists in {journal.status} status. It cannot be edited here.</p> : (
          <OpeningBalanceEditor
            organizationId={organization.id}
            accounts={postableAccounts}
            contacts={contacts ?? []}
            products={products ?? []}
            initialLines={(journalLines ?? []) as { account_id: string; debit: number | string; credit: number | string; contact_id: string | null; description: string | null }[]}
            initialDate={setupDate}
            initialDescription={journal?.description ?? ""}
          />
        )}
      </section>
    </>}

    <div className="setup-bottom-row"><form action={signOut}><button className="text-button" type="submit">Sign out</button></form><span>ZERO ERP · Controlled setup</span></div>
  </section></main>;
}
