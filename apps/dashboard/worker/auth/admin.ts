/**
 * Admin = email exactly in `ADMIN_EMAILS` (after trim + lowercase) and verified.
 * Empty `ADMIN_EMAILS` → no admins (fail closed).
 */
export function isAdmin(env: Pick<Env, "ADMIN_EMAILS">, user: { email: string; emailVerified: boolean }) {
  if (!user.emailVerified) return false;
  const email = user.email.trim().toLowerCase();
  return env.ADMIN_EMAILS.split(",").some((item) => {
    const admin = item.trim().toLowerCase();
    return admin !== "" && admin === email;
  });
}
