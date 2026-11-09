"use client";

import { useMemo, useState } from "react";

const groups = [
  { title: "WORKSPACE", links: [["Overview", "▦"]] },
  { title: "OPERATIONS", links: [["Sales", "↗"], ["Purchases", "▤"], ["Inventory", "▧"], ["Contacts", "♧"]] },
  { title: "FINANCE", links: [["Accounting", "◫"], ["Reports", "▥"]] },
];
const records = [
  ["INV-2026-0084", "Northstar Interiors", "Sales invoice", "09 Nov 2026", "৳ 184,500.00", "Posted", "NI"],
  ["PUR-2026-0041", "Metro Timber Co.", "Purchase", "09 Nov 2026", "৳ 92,000.00", "Pending", "MT"],
  ["INV-2026-0083", "Urban Living Ltd.", "Sales invoice", "08 Nov 2026", "৳ 76,800.00", "Posted", "UL"],
  ["EXP-2026-0019", "Office & Utilities", "Expense", "08 Nov 2026", "৳ 18,250.00", "Draft", "OU"],
];
const bars = [34,47,39,58,48,67,53,74,61,82,69,91];

export default function Dashboard() {
  const [active, setActive] = useState("Overview");
  const [query, setQuery] = useState("");
  const [period, setPeriod] = useState("Last 30 days");
  const [menuOpen, setMenuOpen] = useState(false);
  const [notifications, setNotifications] = useState(false);
  const filtered = useMemo(() => records.filter((r) => r.join(" ").toLowerCase().includes(query.toLowerCase())), [query]);

  return <main className="erp-shell">
    {menuOpen && <button className="mobile-scrim" aria-label="Close navigation" onClick={() => setMenuOpen(false)} />}
    <aside className={`sidebar ${menuOpen ? "sidebar-open" : ""}`}>
      <div className="brand"><div className="brand-mark">Z</div><div className="brand-copy"><strong>ZERO</strong><span>ENTERPRISE</span></div><button className="sidebar-close" onClick={() => setMenuOpen(false)}>×</button></div>
      <button className="workspace-switcher"><span className="workspace-avatar">▦</span><span className="workspace-copy"><strong>Allex Furniture</strong><small>Business workspace</small></span><span>⌄</span></button>
      <nav aria-label="Main navigation">{groups.map((g) => <div className="nav-group" key={g.title}><p className="nav-heading">{g.title}</p>{g.links.map(([name, glyph]) => <button key={name} onClick={() => {setActive(name);setMenuOpen(false);}} className={`nav-link ${active === name ? "nav-link-active" : ""}`}><span className="nav-glyph">{glyph}</span>{name}</button>)}</div>)}</nav>
      <div className="sidebar-bottom"><button className={`nav-link ${active === "Settings" ? "nav-link-active" : ""}`} onClick={() => setActive("Settings")}><span className="nav-glyph">⚙</span>Settings</button><button className="nav-link" onClick={() => setActive("Help & support")}><span className="nav-glyph">?</span>Help & support</button><div className="sidebar-profile"><div className="profile-avatar">FA</div><div className="profile-copy"><strong>Finance Admin</strong><small>Administrator</small></div><span>···</span></div><div className="sidebar-version">ZERO ERP <span>v1.0.0</span></div></div>
    </aside>
    <section className="main-panel">
      <header className="topbar"><div className="topbar-left"><button className="mobile-menu" onClick={() => setMenuOpen(true)}>☰</button><div className="breadcrumb"><span>Workspace</span><span>/</span><strong>{active}</strong></div></div><div className="topbar-actions"><label className="global-search"><span>⌕</span><input placeholder="Search anything..." aria-label="Search transactions" value={query} onChange={(e) => setQuery(e.target.value)} /><kbd>⌘ K</kbd></label><div className="notification-wrap"><button className="icon-button" aria-label="Notifications" onClick={() => setNotifications(!notifications)}>♧<i /></button>{notifications && <div className="notification-popover"><strong>Notifications</strong><p>You’re all caught up.</p><small>New activity will appear here.</small></div>}</div><div className="topbar-divider" /><button className="topbar-user"><span className="profile-avatar">FA</span><span><strong>Finance Admin</strong><small>Administrator</small></span><span>⌄</span></button></div></header>
      <div className="page-content">
        <div className="page-heading"><div><div className="eyebrow">MONDAY, 09 NOVEMBER 2026</div><h1>{active === "Overview" ? "Good morning, Finance Admin" : active}</h1><p>{active === "Overview" ? "Here’s what’s happening across your business today." : `Your ${active.toLowerCase()} workspace is ready for implementation.`}</p></div><div className="heading-actions"><label className="period-select">▦ <select aria-label="Reporting period" value={period} onChange={(e) => setPeriod(e.target.value)}><option>Last 7 days</option><option>Last 30 days</option><option>This quarter</option><option>This year</option></select>⌄</label><button className="primary-button" onClick={() => setActive("Sales")}>＋ Create new</button></div></div>
        <div className="notice-strip"><i /><span><strong>Workspace preview</strong> — Sample figures are shown while live organization data is connected.</span><button onClick={() => setActive("Settings")}>Configure workspace ↗</button></div>
        <section className="metrics-grid">
          <article className="metric-card"><div className="metric-top"><span>Total revenue</span><b className="metric-icon revenue">৳</b></div><div className="metric-value">৳ 8,42,650</div><div className="metric-foot"><strong className="trend-positive">↗ 12.8%</strong><span>vs. previous period</span></div><div className="metric-spark spark-violet">{[28,45,36,57,43,67,56,82].map((v,i)=><i key={i} style={{height:v+"%"}} />)}</div></article>
          <article className="metric-card"><div className="metric-top"><span>Outstanding receivables</span><b className="metric-icon receivable">▤</b></div><div className="metric-value">৳ 2,18,400</div><div className="metric-foot"><strong className="trend-positive">↘ 4.2%</strong><span>vs. previous period</span></div><div className="metric-spark spark-blue">{[55,44,62,39,57,48,69,53].map((v,i)=><i key={i} style={{height:v+"%"}} />)}</div></article>
          <article className="metric-card"><div className="metric-top"><span>Inventory value</span><b className="metric-icon inventory">▧</b></div><div className="metric-value">৳ 12,64,800</div><div className="metric-foot"><strong className="trend-neutral">Stable</strong><span>across active products</span></div><div className="metric-spark spark-green">{[42,51,47,60,55,67,62,72].map((v,i)=><i key={i} style={{height:v+"%"}} />)}</div></article>
          <article className="metric-card"><div className="metric-top"><span>Operating expenses</span><b className="metric-icon expense">◫</b></div><div className="metric-value">৳ 96,250</div><div className="metric-foot"><strong className="trend-warning">↗ 3.1%</strong><span>vs. previous period</span></div><div className="metric-spark spark-amber">{[38,45,41,58,49,65,57,75].map((v,i)=><i key={i} style={{height:v+"%"}} />)}</div></article>
        </section>
        <section className="dashboard-grid">
          <article className="panel revenue-panel"><div className="panel-heading"><div><h2>Revenue overview</h2><p>Revenue performance over time</p></div><button className="subtle-button">Monthly⌄</button></div><div className="chart-summary"><strong>৳ 8,42,650</strong><span className="trend-positive">↗ 12.8%</span><small>compared to previous period</small></div><div className="chart-area"><div className="chart-y-labels"><span>৳ 10L</span><span>৳ 7.5L</span><span>৳ 5L</span><span>৳ 2.5L</span><span>৳ 0</span></div><div className="chart-plot"><div className="chart-gridlines">{[1,2,3,4,5].map(x=><i key={x}/>)}</div><div className="bar-list">{bars.map((h,i)=><div className="bar-column" key={i}><div className={`bar ${i===9?"bar-highlight":""}`} style={{height:h+"%"}} /></div>)}</div></div></div><div className="chart-x-labels"><span>01 Nov</span><span>04 Nov</span><span>07 Nov</span><span>09 Nov</span><span>12 Nov</span><span>15 Nov</span><span>18 Nov</span><span>21 Nov</span><span>24 Nov</span><span>27 Nov</span><span>30 Nov</span></div></article>
          <article className="panel activity-panel"><div className="panel-heading"><div><h2>Quick actions</h2><p>Common tasks, one click away</p></div><button className="icon-button">···</button></div><div className="quick-actions">{[["New sales invoice","Create a customer invoice","▣","quick-violet","Sales"],["Record a purchase","Add supplier purchases","▤","quick-blue","Purchases"],["Inventory adjustment","Update stock quantities","▧","quick-green","Inventory"],["Journal entry","Record an accounting entry","◫","quick-amber","Accounting"]].map(([title,sub,glyph,tone,target])=><button key={title} onClick={()=>setActive(target)}><span className={`quick-icon ${tone}`}>{glyph}</span><span><strong>{title}</strong><small>{sub}</small></span><span className="quick-arrow">↗</span></button>)}</div></article>
        </section>
        <section className="panel transactions-panel"><div className="panel-heading transactions-heading"><div><h2>Recent transactions</h2><p>Your latest business activity at a glance</p></div><div className="table-actions"><button className="subtle-button">☷ Filter</button><button className="subtle-button" onClick={()=>setActive("Reports")}>View all ↗</button></div></div><div className="table-wrap"><table><thead><tr><th>REFERENCE</th><th>CONTACT / DESCRIPTION</th><th>TYPE</th><th>DATE</th><th>AMOUNT</th><th>STATUS</th><th /></tr></thead><tbody>{filtered.map((r)=><tr key={r[0]}><td className="reference-cell">{r[0]}</td><td><div className="party-cell"><span className="party-avatar">{r[6]}</span><strong>{r[1]}</strong></div></td><td>{r[2]}</td><td>{r[3]}</td><td className="amount-cell">{r[4]}</td><td><span className={`status-pill status-${r[5].toLowerCase()}`}><i/>{r[5]}</span></td><td><button className="row-more" aria-label={`More options for ${r[0]}`}>···</button></td></tr>)}</tbody></table>{filtered.length===0&&<div className="empty-state">No sample transactions match “{query}”.</div>}</div><div className="table-footer"><span>Showing <strong>{filtered.length}</strong> of <strong>{records.length}</strong> sample transactions</span><button onClick={()=>setQuery("")}>Clear search</button></div></section>
        <footer className="page-footer"><span>© 2026 ZERO ERP. All rights reserved.</span><span><i/> All systems operational <b>·</b> Last synced just now</span></footer>
      </div>
    </section>
  </main>;
}
