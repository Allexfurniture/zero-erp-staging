import { redirect } from "next/navigation";
import { signOut, createOrganization } from "./actions";
import { createClient } from "../lib/supabase/server";

const money = (value: number | string | null) => new Intl.NumberFormat("en-BD", { style: "currency", currency: "BDT", maximumFractionDigits: 2 }).format(Number(value ?? 0));

export default async function Home() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: memberships } = await supabase.from("organization_users").select("organization_id").eq("user_id", user.id).eq("status", "active");
  const ids = (memberships ?? []).map((row) => row.organization_id);
  const { data: organizations } = ids.length ? await supabase.from("organizations").select("id,name,status").in("id", ids) : { data: [] };

  if (!organizations?.length) return <main className="auth-page"><section className="setup-card">
    <div className="brand auth-brand"><span className="brand-mark">Z</span><span className="brand-copy"><strong>ZERO</strong><small>ERP WORKSPACE</small></span></div>
    <h1>Create your organization</h1><p className="muted">Set up the legal business workspace. You can add opening balances and stock in the next step.</p>
    <form action={createOrganization} className="auth-form">
      <label>Organization name<input name="name" required maxLength={160} /></label>
      <label>Phone<input name="phone" type="tel" /></label>
      <label>Business email<input name="email" type="email" /></label>
      <label>Address<input name="address" /></label>
      <div className="form-grid"><label>TIN<input name="tin" /></label><label>BIN<input name="bin" /></label></div>
      <button className="primary-button" type="submit">Create organization</button>
    </form>
    <form action={signOut}><button className="text-button" type="submit">Sign out</button></form>
  </section></main>;

  if (organizations.some((org) => org.status === "configuring")) redirect("/setup");
  const organization = organizations.find((org) => org.status === "active") ?? organizations[0];
  if (!organization || organization.status !== "active") return <main className="auth-page"><section className="auth-card"><h1>Workspace unavailable</h1><p className="muted">Your organization is inactive. Contact its administrator.</p><form action={signOut}><button className="secondary-button">Sign out</button></form></section></main>;

  const orgId = organization.id;
  const [sales, purchases, expenses, contacts, products, inventory, accounts, recentSales, recentPurchases, recentExpenses] = await Promise.all([
    supabase.from("sales").select("id", { count: "exact", head: true }).eq("organization_id", orgId),
    supabase.from("purchase").select("id", { count: "exact", head: true }).eq("organization_id", orgId),
    supabase.from("expenses").select("id", { count: "exact", head: true }).eq("organization_id", orgId),
    supabase.from("contacts").select("id", { count: "exact", head: true }).eq("organization_id", orgId),
    supabase.from("products").select("id", { count: "exact", head: true }).eq("organization_id", orgId),
    supabase.from("inventory_balances").select("inventory_value").eq("organization_id", orgId),
    supabase.from("accounts").select("id", { count: "exact", head: true }).eq("organization_id", orgId),
    supabase.from("sales").select("id,code,invoice_date,total_amount,status").eq("organization_id", orgId).order("invoice_date", { ascending: false }).limit(6),
    supabase.from("purchase").select("id,code,invoice_date,total_amount,status").eq("organization_id", orgId).order("invoice_date", { ascending: false }).limit(6),
    supabase.from("expenses").select("id,code,expense_date,amount,status").eq("organization_id", orgId).order("expense_date", { ascending: false }).limit(6),
  ]);
  const rows = [
    ...(recentSales.data ?? []).map((r) => ({ id: r.id, code: r.code, date: r.invoice_date, amount: r.total_amount, status: r.status, type: "Sales" })),
    ...(recentPurchases.data ?? []).map((r) => ({ id: r.id, code: r.code, date: r.invoice_date, amount: r.total_amount, status: r.status, type: "Purchase" })),
    ...(recentExpenses.data ?? []).map((r) => ({ id: r.id, code: r.code, date: r.expense_date, amount: r.amount, status: r.status, type: "Expense" })),
  ].sort((a, b) => String(b.date).localeCompare(String(a.date))).slice(0, 10);
  const inventoryValue = (inventory.data ?? []).reduce((sum, row) => sum + Number(row.inventory_value ?? 0), 0);
  const metrics = [
    ["Sales documents", sales.count ?? 0], ["Purchases", purchases.count ?? 0],
    ["Expenses", expenses.count ?? 0], ["Contacts", contacts.count ?? 0],
    ["Products", products.count ?? 0], ["Accounts", accounts.count ?? 0],
  ];
  return <main className="erp-shell">
    <aside className="sidebar"><div className="brand"><span className="brand-mark">Z</span><span className="brand-copy"><strong>ZERO</strong><small>ERP WORKSPACE</small></span></div>
      <div className="workspace-switcher"><span className="workspace-avatar">▦</span><span className="workspace-copy"><strong>{organization.name}</strong><small>Active organization</small></span></div>
      <nav className="nav-list"><span className="nav-heading">WORKSPACE</span><a className="nav-link nav-link-active" href="/">Overview</a><span className="nav-heading">OPERATIONS</span><a className="nav-link" href="#transactions">Sales & purchases</a><a className="nav-link" href="#inventory">Inventory</a><a className="nav-link" href="#contacts">Contacts</a><span className="nav-heading">FINANCE</span><a className="nav-link" href="#accounts">Chart of accounts</a><a className="nav-link" href="#transactions">Expenses</a></nav>
      <div className="sidebar-bottom"><form action={signOut}><button className="nav-link" type="submit">Sign out · {user.email}</button></form><div className="sidebar-version">ZERO ERP <span>Live data</span></div></div>
    </aside>
    <section className="main-panel"><header className="topbar"><div className="breadcrumb"><span>Workspace</span><span>/</span><strong>Overview</strong></div><span className="user-label">{user.email}</span></header>
      <div className="page-content"><div className="page-heading"><div><span className="eyebrow">LIVE ORGANIZATION DATA</span><h1>{organization.name}</h1><p>Operational overview from your organization records.</p></div></div>
        <section className="metrics-grid">{metrics.map(([label, value]) => <article className="metric-card compact-metric" key={label}><span className="metric-label">{label}</span><strong className="metric-value">{value}</strong></article>)}</section>
        <section className="panel inventory-panel" id="inventory"><div className="panel-heading"><div><h2>Inventory valuation</h2><p>Current value from inventory balances</p></div><strong className="metric-value">{money(inventoryValue)}</strong></div></section>
        <section className="panel transactions-panel" id="transactions"><div className="panel-heading"><div><h2>Recent documents</h2><p>Latest sales, purchases and expenses</p></div><span className="live-label">Live · {rows.length}</span></div>
          <div className="table-wrap"><table><thead><tr><th>REFERENCE</th><th>TYPE</th><th>DATE</th><th>AMOUNT</th><th>STATUS</th></tr></thead><tbody>{rows.map((row) => <tr key={row.id}><td className="reference-cell">{row.code ?? "—"}</td><td>{row.type}</td><td>{row.date}</td><td className="amount-cell">{money(row.amount)}</td><td><span className="status-text">{row.status}</span></td></tr>)}</tbody></table>{!rows.length && <p className="empty-state">No transactions recorded yet.</p>}</div>
        </section>
        <footer className="page-footer"><span>ZERO ERP · {organization.name}</span><span>Tenant-scoped data · Supabase RLS</span></footer>
      </div>
    </section>
  </main>;
}
