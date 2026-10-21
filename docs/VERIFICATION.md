# Verification record

Reviewed October 20, 2026 against published base commit `2121ff0` and this cleanup branch. Checks used a clean checkout with no production environment files.

## Results

- Playwright discovery: 61 tests across 13 files.
- Isolated business-logic/PDF subset: 32 tests passed. Files: `order-logic`, `partial-refund`, `sales-tax`, `receipt-pdf`, and `pickup-ticket-pdf`.
- Web TypeScript check: passed.
- ESLint: passed with two existing unused-symbol warnings in `lib/orders/fulfill-payment-intent.ts` and `lib/supabase/products.ts`.
- Optimized Next.js production build: passed with placeholder Supabase and Stripe configuration.
- Whitespace/error check: passed.

## Corrections made

Two shipping assertions still expected the previous $7 near-state rate and $150 free-shipping threshold. The application currently uses $9.99 and $120; the tests now exercise those actual boundaries. No shipping prices were changed.

The root TypeScript project now excludes the independently installed `mobile/` workspace and local `work/` scratch directory. The mobile app must be installed and checked separately. An unchanged admin query result now uses a constant; the native simulator's CommonJS imports receive a file-scoped lint exception.

## Limits

The remaining 29 tests were discovered but were not run against hosted services or a browser-backed store in this review. Placeholder configuration verifies compilation, not authentication, card payments, emails, address verification, tax compliance, database policies, or production readiness. The live site's deployed revision was not verified.

Unpublished changes in other local checkouts were not incorporated. In particular, do not attribute transactional order/refund recovery improvements from those branches to this published baseline.

## Reproduce

```bash
npm ci
npx playwright test --list
PLAYWRIGHT_SKIP_WEBSERVER=1 npx playwright test tests/order-logic.spec.ts tests/partial-refund.spec.ts tests/sales-tax.spec.ts tests/receipt-pdf.spec.ts tests/pickup-ticket-pdf.spec.ts --workers=1
npm run typecheck
npm run lint
```

For a build, configure a dedicated development environment or supply isolated placeholder values for public/server Supabase configuration, Stripe keys and webhook secret, site URL, and admin credentials. Use `npm run build`. For full integration checks, use the development setup in the README and never point tests at real customer or payment data.
