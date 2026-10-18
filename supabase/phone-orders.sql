-- ============================================================
-- Phone / WhatsApp order desk
--
-- Lets staff take an order by phone, save it unpaid, then mark
-- paid when cash/Zelle/card-at-counter lands. Run in Supabase SQL Editor.
-- ============================================================

alter table orders
  add column if not exists payment_status text not null default 'paid',
  add column if not exists paid_at timestamptz,
  add column if not exists order_source text not null default 'online';

comment on column orders.payment_status is
  'paid | unpaid. Online Stripe orders are paid at creation; phone orders may start unpaid.';

comment on column orders.paid_at is
  'When payment was collected. Null while unpaid.';

comment on column orders.order_source is
  'online | phone | whatsapp | in_store';

-- Existing Stripe (and any already-settled) rows stay paid.
update orders
set paid_at = coalesce(paid_at, created_at)
where payment_status = 'paid' and paid_at is null;

create index if not exists orders_payment_status_idx on orders (payment_status);
create index if not exists orders_order_source_idx on orders (order_source);
