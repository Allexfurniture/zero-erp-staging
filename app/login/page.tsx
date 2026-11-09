import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "../../lib/supabase/server";
import { signIn } from "../actions";

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string; check_email?: string; password_updated?: string }> }) {
  const params = await searchParams;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (user) redirect("/");

  return <main className="auth-page"><section className="auth-card">
    <div className="brand auth-brand"><span className="brand-mark">Z</span><span className="brand-copy"><strong>ZERO</strong><small>ERP WORKSPACE</small></span></div>
    <h1>Sign in</h1><p className="muted">Access your business workspace.</p>
    {params.error === "invalid" && <p className="form-error" role="alert">Email or password is incorrect.</p>}
    {params.error === "expired" && <p className="form-error" role="alert">Your password reset link has expired. Request a new one.</p>}
    {params.check_email && <p className="form-success" role="status">Check your email and confirm your address before signing in.</p>}
    {params.password_updated && <p className="form-success" role="status">Password updated. Sign in with your new password.</p>}
    <form action={signIn} className="auth-form">
      <label>Email address<input name="email" type="email" autoComplete="username" required /></label>
      <label>Password<input name="password" type="password" autoComplete="current-password" required /></label>
      <button className="primary-button" type="submit">Sign in</button>
    </form>
    <p className="auth-foot"><Link href="/forgot-password">Forgot password?</Link></p>
    <p className="auth-foot">New to ZERO ERP? <Link href="/signup">Create an account</Link></p>
  </section></main>;
}
