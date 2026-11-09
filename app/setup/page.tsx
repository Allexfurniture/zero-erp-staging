import { redirect } from "next/navigation";
import { signOut } from "../actions";
import { createClient } from "../../lib/supabase/server";

export default async function SetupPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  const { data: memberships } = await supabase.from("organization_users").select("organization_id").eq("user_id", user.id).eq("status", "active");
  const ids = (memberships ?? []).map((row) => row.organization_id);
  const { data: organizations } = ids.length ? await supabase.from("organizations").select("id,name,status").in("id", ids) : { data: [] };
  const organization = organizations?.find((item) => item.status === "configuring");
  if (!organization) return <main className="auth-page"><section className="auth-card"><h1>No setup is pending</h1><p className="muted">Your organization is either active or unavailable.</p><a href="/">Return to workspace</a></section></main>;

  const [{ count: accountCount }, { count: categoryCount }, { count: productCount }, { count: contactCount }] = await Promise.all([
    supabase.from("accounts").select("id", { count: "exact", head: true }).eq("organization_id", organization.id),
    supabase.from("expense_categories").select("id", { count: "exact", head: true }).eq("organization_id", organization.id),
    supabase.from("products").select("id", { count: "exact", head: true }).eq("organization_id", organization.id),
    supabase.from("contacts").select("id", { count: "exact", head: true }).eq("organization_id", organization.id),
  ]);
  return <main className="auth-page"><section className="setup-card">
    <div className="brand auth-brand"><span className="brand-mark">Z</span><span className="brand-copy"><strong>ZERO</strong><small>ERP WORKSPACE</small></span></div>
    <span className="eyebrow">ORGANIZATION SETUP</span><h1>{organization.name}</h1>
    <p className="muted">The organization and its default chart of accounts are ready. Before transactions can be posted, opening balances and opening stock must be reconciled.</p>
    <div className="setup-stats"><div><strong>{accountCount ?? 0}</strong><span>Accounts</span></div><div><strong>{categoryCount ?? 0}</strong><span>Expense categories</span></div><div><strong>{productCount ?? 0}</strong><span>Products</span></div><div><strong>{contactCount ?? 0}</strong><span>Contacts</span></div></div>
    <div className="setup-note"><strong>Accounting control</strong><p>ZERO ERP will not activate this organization until its opening journal is balanced and the inventory value matches the opening stock quantities. No opening entries have been created automatically.</p></div>
    <form action={signOut}><button className="secondary-button" type="submit">Sign out</button></form>
  </section></main>;
}
