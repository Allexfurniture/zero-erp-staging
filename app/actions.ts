"use server";

import { redirect } from "next/navigation";
import { createClient } from "../lib/supabase/server";

const value = (form: FormData, key: string) => String(form.get(key) ?? "").trim();
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export async function signIn(form: FormData) {
  const email = value(form, "email").toLowerCase();
  const password = String(form.get("password") ?? "");
  if (!emailPattern.test(email) || !password) redirect("/login?error=invalid");

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) redirect("/login?error=invalid");
  redirect("/");
}

export async function signUp(form: FormData) {
  const email = value(form, "email").toLowerCase();
  const password = String(form.get("password") ?? "");
  if (!emailPattern.test(email) || password.length < 8) redirect("/signup?error=invalid");

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: { emailRedirectTo: `${process.env.NEXT_PUBLIC_SITE_URL ?? ""}/auth/callback?next=/` },
  });
  if (error) redirect("/signup?error=signup");
  if (data.session) redirect("/");
  redirect("/login?check_email=1");
}

export async function requestPasswordReset(form: FormData) {
  const email = value(form, "email").toLowerCase();
  if (!emailPattern.test(email)) redirect("/forgot-password?error=invalid");

  const supabase = await createClient();
  await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${process.env.NEXT_PUBLIC_SITE_URL ?? ""}/auth/callback?next=/reset-password`,
  });
  // Keep the response identical whether or not the address is registered.
  redirect("/forgot-password?sent=1");
}

export async function updatePassword(form: FormData) {
  const password = String(form.get("password") ?? "");
  const confirmation = String(form.get("confirm_password") ?? "");
  if (password.length < 8 || password !== confirmation) redirect("/reset-password?error=invalid");

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login?error=expired");

  const { error } = await supabase.auth.updateUser({ password });
  if (error) redirect("/reset-password?error=update");
  redirect("/login?password_updated=1");
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}

export async function createOrganization(form: FormData) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { error } = await supabase.rpc("create_organization", {
    p_name: value(form, "name"),
    p_phone: value(form, "phone") || null,
    p_email: value(form, "email") || null,
    p_address: value(form, "address") || null,
    p_tin: value(form, "tin") || null,
    p_bin: value(form, "bin") || null,
  });
  if (error) redirect("/?error=organization");
  redirect("/setup");
}
