begin;
-- Label PDFs contain customer addresses. Only the service role accesses this bucket.
insert into storage.buckets (id, name, public)
values ('shipping-labels', 'shipping-labels', false)
on conflict (id) do update set public = false;
drop policy if exists "Public read shipping labels" on storage.objects;
drop policy if exists "Service role upload shipping labels" on storage.objects;
drop policy if exists "Service role update shipping labels" on storage.objects;

commit;
