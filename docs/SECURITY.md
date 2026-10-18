# Security model and outstanding work

## Implemented controls

- Exact guest order-number/email lookup; no wildcard matching. Staff notes and actor names are omitted from tracking responses.
- Public signup cannot replace an existing password. The old email-confirmation bypass returns HTTP 410. Existing users recover access using verified email links.
- Production admin login throttling is enabled by default. Public signup, tracking, and checkout also use a distributed fixed-window limiter. Production without Redis fails closed.
- Profile role changes are restricted to the service role. Review inserts require authenticated ownership and `approved = false`.
- Service-role-only order and refund RPCs, with RLS/revoked browser access on the operation ledger.
- Raw-body Stripe webhook signature verification and exact USD amount checks.
- Private label bucket; legacy public URLs are resolved only within the configured Supabase bucket. Signed share links expire after five minutes.
- Environment files are ignored. Temporary provider identity tokens are not application configuration.

## Deployment facts that source code cannot prove

Live migrations, custom RLS policies, provider webhook subscriptions, Redis availability, credentials, backups, and domain configuration must be verified separately. A source fix is not evidence that the deployed store is patched. PGlite simulates Supabase roles; hosted Supabase storage, auth configuration, and real concurrent sessions require staging verification.

## Current limits and next priorities

1. Pre-payment stock reservations with expiration/provider cancellation. Current design records shortages after payment for staff resolution.
2. Durable notification outbox and retry worker. Current post-commit emails/SMS can fail without automatic recovery.
3. Staff-specific accounts, MFA, session revocation, and actor-level audit attribution. The existing password-first session is shared and expires after eight hours.
4. Verified-email signup as a product flow. New accounts currently retain immediate sign-in; account creation alone must not be treated as proof of email ownership.
5. High-entropy guest tracking tokens. Current guest access requires exact email plus order number and is rate limited, but order numbers are sequential.
6. Multi-connection PostgreSQL concurrency/load tests and full hosted-provider staging tests.
7. Automatic reconciliation of refunds made outside the application. Only refunds tied to saved operations are automatically reconciled.
8. A financial reconciliation view for unpaid phone-order shortages and historical tax snapshots. Staff currently confirm collection/settlement at handoff.

## Dependency review

Compatible dependency updates removed the critical Next.js advisory observed during this change and upgraded Nodemailer. Run `npm audit` against the current lockfile for current results. Known remaining advisories are in development tooling, including the legacy background-removal script dependency and the lint glob chain. Do not force a Next ESLint downgrade or replace image-processing dependencies without testing their consumers. `npm audit --omit=dev` distinguishes the production dependency graph; a clean production graph does not establish application security.

## Reporting

Report suspected defects privately to the repository owner. Do not include secrets, real customer records, or exploitable production screenshots in public issues. Use synthetic fixtures for reproductions.
