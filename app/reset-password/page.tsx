import Link from "next/link";
import { createClient } from "../../lib/supabase/server";
import { updatePassword } from "../actions";

export default async function ResetPasswordPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return <main className="auth-page"><section className="auth-card"><h1>Reset link expired</h1><p className="muted">Request a new password reset link to continue.</p><Link href="/forgot-password">Request reset link</Link></section></main>;

  return <main className="auth-page"><section className="auth-card">
    <div className="brand auth-brand"><span className="brand-mark">Z</span><span className="brand-copy"><strong>ZERO</strong><small>ERP WORKSPACE</small></span></div>
    <h1>Choose a new password</h1><p className="muted">Use at least 8 characters.</p>
    {params.error && <p className="form-error" role="alert">Passwords must match and contain at least 8 characters.</p>}
    <form action={updatePassword} className="auth-form">
      <label>New password<input name="password" type="password" autoComplete="new-password" minLength={8} required /></label>
      <label>Confirm password<input name="confirm_password" type="password" autoComplete="new-password" minLength={8} required /></label>
      <button className="primary-button" type="submit">Update password</button>
    </form>
  </section></main>;
}
