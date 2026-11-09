import Link from "next/link";
import { requestPasswordReset } from "../actions";

export default async function ForgotPasswordPage({ searchParams }: { searchParams: Promise<{ sent?: string; error?: string }> }) {
  const params = await searchParams;
  return <main className="auth-page"><section className="auth-card">
    <div className="brand auth-brand"><span className="brand-mark">Z</span><span className="brand-copy"><strong>ZERO</strong><small>ERP WORKSPACE</small></span></div>
    <h1>Reset password</h1><p className="muted">Enter your account email. If it is registered, we will send a reset link.</p>
    {params.sent && <p className="form-success" role="status">If the account exists, a password reset email has been sent.</p>}
    {params.error && <p className="form-error" role="alert">Enter a valid email address.</p>}
    <form action={requestPasswordReset} className="auth-form">
      <label>Email address<input name="email" type="email" autoComplete="email" required /></label>
      <button className="primary-button" type="submit">Send reset link</button>
    </form>
    <p className="auth-foot"><Link href="/login">Back to sign in</Link></p>
  </section></main>;
}
