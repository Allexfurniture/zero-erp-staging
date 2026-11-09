import Link from "next/link";
import { signIn } from "../actions";

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string; registered?: string }> }) {
  const params = await searchParams;
  return <main className="auth-page"><section className="auth-card">
    <div className="brand auth-brand"><span className="brand-mark">Z</span><span className="brand-copy"><strong>ZERO</strong><small>ERP WORKSPACE</small></span></div>
    <h1>Sign in</h1><p className="muted">Access your business workspace.</p>
    {params.error && <p className="form-error">Email or password is incorrect. Please try again.</p>}
    {params.registered && <p className="form-success">Account created. Sign in to continue.</p>}
    <form action={signIn} className="auth-form">
      <label>Email address<input name="email" type="email" autoComplete="email" required /></label>
      <label>Password<input name="password" type="password" autoComplete="current-password" required minLength={8} /></label>
      <button className="primary-button" type="submit">Sign in</button>
    </form>
    <p className="auth-foot">New to ZERO ERP? <Link href="/signup">Create an account</Link></p>
  </section></main>;
}
