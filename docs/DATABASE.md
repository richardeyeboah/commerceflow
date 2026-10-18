# Database setup and release procedure

## Fresh Supabase development project

Use a separate project with no production customer data. Apply these versioned files in order using Supabase's migration tooling or SQL editor:

1. `supabase/migrations/202610180001_baseline.sql`
2. `supabase/migrations/202610180002_commerce_integrity.sql`
3. `supabase/migrations/202610180003_private_labels.sql`

The baseline freezes the core schema and feature columns required by the application. Supabase provides `auth`, `storage`, and API roles. Existing root-level SQL files are historical setup/maintenance scripts, not an ordered migration runner. Do not apply all files alphabetically. In particular, reset/seed scripts are not upgrades.

Optional fuzzy search remains in the historical grocery-ops script; the application has a fallback if that RPC is absent. The versioned baseline does not require the trigram extension.

## Existing deployed project

1. Take and verify a database backup; record the current application commit and deployed schema.
2. Compare the required schema against the baseline. The additive migration assumes the existing grocery/phone/pickup/shipping feature columns are present. Add missing prerequisite features in staging first. Do not run the baseline blindly over a live installation: it contains historical setup/backfill statements.
3. Apply only `202610180002_commerce_integrity.sql` and `202610180003_private_labels.sql` to staging, in that order. Each upgrade is transactional.
4. Verify RPC grants, profile trigger, review policy, private label bucket, and unique Stripe identifiers. Review any pre-existing custom policies; permissive policies combine with OR.
5. Deploy the application to staging with separate keys. Complete the staging checks below.
6. Apply the reviewed upgrades to production, then release the matching application. Until migration, the new write paths intentionally fail rather than save incomplete financial records.

Do not merge/deploy the application before its database upgrade. Private labels also require their matching application changes: old public label links stop working when the bucket is made private.

## Staging acceptance checks

- Successful Stripe test payment creates exactly one order with the expected items, totals, tax allocation, and inventory change.
- Replay the same signed payment event; confirm no additional order or stock decrement.
- Change a product price after preparing payment; fulfillment retains the purchased quote.
- Make stock insufficient before fulfillment; the paid order remains visible for inventory review.
- Simulate failure during item insertion; confirm header/items/inventory all roll back and replay repairs the operation.
- Retry a refund after a simulated timeout; confirm one provider refund and one accounting update.
- Attempt overlapping partial refunds; confirm a second operation is rejected while the first is pending.
- Verify full refund changes order status to cancelled.
- Verify browser anonymous/authenticated roles cannot execute commerce RPCs, elevate profile roles, self-approve reviews, or write/download private labels.
- Verify staff can download labels and five-minute share links expire.
- Verify `payment_intent.succeeded`, `checkout.session.completed`, `refund.created`, `refund.updated`, and `refund.failed` are subscribed at the correct Stripe endpoint.

## Rollback

Stop writes and reconcile pending payments/refunds before rolling back. Keep the operation ledger and financial records. Do not undo this change by dropping tables or making customer-label storage public. Prefer a forward repair; a schema rollback requires a reviewed data-preserving plan.

## Local verification

`npm test` creates an ephemeral PGlite PostgreSQL database, supplies a minimal Supabase role/auth/storage fixture, and applies these migrations. It needs no database password and does not connect to the hosted project. This catches SQL execution, transaction, role-policy, and retry regressions without writing production data.
