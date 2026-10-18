const { test, before, after } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const { PGlite } = require('@electric-sql/pglite')
let db
const productId = '10000000-0000-4000-8000-000000000001'
const orderInput = (pi, over = {}) => ({
  customer_name: 'Fixture', customer_email: 'fixture@example.invalid', customer_phone: '6145550100',
  address_line: 'Fixture', city: 'Columbus', state: 'OH', country: 'US', postal_code: '43229',
  subtotal_amount: 20, shipping_fee: 0, tax_amount: 0, total_amount: 20,
  shipping_method: 'pickup', payment_method: 'stripe', stripe_payment_intent_id: pi, ...over,
})
const itemInput = (over = {}) => [{ product_id: productId, product_name: 'Fixture', product_price: 10, quantity: 2, subtotal: 20, tax_amount: 0, ...over }]
const record = async (pi, items = itemInput(), over) => (await db.query('select record_commerce_order($1::jsonb,$2::jsonb) as result', [JSON.stringify(orderInput(pi,over)),JSON.stringify(items)])).rows[0].result
before(async () => {
  db = new PGlite()
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create table auth.users(id uuid primary key, raw_user_meta_data jsonb default '{}');
    create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    create function auth.role() returns text language sql stable as $$ select current_setting('request.jwt.claim.role',true) $$;
    create schema storage; create table storage.buckets(id text primary key,name text,public boolean);
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text,name text);
    alter table storage.objects enable row level security;
  `)
  for (const file of fs.readdirSync('supabase/migrations').sort()) {
    await db.exec(fs.readFileSync(`supabase/migrations/${file}`,'utf8'))
  }
  await db.query('insert into products(id,name,price,category,stock_quantity) values($1,$2,10,$3,20)', [productId,'Fixture','Fresh Produce'])
})
after(async () => { await db?.close() })

test('whole order rolls back if a later item references a missing product', async () => {
  await assert.rejects(record('pi_bad', [...itemInput(), ...itemInput({ product_id: '10000000-0000-4000-8000-999999999999' })]))
  assert.equal((await db.query("select count(*)::int as n from orders where stripe_payment_intent_id='pi_bad'")).rows[0].n,0)
  assert.equal((await db.query('select stock_quantity from products where id=$1',[productId])).rows[0].stock_quantity,20)
})
test('duplicate delivery records one complete order and decrements stock once', async () => {
  const a = await record('pi_once')
  const b = await record('pi_once')
  assert.equal(a.order.id,b.order.id)
  assert.equal(b.created,false)
  assert.equal((await db.query('select count(*)::int as n from order_items where order_id=$1',[a.order.id])).rows[0].n,1)
  assert.equal((await db.query('select stock_quantity from products where id=$1',[productId])).rows[0].stock_quantity,18)
})
test('legacy header-only orders are repaired', async () => {
  await db.query(`insert into orders(customer_name,customer_email,address_line,city,total_amount,stripe_payment_intent_id) values('Fixture','f@example.invalid','Fixture','Columbus',20,'pi_repair')`)
  const result = await record('pi_repair')
  assert.equal(result.created,true)
  assert.equal((await db.query('select count(*)::int as n from order_items where order_id=$1',[result.order.id])).rows[0].n,1)
})
test('paid stock shortages are retained for staff review without negative inventory', async () => {
  const result = await record('pi_short',itemInput({ quantity:99,subtotal:990 }), {subtotal_amount:990,total_amount:990})
  assert.equal(result.order.inventory_review,true)
  assert.equal((await db.query('select stock_quantity from products where id=$1',[productId])).rows[0].stock_quantity,0)
})
test('refund preparation preserves quantities; completion is atomic and idempotent', async () => {
  const result = await record('pi_refund')
  const item = (await db.query('select id from order_items where order_id=$1',[result.order.id])).rows[0]
  const payload = { lines:[{itemId:item.id,previousQuantity:2,fulfilledQuantity:1}],reason:'Fixture' }
  const args=['20000000-0000-4000-8000-000000000001',result.order.id,'shortfall',1000,JSON.stringify(payload),0]
  const op=(await db.query('select prepare_commerce_refund($1,$2,$3,$4,$5::jsonb,$6) as op',args)).rows[0].op
  assert.equal((await db.query('select fulfilled_quantity from order_items where id=$1',[item.id])).rows[0].fulfilled_quantity,null)
  // A retry gets the same durable operation, even before Stripe succeeds.
  assert.equal((await db.query('select prepare_commerce_refund($1,$2,$3,$4,$5::jsonb,$6) as op',args)).rows[0].op.id,op.id)
  await db.query("select finish_commerce_refund($1,'re_fixture','succeeded')",[op.id])
  await db.query("select finish_commerce_refund($1,'re_fixture','succeeded')",[op.id])
  assert.equal(Number((await db.query('select refund_amount from orders where id=$1',[result.order.id])).rows[0].refund_amount),10)
  assert.equal((await db.query('select fulfilled_quantity from order_items where id=$1',[item.id])).rows[0].fulfilled_quantity,1)
  await assert.rejects(db.query('select prepare_commerce_refund($1,$2,$3,$4,$5::jsonb,$6)',[
    '20000000-0000-4000-8000-000000000002',result.order.id,'shortfall',0,
    JSON.stringify({lines:[{itemId:item.id,previousQuantity:1,fulfilledQuantity:2}]}),10]),/only decrease/)
})
test('only one refund can reserve an order balance, and full refund cancels order', async () => {
  const result = await record('pi_full')
  const args=['20000000-0000-4000-8000-000000000003',result.order.id,'refund',2000,'{}',0]
  const op=(await db.query('select prepare_commerce_refund($1,$2,$3,$4,$5::jsonb,$6) as op',args)).rows[0].op
  await assert.rejects(db.query('select prepare_commerce_refund($1,$2,$3,$4,$5::jsonb,$6)',[
    '20000000-0000-4000-8000-000000000004',result.order.id,'refund',1000,'{}',0]),/pending/)
  await db.query("select finish_commerce_refund($1,'re_full','succeeded')",[op.id])
  assert.equal((await db.query('select status from orders where id=$1',[result.order.id])).rows[0].status,'cancelled')
})
test('rerunning phone migration preserves unpaid orders', async () => {
  const result=await record('pi_unpaid',itemInput(),{payment_method:'cod',payment_status:'unpaid'})
  await db.exec(fs.readFileSync('supabase/phone-orders.sql','utf8'))
  const row=(await db.query('select payment_status,paid_at from orders where id=$1',[result.order.id])).rows[0]
  assert.equal(row.payment_status,'unpaid'); assert.equal(row.paid_at,null)
})
test('anonymous clients cannot call payment RPCs or write labels; reviews cannot self-approve', async () => {
  await db.exec('grant usage on schema public,auth,storage to anon,authenticated; grant insert,select on product_reviews to anon,authenticated; grant select,insert,update on storage.objects to anon,authenticated; set role anon;')
  try {
    await assert.rejects(db.query('select record_commerce_order($1::jsonb,$2::jsonb)',['{}','[]']),/permission denied/)
    await assert.rejects(db.query("insert into storage.objects(bucket_id,name) values('shipping-labels','bad.pdf')"),/row-level security/)
    await assert.rejects(db.query('insert into product_reviews(product_id,reviewer_name,rating,approved) values($1,$2,5,true)',[productId,'Fixture']),/row-level security/)
  } finally { await db.exec('reset role;') }
  assert.equal((await db.query("select public from storage.buckets where id='shipping-labels'")).rows[0].public,false)
})
test('authenticated profile update cannot elevate role', async () => {
  const uid='30000000-0000-4000-8000-000000000001'
  await db.query('insert into auth.users(id) values($1)',[uid])
  await db.exec(`grant select,update on profiles to authenticated; set request.jwt.claim.sub='${uid}'; set request.jwt.claim.role='authenticated'; set role authenticated;`)
  try {
    await db.query("update profiles set role='admin' where id=$1",[uid])
    assert.equal((await db.query('select role from profiles where id=$1',[uid])).rows[0].role,'customer')
  } finally { await db.exec('reset role;') }
})
