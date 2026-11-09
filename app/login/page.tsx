import Link from "next/link";
import { signIn } from "../actions";

export default function LoginPage() {
  return <main className="auth-page"><section className="auth-card">
    <div className="brand auth-brand"><span className="brand-mark">Z</span><span className="brand-copy"><strong>ZERO</strong><small>ERP WORKSPACE</small></span></div>
    <h1>Sign in</h1><p className="muted">Access your business workspace.</p>
    <form action={signIn} className="auth-form">
      <label>Email address<input name="email" type="email" autoComplete="email" required /></label>
      <label>Password<input name="password" type="password" autoComplete="current-password" required minLength={8} /></label>
      <button className="primary-button" type="submit">Sign in</button>
    </form>
    <p className="auth-foot">New to ZERO ERP? <Link href="/signup">Create an account</Link></p>
  </section></main>;
}
