# Portfolio and interview walkthrough

## Project listing

**Full-Stack E-Commerce & Order Management Platform**
Next.js · TypeScript · Supabase · PostgreSQL · Stripe
[Live site](https://kintampoafricanmarket.com) · [Source](https://github.com/richardeyeboah/kintampo-african-market)

Built for a grocery-store workflow spanning online checkout, pickup/delivery, catalog administration, phone orders, and refunds. The strongest engineering example is making payment fulfillment recoverable when webhooks repeat or database writes fail.

## Demonstration sequence

1. Browse the catalog on a phone-sized viewport, add items, and show guest checkout.
2. Explain why the API ignores client prices and stores the purchased quote before payment.
3. Use Stripe test mode in a development environment to create an order. Show its items, status event, and stock allocation in the staff tools.
4. Replay the payment event and show that the order and stock count do not duplicate.
5. Demonstrate a shortfall refund and retry the same request. Explain the saved operation, provider idempotency key, and atomic completion.
6. Run the isolated database tests. Show a failure-in-the-middle test that proves there is no orphan order header.
7. Explain a tradeoff: no pre-payment stock reservation yet, so shortages are flagged and compensated after payment.

Do not demonstrate using real customer data or live card payments. Do not claim that unreleased branch changes are deployed.

## Concepts to explain in your own words

- **Atomic transaction:** the order header, items, inventory changes, and first event succeed together or roll back together.
- **Idempotency:** repeating one payment/refund operation does not repeat its effects.
- **Row-level security:** database rules restrict which records a customer can access, even outside the web UI.
- **Immutable snapshot:** purchased amounts remain the same when catalog prices change later.
- **Reconciliation:** compare saved operations with the payment provider after timeouts or failures.
- **Compensation:** resolve a paid inventory shortage explicitly instead of pretending payment and stock are one distributed transaction.

## Resume wording after this branch is verified and merged

- Built a full-stack grocery commerce application with guest checkout, staff order workflows, Stripe payments, and PostgreSQL-backed inventory tracking.
- Implemented transactional order fulfillment and durable refund operations to handle duplicate webhooks, partial database failures, and provider timeouts.
- Added automated security regressions and PostgreSQL integration tests covering access policies, rollback, idempotency, and refund accounting.

Avoid unsupported numbers for users, revenue, performance gains, or uptime. Use the repository's actual test results and your own measured evidence when adding metrics.
