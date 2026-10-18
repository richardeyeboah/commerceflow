# Architecture and reliability

## Boundaries

Next.js route handlers adapt browser cookies or native bearer tokens into application actions. Pricing and quote helpers operate on authoritative database products. Supabase service-role calls live on the server; customer Supabase reads remain subject to RLS. Staff access normally requires an eight-hour HMAC-signed cookie. Supabase admin-role bypass is opt-in and still depends on the protected profile role.

## Checkout and fulfillment

1. Validate cart lines, aggregate quantities per product, load current products, and check quantity limits.
2. Calculate the server quote, including tax allocated in cents to each purchased line. Validate the destination and delivery eligibility.
3. Save the snapshot and create a USD PaymentIntent whose metadata points to it.
4. Verify Stripe's raw-body webhook signature. Retrieve payment status and compare received cents and currency against the saved quote.
5. Call `record_commerce_order`. PostgreSQL locks the payment identity and products in stable order, creates the order and items, allocates stock, and writes the initial event atomically.
6. Send notifications after commit. Browser/native polling can retry fulfillment if the webhook is delayed.

If a statement fails, PostgreSQL rolls back the entire order operation. Duplicate provider delivery returns the committed order without consuming stock again. Older header-only records are repaired when a valid source snapshot/session is still available.

Snapshots are retained for reconciliation. Cleanup only removes old snapshots linked to complete orders. Unresolved snapshots require a provider-status check or cancellation before removal. A successful payment is not rejected solely because its snapshot is older than 24 hours.

The legacy hosted Checkout Session endpoint remains supported, uses the same transaction writer, and enforces delivery eligibility. Its provider line items preserve purchased prices. It does not store per-line tax allocations for historical sessions; legacy shortfall calculations may need review.

## Inventory

`stock_quantity = null` means the merchant only tracks availability. A numeric quantity is decremented inside the order transaction. `allocated_quantity` records the portion accounted for against available stock. Insufficient stock never becomes negative: the paid order is retained with `inventory_review = true` for staff resolution.

No stock reservation is held while a customer enters payment details. Multiple customers can pay for the last unit before either webhook runs. Inventory review and shortfall refund handling are deliberate compensation mechanisms, not a claim that overselling is impossible. Cancellations/refunds do not automatically restock goods, because financial refunds do not prove physical returns.

## Refunds

`commerce_operations` separates a requested refund from its completion. A UUID request key identifies one user action. A partial unique index allows only one pending operation per order; row locks protect cumulative balances. Quantity versions prevent a stale adjustment from overwriting a newer one.

The server saves the operation before calling Stripe. Provider metadata contains the operation ID, and retries use a stable Stripe idempotency key. If the network fails after Stripe succeeds, a retry searches provider refund history before creating anything. Requests older than 23 hours without a matching provider record stop for reconciliation, rather than relying indefinitely on Stripe's finite idempotency retention.

Only confirmed provider success commits the refund amount, fulfilled quantities, status change, and event together. Asynchronous refund events reconcile the same operation. Restoring quantities after a shortage is rejected because that requires a new financial agreement with the customer.

Manual refunds use the same ledger and represent staff-confirmed money returned outside Stripe. They reject Stripe and unpaid orders. Unpaid shortfall records do not represent a cash refund; staff must confirm the amount to collect at handoff.

## Remaining boundaries

- Notifications are best effort after commit; no durable email/SMS outbox yet.
- Refunds created directly in the Stripe dashboard without operation metadata need manual reconciliation.
- Shared staff passwords do not provide per-person attribution or MFA.
- PGlite tests use actual PostgreSQL semantics in one embedded instance. They do not prove cross-process database behavior, hosted storage behavior, or provider delivery timing.
- Legacy schema fallbacks remain in some catalog/admin code. New commerce writes require the documented migration rather than silently dropping financial fields.
