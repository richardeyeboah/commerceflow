const { test } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const ts = require('typescript')
const { NextRequest } = require('next/server')
function load(file, mocks = {}, cache = new Map()) {
  if (cache.has(file)) return cache.get(file)
  const js = ts.transpileModule(fs.readFileSync(file,'utf8'), {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText
  const module={exports:{}}
  const req=name => {
    if (name === '@/lib/security/request-rate-limit' && !(name in mocks)) return { limitPublicRequest: async () => null }
    if (name in mocks) return mocks[name]
    if (name.startsWith('@/')) return load(path.resolve(name.slice(2)+'.ts'),mocks,cache)
    return require(name)
  }
  new Function('require','module','exports',js)(req,module,module.exports)
  cache.set(file,module.exports)
  return module.exports
}
test('duplicate cart lines are combined before stock validation; malformed quantities reject',()=>{
  const {sanitizeCartItems}=load('lib/order-pricing.ts')
  assert.deepEqual(sanitizeCartItems([{product:{id:'p'},quantity:5},{product:{id:'p'},quantity:5}]),[{productId:'p',quantity:10}])
  for(const quantity of [-1,0,1.5,100,NaN]) assert.throws(()=>sanitizeCartItems([{product:{id:'p'},quantity}]))
  assert.throws(()=>sanitizeCartItems([{product:{id:'p'},quantity:99},{product:{id:'p'},quantity:1}]))
})
test('guest tracking uses exact email match and never returns internal log notes',async()=>{
  const calls=[]
  const route=load('app/api/orders/track/route.ts',{
    '@/lib/supabase/server':{createClient:async()=>({auth:{getUser:async()=>({data:{user:null}})}})},
    '@/lib/supabase-admin':{supabaseAdmin:{from:table=>{
      const q={select(fields){calls.push([table,'select',fields]);return this},eq(k,v){calls.push([table,k,v]);return this},order(){return this},maybeSingle:async()=>({data:{id:'o',order_number:1001,status:'ordered'}}),then(resolve){return Promise.resolve({data:[]}).then(resolve)}}
      return q
    }}},
  })
  const response=await route.GET(new NextRequest('https://fixture.invalid/api/orders/track?id=LQ-1001&email=someone%40example.invalid'))
  assert.equal(response.status,200)
  assert.ok(calls.some(c=>c[0]==='orders'&&c[1]==='customer_email'&&c[2]==='someone@example.invalid'))
  assert.ok(calls.some(c=>c[0]==='order_status_logs'&&c[1]==='select'&&!c[2].includes('note')))
  const wildcard=await route.GET(new NextRequest('https://fixture.invalid/api/orders/track?id=LQ-1001&email=%25%40%25.%25'))
  assert.equal(wildcard.status,400)
})
test('signup never overwrites an existing unconfirmed account',async()=>{
  let updated=false
  const {POST}=load('app/api/auth/signup/route.ts',{
    '@/lib/supabase-admin':{supabaseAdmin:{auth:{admin:{
      createUser:async()=>({error:{message:'User already registered'}}),
      updateUserById:async()=>{updated=true;throw Error('Must never update')},
    }}}},
  })
  const response=await POST(new Request('https://fixture.invalid/api/auth/signup',{method:'POST',body:JSON.stringify({email:'f@example.invalid',password:'Str0ng!Password',firstName:'Fixture',lastName:'Test',termsAccepted:true})}))
  assert.equal(response.status,409);assert.equal(updated,false)
  const retired=load('app/api/auth/confirm-pending/route.ts')
  assert.equal((await retired.POST()).status,410)
})
test('production admin throttling is enabled even when old disable flags are set',()=>{
  const env={...process.env}
  try{
    process.env.NODE_ENV='production';process.env.ADMIN_DISABLE_LOGIN_RATE_LIMIT='1'
    const {isAdminLoginRateLimitDisabled}=load('lib/security/login-rate-limit.ts')
    assert.equal(isAdminLoginRateLimitDisabled(),false)
  }finally{process.env=env}
})
test('shortfall tax uses the purchased line tax despite a later category/rate change',()=>{
  const {computeShortfallRefund}=load('lib/orders/partial-refund.ts')
  const quote=computeShortfallRefund({lines:[{itemId:'x',productName:'Fixture',unitPrice:10,orderedQuantity:2,previousFulfilledQuantity:2,nextFulfilledQuantity:1,category:'Fresh Produce',lineTaxAmount:1.55}],taxRate:0.2,orderTaxAmount:1.55,maxRefundable:21.55})
  assert.equal(quote.taxRefund,0.78);assert.equal(quote.totalRefund,10.78)
})
test('paid fulfillment uses an old immutable quote without reading changed catalog prices',async()=>{
  let catalogRead=false, recorded, notified=0
  const quote={orderItems:[{product_id:'p',product_name:'Purchased name',product_price:10,quantity:2,subtotal:20,tax_amount:0}],subtotal:20,shipping:{fee:0,method:'pickup',zone:'local'},tax:{taxAmount:0},tip:0,total:20}
  const payload={items:[{productId:'p',quantity:2}],quote,customer_name:'Fixture',customer_phone:'6145550100',address_line:'Fixture',city:'Columbus',state:'OH',country:'US',postal_code:'43229',shipping_method:'pickup',account_email:'f@example.invalid'}
  const {fulfillOrderFromPaymentIntent}=load('lib/orders/fulfill-payment-intent.ts',{
    '@/lib/stripe':{getStripe:()=>({paymentIntents:{retrieve:async()=>({status:'succeeded',currency:'usd',amount_received:2000,metadata:{user_id:'u',checkout_snapshot_id:'s'}})}})},
    '@/lib/supabase-admin':{supabaseAdmin:{from:table=>{
      if(table==='products'){catalogRead=true;throw Error('Must not reprice')}
      return {select(){return this},eq(){return this},maybeSingle:async()=>({data:table==='orders'?null:{id:'s',user_id:'u',created_at:'2000-01-01',payload}})}
    }}},
    '@/lib/orders/record-order':{recordOrder:async(order,items)=>{recorded={order,items};return {order:{...order,id:'order'},created:true}}},
    '@/lib/email/send-order-emails':{sendOrderEmails:async()=>{notified++}},
    '@/lib/notifications/send-order-sms':{sendOrderSmsToMerchant:async()=>{}},
  })
  assert.equal((await fulfillOrderFromPaymentIntent('pi_fixture')).orderId,'order')
  assert.equal(catalogRead,false);assert.equal(recorded.order.total_amount,20);assert.equal(recorded.items[0].product_price,10);assert.equal(notified,1)
})
test('refund network retry reuses the same provider key and commits only after success',async()=>{
  let attempts=0,finishes=0
  const keys=[]
  const {executeRefund}=load('lib/orders/refund-operation.ts',{
    '@/lib/supabase-admin':{supabaseAdmin:{rpc:async(name)=>{assert.equal(name,'finish_commerce_refund');finishes++;return {data:{}}}}},
    '@/lib/stripe':{getStripe:()=>({refunds:{
      list:async function*(){},
      create:async(body,options)=>{keys.push(options.idempotencyKey);if(++attempts===1)throw Error('network');return {id:'re_ok',amount:1000,payment_intent:'pi_fixture',status:'succeeded'}},
    }})},
  })
  const op={id:'op',amount_cents:1000,state:'pending',created_at:new Date().toISOString(),payload:{paymentIntentId:'pi_fixture',response:{refunded:true}}}
  await assert.rejects(executeRefund(op),/network/);assert.equal(finishes,0)
  assert.equal((await executeRefund(op)).refundId,'re_ok');assert.equal(finishes,1)
  assert.deepEqual(keys,['commerce-refund-op','commerce-refund-op'])
})
test('old pending refund reconciles provider history without creating another refund',async()=>{
  let created=false
  const {executeRefund}=load('lib/orders/refund-operation.ts',{
    '@/lib/supabase-admin':{supabaseAdmin:{rpc:async()=>({data:{}})}},
    '@/lib/stripe':{getStripe:()=>({refunds:{
      list:async function*(){yield {id:'re_old',amount:1000,payment_intent:'pi_fixture',status:'succeeded',metadata:{commerce_operation_id:'op'}}},
      create:async()=>{created=true},
    }})},
  })
  const op={id:'op',amount_cents:1000,state:'pending',created_at:'2000-01-01',payload:{paymentIntentId:'pi_fixture',response:{}}}
  assert.equal((await executeRefund(op)).refundId,'re_old');assert.equal(created,false)
})
