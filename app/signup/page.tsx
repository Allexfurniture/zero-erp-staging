import Link from "next/link";
import { signUp } from "../actions";

export default async function SignupPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const params = await searchParams;
  return <main className="auth-page"><section className="auth-card">
    <div className="brand auth-brand"><span className="brand-mark">Z</span><span className="brand-copy"><strong>ZERO</strong><small>ERP WORKSPACE</small></span></div>
    <h1>Create account</h1><p className="muted">Start with your secure workspace login.</p>
    {params.error && <p className="form-error">Could not create the account. Check the details or try another email.</p>}
    <form action={signUp} className="auth-form">
      <label>Email address<input name="email" type="email" autoComplete="email" required /></label>
      <label>Password<input name="password" type="password" autoComplete="new-password" required minLength={8} /></label>
      <button className="primary-button" type="submit">Create account</button>
    </form>
    <p className="auth-foot">Already registered? <Link href="/login">Sign in</Link></p>
  </section></main>;
}
