"use client";

import { useMemo, useState } from "react";
import { saveOpeningBalanceDraft } from "./actions";

type Account = { id: string; code: string; account_name: string };
type Contact = { id: string; code: string; name: string };
type Product = { id: string; code: string; name: string };
type InitialLine = { account_id: string; debit: number | string; credit: number | string; contact_id: string | null; description: string | null };

type Line = { key: string; account_id: string; debit: string; credit: string; contact_id: string; description: string };
type StockLine = { key: string; product_id: string; quantity: string; unit_cost: string };

const newKey = () => crypto.randomUUID();
const round4 = (value: number) => Math.round((value + Number.EPSILON) * 10000) / 10000;
const money = (value: number) => new Intl.NumberFormat("en-BD", { minimumFractionDigits: 2, maximumFractionDigits: 4 }).format(value);

export function OpeningBalanceEditor({
  organizationId,
  accounts,
  contacts,
  products,
  initialLines,
  initialDate,
  initialDescription,
}: {
  organizationId: string;
  accounts: Account[];
  contacts: Contact[];
  products: Product[];
  initialLines: InitialLine[];
  initialDate: string;
  initialDescription: string;
}) {
  const [date, setDate] = useState(initialDate);
  const [description, setDescription] = useState(initialDescription);
  const [lines, setLines] = useState<Line[]>(initialLines.length
    ? initialLines.map((line) => ({
      key: newKey(),
      account_id: line.account_id,
      debit: String(line.debit ?? ""),
      credit: String(line.credit ?? ""),
      contact_id: line.contact_id ?? "",
      description: line.description ?? "",
    }))
    : [{ key: newKey(), account_id: "", debit: "", credit: "", contact_id: "", description: "" }]);
  const [stock, setStock] = useState<StockLine[]>([]);
  const [confirmZero, setConfirmZero] = useState(false);

  const updateLine = (key: string, patch: Partial<Line>) => setLines((current) => current.map((line) => line.key === key ? { ...line, ...patch } : line));
  const updateStock = (key: string, patch: Partial<StockLine>) => setStock((current) => current.map((line) => line.key === key ? { ...line, ...patch } : line));

  const selectedLines = useMemo(() => lines.filter((line) => line.account_id && (line.debit !== "" || line.credit !== "")).map(({ account_id, debit, credit, contact_id, description: lineDescription }) => ({
    account_id,
    debit: debit || "0",
    credit: credit || "0",
    contact_id: contact_id || null,
    description: lineDescription || null,
  })), [lines]);

  const selectedStock = useMemo(() => stock.filter((line) => line.product_id && line.quantity !== "").map(({ product_id, quantity, unit_cost }) => ({
    product_id,
    quantity,
    unit_cost: unit_cost || "0",
  })), [stock]);

  const debitTotal = selectedLines.reduce((sum, line) => sum + Number(line.debit), 0);
  const creditTotal = selectedLines.reduce((sum, line) => sum + Number(line.credit), 0);
  const inventoryValue = selectedStock.reduce((sum, line) => sum + Number(line.quantity) * Number(line.unit_cost), 0);
  const inventoryDebit = selectedLines.reduce((sum, line) => {
    const account = accounts.find((item) => item.id === line.account_id);
    return sum + (account?.code === "1140" ? Number(line.debit) : 0);
  }, 0);
  const balanced = selectedLines.length >= 2 && debitTotal > 0 && round4(debitTotal) === round4(creditTotal);
  const inventoryMatches = selectedStock.length
    ? round4(inventoryDebit) === round4(inventoryValue)
    : confirmZero && round4(inventoryDebit) === 0;
  const canComplete = balanced && inventoryMatches;

  return (
    <form action={saveOpeningBalanceDraft} className="opening-form">
      <input type="hidden" name="organization_id" value={organizationId} />
      <input type="hidden" name="lines" value={JSON.stringify(selectedLines)} />
      <input type="hidden" name="inventory_items" value={JSON.stringify(selectedStock)} />
      <input type="hidden" name="confirm_zero_inventory" value={confirmZero ? "true" : "false"} />

      <div className="setup-form-grid">
        <label>Opening balance date
          <input type="date" name="entry_date" value={date} onChange={(event) => setDate(event.target.value)} required />
        </label>
        <label>Reference / note
          <input type="text" name="description" value={description} onChange={(event) => setDescription(event.target.value)} maxLength={500} placeholder="Opening balances" />
        </label>
      </div>

      <div className="setup-section-heading">
        <div><h3>Opening journal</h3><p>Enter each account balance on its normal debit or credit side</p></div>
        <button type="button" className="small-button" onClick={() => setLines((current) => [...current, { key: newKey(), account_id: "", debit: "", credit: "", contact_id: "", description: "" }])}>Add line</button>
      </div>
      <div className="setup-table-wrap">
        <table className="setup-entry-table">
          <thead><tr><th>ACCOUNT</th><th>CONTACT</th><th>DEBIT (BDT)</th><th>CREDIT (BDT)</th><th>NOTE</th><th /></tr></thead>
          <tbody>
            {lines.map((line) => {
              const account = accounts.find((item) => item.id === line.account_id);
              const needsContact = account?.code === "1130" || account?.code === "2110";
              return (
                <tr key={line.key}>
                  <td><select value={line.account_id} onChange={(event) => updateLine(line.key, { account_id: event.target.value, contact_id: "", ...(accounts.find((item) => item.id === event.target.value)?.code === "1140" ? { credit: "" } : {}) })}>
                    <option value="">Select account</option>
                    {accounts.map((item) => <option key={item.id} value={item.id}>{item.code} · {item.account_name}</option>)}
                  </select></td>
                  <td>{needsContact ? <select value={line.contact_id} onChange={(event) => updateLine(line.key, { contact_id: event.target.value })} required>
                    <option value="">Select contact</option>
                    {contacts.map((item) => <option key={item.id} value={item.id}>{item.code} · {item.name}</option>)}
                  </select> : <span className="muted">—</span>}</td>
                  <td><input aria-label="Debit amount" type="number" min="0" step="0.0001" value={line.debit} onChange={(event) => updateLine(line.key, { debit: event.target.value, ...(account?.code === "1140" ? { credit: "" } : {}) })} /></td>
                  <td><input aria-label="Credit amount" type="number" min="0" step="0.0001" value={line.credit} disabled={account?.code === "1140"} onChange={(event) => updateLine(line.key, { credit: event.target.value })} /></td>
                  <td><input aria-label="Line note" value={line.description} onChange={(event) => updateLine(line.key, { description: event.target.value })} maxLength={250} /></td>
                  <td><button type="button" className="remove-line" aria-label="Remove line" onClick={() => setLines((current) => current.filter((item) => item.key !== line.key))}>×</button></td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <div className="setup-totals">
        <span>Debit <strong>{money(debitTotal)}</strong></span>
        <span>Credit <strong>{money(creditTotal)}</strong></span>
        <span className={balanced ? "balance-ok" : "balance-warning"}>{balanced ? "Balanced" : `Difference ${money(Math.abs(debitTotal - creditTotal))}`}</span>
      </div>

      <div className="setup-section-heading stock-heading">
        <div><h3>Opening stock</h3><p>Quantities and unit costs must reconcile to Inventory Asset account 1140</p></div>
        {products.length > 0 && <button type="button" className="small-button" onClick={() => setStock((current) => [...current, { key: newKey(), product_id: "", quantity: "", unit_cost: "" }])}>Add stock item</button>}
      </div>
      {products.length === 0 ? <p className="setup-inline-note">No active products yet. Add products above to record opening stock, or explicitly confirm zero inventory.</p> : (
        <div className="setup-table-wrap">
          <table className="setup-entry-table stock-table">
            <thead><tr><th>PRODUCT</th><th>QUANTITY</th><th>UNIT COST (BDT)</th><th>VALUE (BDT)</th><th /></tr></thead>
            <tbody>
              {stock.map((line) => (
                <tr key={line.key}>
                  <td><select value={line.product_id} onChange={(event) => updateStock(line.key, { product_id: event.target.value })}>
                    <option value="">Select product</option>
                    {products.map((item) => <option key={item.id} value={item.id}>{item.code} · {item.name}</option>)}
                  </select></td>
                  <td><input aria-label="Opening quantity" type="number" min="0.000001" step="0.000001" value={line.quantity} onChange={(event) => updateStock(line.key, { quantity: event.target.value })} /></td>
                  <td><input aria-label="Opening unit cost" type="number" min="0" step="0.000001" value={line.unit_cost} onChange={(event) => updateStock(line.key, { unit_cost: event.target.value })} /></td>
                  <td className="setup-number">{money(Number(line.quantity || 0) * Number(line.unit_cost || 0))}</td>
                  <td><button type="button" className="remove-line" aria-label="Remove stock item" onClick={() => setStock((current) => current.filter((item) => item.key !== line.key))}>×</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <div className="setup-totals">
        <span>Opening stock value <strong>{money(inventoryValue)}</strong></span>
        <span>Inventory Asset debit <strong>{money(inventoryDebit)}</strong></span>
        <span className={inventoryMatches ? "balance-ok" : "balance-warning"}>{inventoryMatches ? "Reconciled" : "Not reconciled"}</span>
      </div>
      <label className="zero-inventory-check">
        <input type="checkbox" checked={confirmZero} onChange={(event) => setConfirmZero(event.target.checked)} />
        Confirm that this organization starts with zero inventory
      </label>
      <div className="setup-submit-row">
        <button type="submit" name="intent" value="save" className="secondary-button">Save opening journal</button>
        <button type="submit" name="intent" value="complete" className="primary-button" disabled={!canComplete}>Complete organization setup</button>
      </div>
      {!canComplete && <p className="setup-hint">To activate the organization, the opening journal must balance and opening stock must reconcile (or zero inventory must be confirmed).</p>}
    </form>
  );
}
