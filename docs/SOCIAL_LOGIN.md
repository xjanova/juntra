# Mobile social sign-in

The Android app uses Juntra's existing Thaiprompt identity provider in the
external browser. It does not embed provider credentials or collect social
passwords. Available buttons come from the server; Google is not shown until
it is configured and advertised by the provider bridge.

## API contract

All endpoints are under `/api/v1/auth/social`:

- `GET providers`: `data.providers` contains `{id, name}` objects for enabled
  providers. Unknown providers are ignored by the app.
- `POST start`: accepts `provider`, `code_challenge` (S256), `device: mobile`,
  and optional `referral_code`. Returns `data.{id,url,expires_in,poll_interval}`.
  The browser URL must have the same origin as the configured Juntra API.
- `POST poll`: accepts `id` and `code_verifier` in the JSON body. Returns
  `data.status`: `pending`, `authorized`, `cancelled`, `failed`, or `expired`.
  Only `authorized` with both a token and a valid `user.id` can sign in.
  The user object is identical to the password-login response.

The verifier is random for each attempt and stays in memory. Requests expire
after five minutes. Cancelling or leaving the login screen invalidates local
callbacks, so a late result cannot sign in. Killing the app requires a new
attempt. Tokens are written to secure storage before authenticated state is
published. Request bodies are excluded from debug HTTP logging.

## Browser return

The success page links to `juntra://auth/complete`. Android brings the existing
activity forward. Flutter deep-link routing is disabled because the link is a
wake-up signal, not an authentication result. Resuming triggers a server poll
using the original verifier; no credentials are accepted from the return URL.
Manually switching back to the app works too. Polling pauses while backgrounded.

## Rollout and device checks

Deploy the upstream fresh-provider OAuth bridge first, then Juntra's mobile
social-auth API and its database migration. Confirm `GET providers` advertises
the configured provider before testing the release APK. An older server returns
an unavailable/retry message and password sign-in remains usable.

The pending server changes are
[Thaiprompt PR #2704](https://github.com/xjanova/Thaiprompt-Affiliate/pull/2704)
and [Juntra PR #69](https://github.com/xjanova/juntraweb/pull/69). They do not
depend on parity PR #68. Merge and deployment require the owner's approval.
Run each migration in its own server checkout before enabling the new routes:

1. Thaiprompt, before Juntra:
   `php artisan migrate --path=database/migrations/2026_11_12_000001_add_social_binding_to_oauth_auth_codes.php --force`
2. Juntra:
   `php artisan migrate --path=database/migrations/2026_11_12_120000_create_social_login_requests_table.php --force`

Juntra's `APP_URL` must be its canonical HTTPS origin. Thai hostnames are
normalized to ASCII IDNA/punycode; invalid origins hide providers and reject
new requests. For staging, build the APK with
`--dart-define=JUNTRA_API_BASE=https://<staging-host>/api` so its trusted API
origin matches the server's returned browser URL. Google appears only when
configured and enabled upstream.

Before production rollout, verify real provider sign-in on staging and run
concurrent poll/callback checks with independent MySQL workers. The automated
server tests use mocked provider responses and SQLite; they do not establish
either of those results.

Test on Android: choose an advertised provider, finish the provider's own login,
return to Juntra, verify account identity and credit balance, then relaunch and
verify the session persists. Also test cancellation, an expired request, network
loss, and a browser with a different existing Juntra account. Real provider login
requires the account owner. iOS browser return is not implemented in this change.
