# Environment configuration

The Desktop checkout is `~/Desktop/merge-from-github`. `.env.local` is private local configuration and is ignored by Git. The pasted environment reference was saved there with owner-only permissions; a temporary `VERCEL_OIDC_TOKEN` was omitted. Do not commit or copy secrets into README files, screenshots, test fixtures, or issue descriptions.

## Development

Use a dedicated Supabase project, Stripe **test-mode** keys, and separate mail/Redis/shipping credentials. A file named `.env.local` does not make the services behind its keys local. The supplied Stripe key was identified as test mode; the Supabase keys have not been authenticated or established as development-only.

Minimum catalog/auth settings: `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`. Server order operations also require `SUPABASE_SERVICE_ROLE_KEY` and the database migrations. Local checkout requires `STRIPE_SECRET_KEY`, `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY`, and a test webhook secret. Point `NEXT_PUBLIC_SITE_URL` at the local origin when testing redirects.

Staff tools require `ADMIN_PASSWORD` and an independent random `ADMIN_SESSION_SECRET`. Keep the development server bound to localhost when using staff credentials: its non-production convenience sign-in route bypasses the password.

Mail, SMS, geocoding, and label purchasing are optional external integrations. Disable their credentials in automated tests so a test cannot notify a real customer or buy a label.

## Production requirements

- Apply and verify the reviewed database migrations before releasing code that calls their RPCs.
- Configure a dedicated Upstash Redis URL/token. Public sensitive endpoints and admin login fail closed without distributed limiting in production. The pasted configuration did not contain usable Redis values.
- Use matching Stripe live keys and the signing secret for the production webhook endpoint. Subscribe to payment and refund events listed in `DATABASE.md`.
- Set the production site URL and a separate long admin signing secret.
- Configure verified sending domains and the correct ship-from information before enabling notifications/labels.
- Keep provider/environment configuration outside Git and use Vercel's environment settings for each target environment. This change does not upload local settings to Vercel.

`npm run check:env` reports presence only; it does not prove credentials work. `npm run check:env:prod` additionally checks required production settings. Use `npm run ci` for tests/build with masked local integration settings.
