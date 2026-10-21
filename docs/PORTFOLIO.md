# CommerceFlow engineering walkthrough

## Project summary

CommerceFlow is a Next.js and TypeScript grocery commerce application backed by Supabase/PostgreSQL and Stripe. Customers browse, check out, and track purchases; staff manage inventory, refunds, and fulfillment. The web application, native clients, and operating instructions remain in their existing directories so build and deployment paths remain stable.

[Live storefront](https://kintampoafricanmarket.com) · [Source code](https://github.com/richardeyeboah/commerceflow)

## Code reading order

1. `lib/order-pricing.ts` and `lib/checkout-totals.ts`: sanitize cart lines and calculate totals using database product prices rather than client-supplied amounts.
2. `app/api/checkout/payment-intent/route.ts`: validate the customer/cart, calculate checkout amounts, and create payment state.
3. `app/api/stripe/webhook/route.ts`: verify Stripe event signatures before dispatching fulfillment.
4. `lib/orders/fulfill-payment-intent.ts` and `lib/orders/fulfill-stripe-checkout.ts`: convert successful payments into order records and check provider identifiers for duplicates.
5. `lib/orders/partial-refund.ts`: calculate shortages, category tax adjustments, and remaining refundable amounts.
6. `app/api/admin/orders/[id]/refund/route.ts`: authorize staff requests before invoking Stripe refunds.
7. `supabase/bootstrap.sql`: inspect order schema, provider identifier uniqueness, and access policies.
8. `tests/`: inspect pricing, refund, tax, receipt, checkout, and administrative access expectations.

## Engineering decisions to demonstrate

- **Price authority:** the server reads catalog prices before calculating payment amounts.
- **Payment authenticity:** the webhook verifies the raw request body with Stripe's signature and webhook secret.
- **Duplicate detection:** payment/session identifiers are checked and constrained uniquely; this alone does not guarantee recovery after a partially written order.
- **Shortfall accounting:** refunds separate goods and taxable amounts and cap refunds at the remaining refundable balance.
- **Access boundaries:** staff APIs and customer-owned records use different authorization paths.

## Demo outline

Use an isolated development database and Stripe test mode. Show browsing and guest checkout, inspect a test order in staff tools, explain server-side pricing, then walk through the shortfall-refund tests. Use synthetic customers and addresses. Run integration tests only against a configured test environment.

## Resume entry

**CommerceFlow | Next.js, TypeScript, Supabase, PostgreSQL, Stripe**

- Built a full-stack grocery storefront with guest/account checkout, pickup and shipping, and staff tools for inventory, refunds, and fulfillment.
- Implemented server-calculated checkout totals, Stripe webhook signature verification, and unique payment identifiers to reject client price tampering and detect duplicate payment records.
- Developed a 61-test Playwright suite across 13 files covering checkout, tax/shipping rules, refunds, receipts, and staff APIs.

The test count describes declared tests. Consult verification notes for tests actually executed. Do not infer revenue, customer counts, uptime, deployment parity, or full integration success from source code.
