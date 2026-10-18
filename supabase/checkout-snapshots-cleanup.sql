-- Only remove snapshots whose complete order was committed. Unresolved payments
-- need Stripe reconciliation/cancellation before their recovery payload is removed.
delete from checkout_snapshots c
where c.created_at < now() - interval '30 days'
  and exists (
    select 1 from orders o join order_items i on i.order_id=o.id
    where o.stripe_payment_intent_id=c.payment_intent_id
  );
