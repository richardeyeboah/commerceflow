# Verification record — 2026-10-18

Performed in the Desktop checkout on branch `improve/commerce-reliability`, using isolated provider placeholders. The local `.env.local` is ignored and was excluded from committed changes. No hosted database migration, live payment, customer notification, label purchase, or deployment was performed.

## Results

- **20 passed:** Node/service-boundary regression tests and ephemeral PostgreSQL integration tests (`npm test`).
- **32 passed:** existing shipping, tax, shortfall, receipt, and pickup-PDF business-logic tests (`npm run test:logic`).
- **7 passed:** production-server browser/API smoke tests covering guest checkout, confirmation rendering, tracking validation, disabled direct order creation, unauthenticated admin APIs, and origin rejection (`node scripts/ci.mjs --smoke-only`, after the isolated build).
- TypeScript check: passed.
- Production build: passed with Next.js 16.4.2 resolved by the lockfile.
- ESLint: zero errors, six navigation warnings in existing components.
- `git diff --check`: passed.
- Production dependency audit (`npm audit --omit=dev`): zero known advisories at verification time. Development-tool advisories remain; see `SECURITY.md`.

The combined pipeline is `node scripts/ci.mjs --browser` after installing Chromium. An expanded GitHub Actions workflow is prepared locally to run the same checks and upload browser diagnostics on failure. GitHub rejected that workflow update because the connected app lacks workflow scope; the published branch retains the original lint/typecheck/build workflow.

## What these checks prove

The database tests execute the migration SQL and RPCs. They cover rollback of partial order writes; duplicate payment delivery; legacy header-only repair; stock shortage recording; repeatable refund preparation/completion; pending-operation exclusion; full-refund cancellation; preservation of unpaid records; anonymous access rejection; and protection against profile-role escalation.

Service-boundary tests cover exact guest email lookup, internal-log filtering, unsafe recovery rejection, duplicate cart aggregation, immutable quote fulfillment after a long delay, stable provider refund keys after network failure, and reconciliation of old provider refunds without creating another.

## What remains unverified

Hosted Supabase policies/storage, real independent-connection contention, Stripe webhook configuration, actual provider credentials, mail delivery, native client builds, and the full catalog/browser suite were not validated by these isolated checks. Follow `DATABASE.md` for staging acceptance. Tests against a simulated Supabase schema do not establish the live deployment's security state.

## GitHub-hosted checks

The first PR check did not start: GitHub reported that the account is locked due to a billing issue. This is an external account blocker, not a failed test execution. The evidence is [Actions run 39157845718](https://github.com/richardeyeboah/kintampo-african-market/actions/runs/39157845718). Local verification results above remain separate from GitHub-hosted status. Resolve account billing and the workflow permission before claiming the expanded CI pipeline is active.
