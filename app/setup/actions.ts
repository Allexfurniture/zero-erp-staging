"use server";

import { redirect } from "next/navigation";
import { createClient } from "../../lib/supabase/server";

const text = (form: FormData, key: string) => String(form.get(key) ?? "").trim();
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const datePattern = /^\d{4}-\d{2}-\d{2}$/;
const amount4 = /^\d+(?:\.\d{1,4})?$/;
const amount6 = /^\d+(?:\.\d{1,6})?$/;

async function requireSetupOwner(organizationId: string) {
  if (!uuidPattern.test(organizationId)) redirect("/setup?error=permission");
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: organization } = await supabase
    .from("organizations")
    .select("id,status,owner_user_id")
    .eq("id", organizationId)
    .maybeSingle();

  if (!organization || organization.status !== "configuring" || organization.owner_user_id !== user.id) {
    redirect("/setup?error=permission");
  }
  return { supabase, user };
}

function parseArray(form: FormData, key: string): unknown[] {
  try {
    const value = JSON.parse(text(form, key) || "[]");
    return Array.isArray(value) ? value : [];
  } catch {
    return [];
  }
}

function validLines(value: unknown[]) {
  if (value.length > 500) return false;
  return value.every((item) => {
    if (!item || typeof item !== "object") return false;
    const line = item as Record<string, unknown>;
    return typeof line.account_id === "string"
      && uuidPattern.test(line.account_id)
      && typeof line.debit === "string" && amount4.test(line.debit)
      && typeof line.credit === "string" && amount4.test(line.credit)
      && (line.contact_id === null || (typeof line.contact_id === "string" && uuidPattern.test(line.contact_id)))
      && (line.description === null || typeof line.description === "string");
  });
}

function validInventory(value: unknown[]) {
  if (value.length > 500) return false;
  return value.every((item) => {
    if (!item || typeof item !== "object") return false;
    const line = item as Record<string, unknown>;
    return typeof line.product_id === "string"
      && uuidPattern.test(line.product_id)
      && typeof line.quantity === "string" && amount6.test(line.quantity) && Number(line.quantity) > 0
      && typeof line.unit_cost === "string" && amount6.test(line.unit_cost);
  });
}

function setupError(message: string) {
  const value = message.toLowerCase();
  if (value.includes("inventory asset debit")) return "inventory_mismatch";
  if (value.includes("zero-inventory")) return "zero_inventory";
  if (value.includes("opening journal must")) return "journal_unbalanced";
  if (value.includes("contact")) return "contact";
  if (value.includes("creator") || value.includes("authorized")) return "permission";
  return "setup_failed";
}

export async function saveOpeningBalanceDraft(form: FormData) {
  const organizationId = text(form, "organization_id");
  const { supabase } = await requireSetupOwner(organizationId);
  const entryDate = text(form, "entry_date");
  const description = text(form, "description");
  const lines = parseArray(form, "lines");
  const inventoryItems = parseArray(form, "inventory_items");
  const intent = text(form, "intent");

  if (!datePattern.test(entryDate) || !validLines(lines) || !validInventory(inventoryItems)) {
    redirect("/setup?error=invalid_input");
  }

  const { error: saveError } = await supabase.rpc("save_opening_balance_draft", {
    p_organization_id: organizationId,
    p_entry_date: entryDate,
    p_description: description || null,
    p_lines: lines,
  });
  if (saveError) redirect("/setup?error=balances");

  if (intent !== "complete") redirect("/setup?saved=1");

  const confirmZeroInventory = text(form, "confirm_zero_inventory") === "true";
  const { error: completeError } = await supabase.rpc("complete_organization_setup", {
    p_organization_id: organizationId,
    p_inventory_items: inventoryItems,
    p_confirm_zero_inventory: confirmZeroInventory,
  });
  if (completeError) redirect(`/setup?error=${setupError(completeError.message)}`);

  redirect("/");
}

export async function createSetupContact(form: FormData) {
  const organizationId = text(form, "organization_id");
  const { supabase, user } = await requireSetupOwner(organizationId);
  const name = text(form, "name");
  const phone = text(form, "phone");
  const email = text(form, "email").toLowerCase();
  if (!name || name.length > 160 || phone.length > 40 || email.length > 320) {
    redirect("/setup?error=contact_input");
  }

  const { data: code, error: codeError } = await supabase.rpc("next_document_number", {
    p_organization_id: organizationId,
    p_document_type: "contacts",
  });
  if (codeError || !code) redirect("/setup?error=contact_create");

  const { error } = await supabase.from("contacts").insert({
    organization_id: organizationId,
    code,
    name,
    phone: phone || null,
    email: email || null,
    status: "active",
    created_by: user.id,
  });
  if (error) redirect("/setup?error=contact_create");
  redirect("/setup?created=contact");
}

export async function createSetupUnit(form: FormData) {
  const organizationId = text(form, "organization_id");
  const { supabase, user } = await requireSetupOwner(organizationId);
  const name = text(form, "name");
  if (!name || name.length > 80) redirect("/setup?error=unit_input");

  const { error } = await supabase.from("units_of_measure").insert({
    organization_id: organizationId,
    name,
    status: "active",
    created_by: user.id,
  });
  if (error) redirect("/setup?error=unit_create");
  redirect("/setup?created=unit");
}

export async function createSetupProduct(form: FormData) {
  const organizationId = text(form, "organization_id");
  const { supabase, user } = await requireSetupOwner(organizationId);
  const name = text(form, "name");
  const unitId = text(form, "unit_id");
  if (!name || name.length > 160 || !uuidPattern.test(unitId)) {
    redirect("/setup?error=product_input");
  }

  const [{ data: unit }, { data: accounts, error: accountError }] = await Promise.all([
    supabase.from("units_of_measure").select("id").eq("organization_id", organizationId).eq("id", unitId).eq("status", "active").maybeSingle(),
    supabase.from("accounts").select("id,code").eq("organization_id", organizationId).eq("status", "active").eq("is_postable", true).in("code", ["1140", "4100", "5100"]),
  ]);
  if (!unit || accountError || !accounts) redirect("/setup?error=product_accounts");

  const inventoryAccount = accounts.find((account) => account.code === "1140");
  const salesAccount = accounts.find((account) => account.code === "4100");
  const cogsAccount = accounts.find((account) => account.code === "5100");
  if (!inventoryAccount || !salesAccount || !cogsAccount) redirect("/setup?error=product_accounts");

  const { data: code, error: codeError } = await supabase.rpc("next_document_number", {
    p_organization_id: organizationId,
    p_document_type: "products",
  });
  if (codeError || !code) redirect("/setup?error=product_create");

  const { error } = await supabase.from("products").insert({
    organization_id: organizationId,
    code,
    name,
    unit_id: unitId,
    inventory_account_id: inventoryAccount.id,
    sales_account_id: salesAccount.id,
    cogs_account_id: cogsAccount.id,
    status: true,
    created_by: user.id,
  });
  if (error) redirect("/setup?error=product_create");
  redirect("/setup?created=product");
}
