import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "../../lib/supabase/server";
import { signUp } from "../actions";

export default async function SignupPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (user) redirect("/");

  return <main className="auth-page"><section className="auth-card">
    <div className="brand auth-brand"><span className="brand-mark">Z</span><span className="brand-copy"><strong>ZERO</strong><small>ERP WORKSPACE</small></span></div>
    <h1>Create account</h1><p className="muted">Create a secure login for your business workspace.</p>
    {params.error && <p className="form-error" role="alert">Enter a valid email and a password with at least 8 characters.</p>}
    <form action={signUp} className="auth-form">
      <label>Email address<input name="email" type="email" autoComplete="email" required /></label>
      <label>Password<input name="password" type="password" autoComplete="new-password" minLength={8} required /></label>
      <button className="primary-button" type="submit">Create account</button>
    </form>
    <p className="auth-foot">Already registered? <Link href="/login">Sign in</Link></p>
  </section></main>;
}
