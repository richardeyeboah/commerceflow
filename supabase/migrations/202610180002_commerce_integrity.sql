-- Additive upgrade for an existing store. Run in a transaction after taking a backup.
-- Application deploy requires this migration first. RPCs are service-role only.
begin;
update public.orders set customer_email=lower(btrim(customer_email)) where customer_email is distinct from lower(btrim(customer_email));
alter table public.orders add column if not exists inventory_review boolean not null default false;
alter table public.order_items add column if not exists allocated_quantity integer;
alter table public.order_items add column if not exists tax_amount numeric(10,2);
alter table public.orders add column if not exists shortfall_refund_amount numeric(10,2) not null default 0;
alter table public.order_items add column if not exists fulfilled_quantity integer;

create table if not exists public.commerce_operations (
 id uuid primary key default gen_random_uuid(),
 request_key uuid not null unique,
 order_id uuid not null references public.orders(id) on delete restrict,
 kind text not null check (kind in ('refund','shortfall')),
 amount_cents integer not null check (amount_cents >= 0),
 payload jsonb not null,
 state text not null default 'pending' check (state in ('pending','succeeded','failed')),
 provider_refund_id text unique,
 created_at timestamptz not null default now(),
 completed_at timestamptz
);
create unique index if not exists commerce_one_pending_per_order
 on public.commerce_operations(order_id) where state = 'pending';
alter table public.commerce_operations enable row level security;
revoke all on public.commerce_operations from anon, authenticated;

-- Atomic header + lines + inventory accounting + initial event. A duplicate
-- webhook returns only a complete order, and repairs legacy header-only rows.
create or replace function public.record_commerce_order(p_order jsonb, p_items jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
 o public.orders; item jsonb; product public.products; allocated integer;
 existing_id uuid; payment_key text; shortage boolean := false;
begin
 if jsonb_array_length(p_items) < 1 then raise exception 'Empty order'; end if;
 payment_key := coalesce(p_order->>'stripe_payment_intent_id',p_order->>'stripe_checkout_session_id',p_order->>'id');
 if payment_key is null then raise exception 'Missing operation identity'; end if;
 perform pg_advisory_xact_lock(hashtextextended(payment_key, 0));
 select id into existing_id from public.orders
 where (p_order->>'stripe_payment_intent_id' is not null and stripe_payment_intent_id = p_order->>'stripe_payment_intent_id')
 or (p_order->>'stripe_checkout_session_id' is not null and stripe_checkout_session_id = p_order->>'stripe_checkout_session_id')
 or id::text = p_order->>'id' limit 1;
 if existing_id is not null then
   select * into o from public.orders where id = existing_id for update;
   if exists(select 1 from public.order_items where order_id = existing_id) then
     return jsonb_build_object('order',to_jsonb(o),'created',false);
   end if;
 else
   -- Populate explicit columns so defaults, including order_number, remain active.
   insert into public.orders(id,customer_name,customer_email,customer_phone,address_line,city,state,country,postal_code,
     subtotal_amount,shipping_fee,tax_amount,total_amount,shipping_method,shipping_zone,status,ordered_at,
     payment_method,user_id,stripe_checkout_session_id,stripe_payment_intent_id,pickup_contact_name,
     tip_amount,substitution_pref,pickup_slot,payment_status,paid_at,order_source)
   select coalesce((p_order->>'id')::uuid,gen_random_uuid()),p_order->>'customer_name',lower(p_order->>'customer_email'),
     p_order->>'customer_phone',p_order->>'address_line',p_order->>'city',p_order->>'state',p_order->>'country',p_order->>'postal_code',
     (p_order->>'subtotal_amount')::numeric,(p_order->>'shipping_fee')::numeric,coalesce((p_order->>'tax_amount')::numeric,0),
     (p_order->>'total_amount')::numeric,p_order->>'shipping_method',p_order->>'shipping_zone','ordered',now(),
     p_order->>'payment_method',(p_order->>'user_id')::uuid,p_order->>'stripe_checkout_session_id',p_order->>'stripe_payment_intent_id',
     p_order->>'pickup_contact_name',coalesce((p_order->>'tip_amount')::numeric,0),p_order->>'substitution_pref',p_order->>'pickup_slot',
     coalesce(p_order->>'payment_status','paid'),
     case when coalesce(p_order->>'payment_status','paid')='paid' then now() else null end,
     coalesce(p_order->>'order_source','online') returning * into o;
 end if;
 -- Stable product lock order prevents deadlocks for overlapping multi-item carts.
 perform 1 from public.products where id in
   (select (value->>'product_id')::uuid from jsonb_array_elements(p_items)) order by id for update;
 for item in select value from jsonb_array_elements(p_items) loop
   if (item->>'quantity')::integer not between 1 and 99 or (item->>'product_price')::numeric < 0 then
     raise exception 'Invalid order line';
   end if;
   select * into product from public.products where id = (item->>'product_id')::uuid;
   if not found then raise exception 'Product no longer exists'; end if;
   allocated := (item->>'quantity')::integer;
   if product.stock_quantity is not null then
     allocated := least(greatest(product.stock_quantity,0),allocated);
     shortage := shortage or allocated < (item->>'quantity')::integer;
     update public.products set stock_quantity = greatest(stock_quantity-allocated,0) where id = product.id;
   elsif not product.in_stock then
     allocated := 0; shortage := true;
   end if;
   insert into public.order_items(order_id,product_id,product_name,product_price,quantity,subtotal,allocated_quantity,tax_amount)
   values(o.id,product.id,item->>'product_name',(item->>'product_price')::numeric,(item->>'quantity')::integer,
     (item->>'subtotal')::numeric,allocated,(item->>'tax_amount')::numeric);
 end loop;
 update public.orders set inventory_review=shortage where id=o.id returning * into o;
 insert into public.order_status_logs(order_id,to_status,changed_by,note)
 values(o.id,'ordered','server',case when shortage then 'Inventory shortage: staff reconciliation required' else 'Order recorded atomically' end);
 return jsonb_build_object('order',to_jsonb(o),'created',true);
end $$;
revoke all on function public.record_commerce_order(jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.record_commerce_order(jsonb,jsonb) to service_role;

create or replace function public.prepare_commerce_refund(p_key uuid,p_order_id uuid,p_kind text,p_amount integer,p_payload jsonb,p_expected_refund numeric)
returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.orders; op public.commerce_operations; line jsonb; current_qty integer;
begin
 select * into o from public.orders where id=p_order_id for update;
 if not found then raise exception 'Order not found'; end if;
 select * into op from public.commerce_operations where request_key=p_key;
 if found then
   if op.order_id<>p_order_id or op.kind<>p_kind or op.amount_cents<>p_amount or op.payload<>p_payload then
     raise exception 'Idempotency key reused with different parameters';
   end if;
   return to_jsonb(op);
 end if;
 if exists(select 1 from public.commerce_operations where order_id=p_order_id and state='pending') then
   raise exception 'A refund is pending for this order; retry the original operation';
 end if;
 if coalesce(o.refund_amount,0)<>p_expected_refund then raise exception 'Order changed; refresh and retry'; end if;
 if p_amount<0 or p_amount>round((o.total_amount-coalesce(o.refund_amount,0))*100) then raise exception 'Invalid refundable amount'; end if;
 for line in select value from jsonb_array_elements(coalesce(p_payload->'lines','[]')) loop
   select coalesce(fulfilled_quantity,quantity) into current_qty from public.order_items
   where id=(line->>'itemId')::uuid and order_id=p_order_id;
   if not found or current_qty<>(line->>'previousQuantity')::integer then raise exception 'Item quantities changed; refresh'; end if;
   -- Never restore quantities after a refund: that would require collecting money again.
   if (line->>'fulfilledQuantity')::integer<0 or (line->>'fulfilledQuantity')::integer>current_qty then
     raise exception 'Fulfilled quantities may only decrease';
   end if;
 end loop;
 insert into public.commerce_operations(request_key,order_id,kind,amount_cents,payload)
 values(p_key,p_order_id,p_kind,p_amount,p_payload) returning * into op;
 return to_jsonb(op);
end $$;
revoke all on function public.prepare_commerce_refund(uuid,uuid,text,integer,jsonb,numeric) from public,anon,authenticated;
grant execute on function public.prepare_commerce_refund(uuid,uuid,text,integer,jsonb,numeric) to service_role;

create or replace function public.finish_commerce_refund(p_id uuid,p_provider_id text,p_state text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare op public.commerce_operations; o public.orders; line jsonb; applied numeric; new_total numeric;
begin
 -- All operation functions lock the order before the operation.
 select orders.* into o from public.orders orders join public.commerce_operations c on c.order_id=orders.id
 where c.id=p_id for update of orders;
 select * into op from public.commerce_operations where id=p_id for update;
 if not found then raise exception 'Operation not found'; end if;
 if op.state<>'pending' then return to_jsonb(op); end if;
 if p_state not in ('succeeded','failed') then raise exception 'Invalid operation state'; end if;
 if p_state='failed' then
   update public.commerce_operations set state='failed',provider_refund_id=p_provider_id,completed_at=now() where id=p_id returning * into op;
   return to_jsonb(op);
 end if;
 if o.payment_method='stripe' and op.amount_cents>0 and p_provider_id is null then raise exception 'Missing provider refund'; end if;
 applied := case when o.payment_status='unpaid' then 0 else op.amount_cents/100.0 end;
 new_total := coalesce(o.refund_amount,0)+applied;
 if new_total>o.total_amount then raise exception 'Refund exceeds order total'; end if;
 for line in select value from jsonb_array_elements(coalesce(op.payload->'lines','[]')) loop
   update public.order_items set fulfilled_quantity=(line->>'fulfilledQuantity')::integer
   where id=(line->>'itemId')::uuid and order_id=o.id;
 end loop;
 update public.orders set refund_amount=new_total,
   shortfall_refund_amount=coalesce(shortfall_refund_amount,0)+case when op.kind='shortfall' then applied else 0 end,
   refund_stripe_id=coalesce(p_provider_id,refund_stripe_id),
   refunded_at=case when new_total>=total_amount then now() else refunded_at end,
   status=case when new_total>=total_amount then 'cancelled' else status end,
   cancelled_at=case when new_total>=total_amount then now() else cancelled_at end
 where id=o.id;
 update public.commerce_operations set state='succeeded',provider_refund_id=p_provider_id,completed_at=now() where id=p_id returning * into op;
 insert into public.order_status_logs(order_id,from_status,to_status,changed_by,note)
 values(o.id,o.status,case when new_total>=o.total_amount then 'cancelled' else o.status end,'admin',
   'Refund operation '||op.id||': $'||applied||coalesce(' — '||(op.payload->>'reason'),''));
 return to_jsonb(op);
end $$;
revoke all on function public.finish_commerce_refund(uuid,text,text) from public,anon,authenticated;
grant execute on function public.finish_commerce_refund(uuid,text,text) to service_role;

-- Enforce profile and review privileges independently of application flags.
-- Prevent authenticated users from escalating profiles.role to 'admin'.
-- Service-role (server) updates still work for legitimate admin provisioning.
-- Run in Supabase SQL Editor (or via migration tooling).

create or replace function public.protect_profiles_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Service role / server-side writes may change role (e.g. manual admin setup).
  if coalesce(auth.role(), '') = 'service_role' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.role := 'customer';
    return new;
  end if;

  if tg_op = 'UPDATE' and old.role is distinct from new.role then
    new.role := old.role;
  end if;

  return new;
end;
$$;

drop trigger if exists protect_profiles_role_trigger on public.profiles;

create trigger protect_profiles_role_trigger
  before insert or update on public.profiles
  for each row
  execute function public.protect_profiles_role();

comment on function public.protect_profiles_role() is
  'Blocks self-service role escalation; only service_role may set profiles.role.';
drop policy if exists "users can submit reviews" on public.product_reviews;
create policy "users can submit reviews" on public.product_reviews for insert to authenticated
 with check (auth.uid()=user_id and approved=false);
commit;
