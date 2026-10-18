-- Fresh databases only. Existing installations: see docs/DATABASE.md.

-- Source baseline: bootstrap.sql
-- ============================================================
-- Kintampo African Market — one-shot bootstrap for a NEW project
-- Dashboard → SQL Editor → paste all → Run
-- Project: qppnaxvwslwlsvsdwhvp
-- Safe to re-run (IF NOT EXISTS / drop policy if exists).
-- ============================================================

-- 1) Products (public catalog) -----------------------------------------------
create table if not exists public.products (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  description text,
  price       numeric(10,2) not null,
  category    text not null,
  image_url   text,
  image_urls  text[] not null default '{}',
  in_stock    boolean not null default true,
  created_at  timestamptz not null default now()
);

alter table public.products enable row level security;

drop policy if exists "Public can view products" on public.products;
create policy "Public can view products"
  on public.products for select
  using (true);

-- 2) Orders + items ----------------------------------------------------------
create table if not exists public.orders (
  id                         uuid primary key default gen_random_uuid(),
  customer_name              text not null,
  customer_email             text not null,
  customer_phone             text,
  address_line               text not null,
  city                       text not null,
  state                      text,
  country                    text not null default 'United States',
  postal_code                text,
  subtotal_amount            numeric(10,2) not null default 0,
  shipping_fee               numeric(10,2) not null default 0,
  tax_amount                 numeric(10,2) not null default 0,
  shipping_method            text not null default 'standard',
  shipping_zone              text,
  total_amount               numeric(10,2) not null,
  status                     text not null default 'ordered',
  payment_method             text not null default 'stripe',
  user_id                    uuid references auth.users(id) on delete set null,
  stripe_checkout_session_id text,
  stripe_payment_intent_id   text,
  pickup_contact_name        text,
  tracking_number            text,
  admin_note                 text,
  refunded_at                timestamptz,
  refund_amount              numeric,
  refund_stripe_id           text,
  ordered_at                 timestamptz,
  processing_at              timestamptz,
  shipped_at                 timestamptz,
  out_for_delivery_at        timestamptz,
  delivered_at               timestamptz,
  cancelled_at               timestamptz,
  created_at                 timestamptz not null default now()
);

create table if not exists public.order_items (
  id            uuid primary key default gen_random_uuid(),
  order_id      uuid not null references public.orders(id) on delete cascade,
  product_id    uuid references public.products(id),
  product_name  text not null,
  product_price numeric(10,2) not null,
  quantity      int not null,
  subtotal      numeric(10,2) not null
);

create unique index if not exists orders_stripe_checkout_session_id_key
  on public.orders (stripe_checkout_session_id)
  where stripe_checkout_session_id is not null;

create unique index if not exists orders_stripe_payment_intent_id_key
  on public.orders (stripe_payment_intent_id)
  where stripe_payment_intent_id is not null;

create index if not exists idx_orders_user_id on public.orders (user_id);

create sequence if not exists orders_order_number_seq start 1001;
alter table public.orders
  add column if not exists order_number bigint;
update public.orders
set order_number = nextval('orders_order_number_seq')
where order_number is null;
alter table public.orders
  alter column order_number set default nextval('orders_order_number_seq');
alter table public.orders
  alter column order_number set not null;
create unique index if not exists orders_order_number_unique on public.orders(order_number);

alter table public.orders enable row level security;
alter table public.order_items enable row level security;

drop policy if exists "Anyone can place orders" on public.orders;
drop policy if exists "Anyone can insert order items" on public.order_items;
drop policy if exists "service_role_only_orders" on public.orders;
drop policy if exists "service_role_only_order_items" on public.order_items;
drop policy if exists "orders_anon_none" on public.orders;
drop policy if exists "orders_select_own" on public.orders;
drop policy if exists "order_items_anon_none" on public.order_items;
drop policy if exists "order_items_select_own" on public.order_items;

create policy "orders_anon_none"
  on public.orders for all to anon
  using (false) with check (false);

create policy "orders_select_own"
  on public.orders for select to authenticated
  using (user_id is not null and auth.uid() = user_id);

create policy "order_items_anon_none"
  on public.order_items for all to anon
  using (false) with check (false);

create policy "order_items_select_own"
  on public.order_items for select to authenticated
  using (
    exists (
      select 1 from public.orders o
      where o.id = order_items.order_id
        and o.user_id is not null
        and o.user_id = auth.uid()
    )
  );

-- 3) Profiles ----------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  phone text,
  role text not null default 'customer' check (role in ('customer', 'admin')),
  marketing_opt_in boolean default false,
  terms_accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
drop policy if exists "profiles_insert_own" on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;

create policy "profiles_select_own"
  on public.profiles for select to authenticated
  using (auth.uid() = id);
create policy "profiles_insert_own"
  on public.profiles for insert to authenticated
  with check (auth.uid() = id);
create policy "profiles_update_own"
  on public.profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    'customer'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 4) Reviews + wishlist ------------------------------------------------------
create table if not exists public.product_reviews (
  id            uuid primary key default gen_random_uuid(),
  product_id    uuid not null references public.products(id) on delete cascade,
  user_id       uuid references auth.users(id) on delete set null,
  reviewer_name text not null,
  rating        smallint not null check (rating between 1 and 5),
  comment       text,
  approved      boolean not null default false,
  created_at    timestamptz not null default now()
);

create index if not exists product_reviews_product_id_idx
  on public.product_reviews(product_id);

alter table public.product_reviews enable row level security;

drop policy if exists "approved reviews are public" on public.product_reviews;
drop policy if exists "users can submit reviews" on public.product_reviews;
create policy "approved reviews are public" on public.product_reviews
  for select using (approved = true);
create policy "users can submit reviews" on public.product_reviews
  for insert to authenticated with check (auth.uid() = user_id and approved = false);

create table if not exists public.wishlists (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique(user_id, product_id)
);

alter table public.wishlists enable row level security;
drop policy if exists "users manage own wishlist" on public.wishlists;
create policy "users manage own wishlist" on public.wishlists
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- 5) Addresses + status logs -------------------------------------------------
create table if not exists public.addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text,
  full_name text not null,
  phone text,
  line1 text not null,
  line2 text,
  city text not null,
  state text not null,
  country text not null default 'United States',
  postal_code text not null,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists addresses_user_idx on public.addresses(user_id);
alter table public.addresses enable row level security;
drop policy if exists "addresses_owner_select" on public.addresses;
create policy "addresses_owner_select" on public.addresses
  for select using (auth.uid() = user_id);
drop policy if exists "addresses_owner_insert" on public.addresses;
create policy "addresses_owner_insert" on public.addresses
  for insert with check (auth.uid() = user_id);
drop policy if exists "addresses_owner_update" on public.addresses;
create policy "addresses_owner_update" on public.addresses
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "addresses_owner_delete" on public.addresses;
create policy "addresses_owner_delete" on public.addresses
  for delete using (auth.uid() = user_id);

create table if not exists public.order_status_logs (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  from_status text,
  to_status text not null,
  changed_at timestamptz not null default now(),
  changed_by text,
  note text
);

create index if not exists order_status_logs_order_idx
  on public.order_status_logs(order_id, changed_at desc);

alter table public.order_status_logs enable row level security;
drop policy if exists "service_role_only_order_status_logs" on public.order_status_logs;
create policy "service_role_only_order_status_logs"
  on public.order_status_logs for all to anon, authenticated
  using (false) with check (false);

-- 8) Checkout snapshots (Stripe Payment Element) -----------------------------
create table if not exists public.checkout_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  payload jsonb not null,
  payment_intent_id text,
  created_at timestamptz not null default now()
);

create index if not exists checkout_snapshots_user_id_idx
  on public.checkout_snapshots (user_id);

create index if not exists checkout_snapshots_payment_intent_id_idx
  on public.checkout_snapshots (payment_intent_id);

alter table public.checkout_snapshots enable row level security;

revoke all on table public.checkout_snapshots from anon, authenticated;

drop policy if exists "deny all non-service-role access to checkout_snapshots"
  on public.checkout_snapshots;

create policy "deny all non-service-role access to checkout_snapshots"
  on public.checkout_snapshots
  for all
  to public
  using (false)
  with check (false);

-- Done ----------------------------------------------------------------------
select 'bootstrap ok' as status,
  (select count(*) from public.products) as products;


-- Source baseline: grocery-ops.sql
-- Tier 2–4 grocery ops: stock qty, unit pricing, variants, brand/dietary,
-- checkout prefs (substitution, pickup slot, tip), announcements, bundles, recipes.
-- Safe to re-run.

-- ── Products ───────────────────────────────────────────────────────────────
alter table products
  add column if not exists brand text,
  add column if not exists dietary_tags text[] not null default '{}',
  add column if not exists stock_quantity integer,
  add column if not exists unit_amount numeric(10, 3),
  add column if not exists unit_of_measure text,
  add column if not exists pack_label text,
  add column if not exists variant_group text;

comment on column products.brand is 'Brand for filters (e.g. Tropiway).';
comment on column products.dietary_tags is 'Tags: vegetarian, vegan, gluten_free, halal, spicy.';
comment on column products.stock_quantity is 'Null = use in_stock boolean only. When set, drives low-stock UI.';
comment on column products.unit_amount is 'Numeric size for unit price (e.g. 5 for 5 lb).';
comment on column products.unit_of_measure is 'lb | oz | kg | g | ct | ml | l';
comment on column products.pack_label is 'Display pack size override (e.g. 5 lb bag).';
comment on column products.variant_group is 'Shared slug linking size variants of the same item.';

create index if not exists products_brand_idx on products (brand);
create index if not exists products_variant_group_idx on products (variant_group);
create index if not exists products_dietary_tags_gin on products using gin (dietary_tags);

-- Keep in_stock in sync when quantity is tracked.
create or replace function products_sync_in_stock_from_qty()
returns trigger
language plpgsql
as $$
begin
  if new.stock_quantity is not null then
    new.in_stock := new.stock_quantity > 0;
  end if;
  return new;
end;
$$;

drop trigger if exists products_sync_in_stock_trg on products;
create trigger products_sync_in_stock_trg
  before insert or update of stock_quantity
  on products
  for each row
  execute function products_sync_in_stock_from_qty();

-- ── Orders (checkout extras) ───────────────────────────────────────────────
alter table orders
  add column if not exists substitution_pref text,
  add column if not exists pickup_slot text,
  add column if not exists tip_amount numeric(10, 2) not null default 0;

comment on column orders.substitution_pref is 'refund | call | substitute';
comment on column orders.pickup_slot is 'Customer-selected pickup window label.';
comment on column orders.tip_amount is 'Driver tip for local delivery (and optional pickup tip).';

-- ── Announcement bar (admin-managed) ───────────────────────────────────────
create table if not exists site_announcements (
  id uuid primary key default gen_random_uuid(),
  message text not null,
  href text,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table site_announcements is 'Rotating storefront announcement bar messages.';

alter table site_announcements enable row level security;

drop policy if exists "Public read active announcements" on site_announcements;
create policy "Public read active announcements"
  on site_announcements for select
  using (active = true);

-- Seed defaults only when empty.
insert into site_announcements (message, href, sort_order)
select * from (values
  ('Nationwide shipping · Free standard on $120+ · Pickup in Columbus', null::text, 0),
  ('Mobile market & Ohio delivery — call the store', '/#mobile-market', 1),
  ('Insurance, notary & more services — by appointment', '/#services', 2),
  ('Store pickup · 1668 E Dublin Granville Rd, Columbus, OH 43229', null::text, 3)
) as v(message, href, sort_order)
where not exists (select 1 from site_announcements limit 1);

-- ── Bundles / kits ─────────────────────────────────────────────────────────
create table if not exists product_bundles (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  image_url text,
  discount_percent numeric(5, 2) not null default 0,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists product_bundle_items (
  id uuid primary key default gen_random_uuid(),
  bundle_id uuid not null references product_bundles(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  quantity integer not null default 1 check (quantity > 0),
  unique (bundle_id, product_id)
);

alter table product_bundles enable row level security;
alter table product_bundle_items enable row level security;

drop policy if exists "Public read active bundles" on product_bundles;
create policy "Public read active bundles"
  on product_bundles for select
  using (active = true);

drop policy if exists "Public read bundle items" on product_bundle_items;
create policy "Public read bundle items"
  on product_bundle_items for select
  using (
    exists (
      select 1 from product_bundles b
      where b.id = bundle_id and b.active = true
    )
  );

-- ── Recipes ────────────────────────────────────────────────────────────────
create table if not exists recipes (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  summary text,
  body_md text not null default '',
  image_url text,
  prep_minutes integer,
  cook_minutes integer,
  servings integer,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists recipe_ingredients (
  id uuid primary key default gen_random_uuid(),
  recipe_id uuid not null references recipes(id) on delete cascade,
  product_id uuid references products(id) on delete set null,
  label text not null,
  quantity integer not null default 1 check (quantity > 0),
  sort_order integer not null default 0
);

alter table recipes enable row level security;
alter table recipe_ingredients enable row level security;

drop policy if exists "Public read active recipes" on recipes;
create policy "Public read active recipes"
  on recipes for select
  using (active = true);

drop policy if exists "Public read recipe ingredients" on recipe_ingredients;
create policy "Public read recipe ingredients"
  on recipe_ingredients for select
  using (
    exists (
      select 1 from recipes r
      where r.id = recipe_id and r.active = true
    )
  );

-- Seed starter recipes (ingredients linked later in admin by product_id).
insert into recipes (slug, title, summary, body_md, prep_minutes, cook_minutes, servings, sort_order)
select * from (values
  (
    'egusi-soup',
    'Egusi soup',
    'Classic West African melon-seed stew. Pair with fufu or rice.',
    E'## Steps\n\n1. Blend egusi with a little water into a thick paste.\n2. Sauté onion, pepper, and tomato base until reduced.\n3. Add stock, leafy greens, and protein.\n4. Drop spoonfuls of egusi paste; simmer until oil rises.\n5. Season and serve with fufu, pounded yam, or rice.',
    20,
    45,
    4,
    0
  ),
  (
    'jollof-rice',
    'Jollof rice',
    'Party-style one-pot rice with tomato pepper base.',
    E'## Steps\n\n1. Blend tomato, pepper, and onion.\n2. Fry the base in oil until deep red and thick.\n3. Add rice, stock, and seasoning; cover and steam.\n4. Fluff and rest 5 minutes before serving.',
    15,
    40,
    6,
    1
  ),
  (
    'plantain-fufu-night',
    'Plantain & fufu night',
    'Quick weeknight plate: ripe plantain with fufu and stew.',
    E'## Steps\n\n1. Peel and fry ripe plantain until golden.\n2. Prepare fufu flour per package directions.\n3. Warm stew or soup and plate together.',
    10,
    25,
    2,
    2
  )
) as v(slug, title, summary, body_md, prep_minutes, cook_minutes, servings, sort_order)
where not exists (select 1 from recipes where slug = v.slug);

-- Soft ingredient labels (no product_id) for the seeded recipes.
insert into recipe_ingredients (recipe_id, label, quantity, sort_order)
select r.id, i.label, i.quantity, i.sort_order
from recipes r
join (values
  ('egusi-soup', 'Egusi (melon seed)', 1, 0),
  ('egusi-soup', 'Palm oil', 1, 1),
  ('egusi-soup', 'Stockfish or protein', 1, 2),
  ('egusi-soup', 'Leafy greens', 1, 3),
  ('egusi-soup', 'Fufu flour', 1, 4),
  ('jollof-rice', 'Long grain rice', 1, 0),
  ('jollof-rice', 'Tomato / pepper mix', 1, 1),
  ('jollof-rice', 'Vegetable oil', 1, 2),
  ('jollof-rice', 'Seasoning / stock', 1, 3),
  ('plantain-fufu-night', 'Ripe plantain', 1, 0),
  ('plantain-fufu-night', 'Fufu flour', 1, 1),
  ('plantain-fufu-night', 'Stew or soup base', 1, 2)
) as i(slug, label, quantity, sort_order) on r.slug = i.slug
where not exists (
  select 1 from recipe_ingredients ri where ri.recipe_id = r.id
);



-- Source baseline: partial-fulfillment.sql
-- ============================================================
-- Partial fulfillment + delivery proof
--
-- Lets staff hand over only the items actually on the shelf, refund the
-- shortfall, and record how a delivery ended (handed over vs left at door).
-- Run in Supabase SQL Editor.
-- ============================================================

alter table order_items
  -- How many of `quantity` were actually given to the customer.
  -- NULL means "not adjusted" and is treated as the full ordered quantity,
  -- so existing rows keep their current meaning.
  add column if not exists fulfilled_quantity int;

comment on column order_items.fulfilled_quantity is
'Units actually handed over. NULL = full quantity fulfilled (no shortage recorded).';

alter table orders
  -- 'handed' | 'left_at_door' — how the courier closed out the delivery.
  add column if not exists delivery_proof text,
  add column if not exists delivery_proof_note text,
  add column if not exists delivery_proof_at timestamptz,
  -- Running total refunded specifically for out-of-stock lines, so the
  -- shortfall refund never double-counts a goodwill refund issued by hand.
  add column if not exists shortfall_refund_amount numeric(10,2) not null default 0;

comment on column orders.delivery_proof is
'How the delivery ended: handed | left_at_door.';

comment on column orders.shortfall_refund_amount is
'Portion of refund_amount that was issued for unavailable items.';


-- Source baseline: pickup-flow.sql
-- ============================================================
-- Store pickup upgrade
-- Adds a "who's collecting" contact and a ready-for-pickup step
-- so customers can send an Uber/DoorDash driver or a friend.
-- Run in Supabase SQL Editor.
-- ============================================================

alter table orders
  -- Optional: name of the person collecting (customer, a friend, or
  -- "Uber driver"). Helps staff hand the bag to the right person.
  add column if not exists pickup_contact_name text,
  -- Timestamp set when a pickup order is staged at the counter.
  add column if not exists ready_for_pickup_at timestamptz;

comment on column orders.status is
'ordered | processing | ready_for_pickup | shipped | out_for_delivery | delivered | cancelled';

comment on column orders.pickup_contact_name is
'Who is collecting a pickup order (customer, friend, or courier the customer sends).';


-- Source baseline: phone-orders.sql
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


-- Source baseline: shipping-labels.sql
-- Shipping label metadata (Shippo / USPS / UPS)
alter table public.orders add column if not exists shipping_label_url text;
alter table public.orders add column if not exists shipping_carrier text;
alter table public.orders add column if not exists shipping_service text;
alter table public.orders add column if not exists label_purchased_at timestamptz;

comment on column public.orders.shipping_label_url is 'PDF URL from Shippo after label purchase';
comment on column public.orders.shipping_carrier is 'USPS or UPS';
comment on column public.orders.shipping_service is 'Carrier service name e.g. Priority Mail';


-- Source baseline: profiles-extended-auth.sql
-- ============================================================
-- Extended profile fields + handle_new_user() for signup metadata
-- Run in Supabase SQL Editor after auth-profiles.sql (safe to re-run).
--
-- Signup sends user metadata: first_name, last_name, full_name, phone,
-- marketing_opt_in, terms_accepted_at.
-- ============================================================

alter table public.profiles add column if not exists marketing_email_opt_in boolean not null default false;
alter table public.profiles add column if not exists terms_accepted_at timestamptz;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  fn text := coalesce(nullif(trim(new.raw_user_meta_data->>'first_name'), ''), '');
  ln text := coalesce(nullif(trim(new.raw_user_meta_data->>'last_name'), ''), '');
  combined text;
  marketing boolean;
  terms_ts timestamptz;
begin
  combined := nullif(trim(concat_ws(' ', fn, ln)), '');
  if combined is null then
    combined := nullif(trim(coalesce(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      ''
    )), '');
  end if;

  marketing := lower(coalesce(new.raw_user_meta_data->>'marketing_opt_in', '')) in ('true', 't', '1');

  begin
    if new.raw_user_meta_data->>'terms_accepted_at' is not null
       and btrim(new.raw_user_meta_data->>'terms_accepted_at') <> '' then
      terms_ts := (new.raw_user_meta_data->>'terms_accepted_at')::timestamptz;
    else
      terms_ts := null;
    end if;
  exception when others then
    terms_ts := null;
  end;

  insert into public.profiles (id, full_name, phone, role, marketing_email_opt_in, terms_accepted_at)
  values (
    new.id,
    coalesce(combined, ''),
    nullif(trim(coalesce(new.raw_user_meta_data->>'phone', '')), ''),
    'customer',
    marketing,
    terms_ts
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

comment on column public.profiles.marketing_email_opt_in is 'Optional marketing opt-in from signup (not pre-checked by default in app).';
comment on column public.profiles.terms_accepted_at is 'Timestamp when user accepted Terms/Privacy during signup, if provided.';


-- Source baseline: protect-profiles-role.sql
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
