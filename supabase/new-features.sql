-- ============================================================
-- Run this in Supabase Dashboard → SQL Editor
-- Adds: product_reviews, wishlists, product image gallery
-- ============================================================

-- 1. Product image gallery (extra photos per product)
alter table public.products
  add column if not exists image_urls text[] default '{}';

-- 2. Product Reviews
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

create policy "approved reviews are public" on public.product_reviews
  for select using (approved = true);

create policy "users can submit reviews" on public.product_reviews
  for insert to authenticated with check (auth.uid() = user_id and approved = false);

-- 3. Wishlists
create table if not exists public.wishlists (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique(user_id, product_id)
);

create index if not exists wishlists_user_id_idx
  on public.wishlists(user_id);

alter table public.wishlists enable row level security;

create policy "users manage own wishlist" on public.wishlists
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
