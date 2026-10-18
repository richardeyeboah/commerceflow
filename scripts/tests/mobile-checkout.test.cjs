const { test } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const ts = require('typescript')
const { NextRequest } = require('next/server')

// Execute the real route with isolated service boundaries. No keys, database,
// payment provider, or customer notifications are contacted by these tests.
function route(path, mocks) {
  const js = ts.transpileModule(fs.readFileSync(path, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  }).outputText
  const module = { exports: {} }
  const load = name => {
    if (name in mocks) return mocks[name]
    if (name === '@/lib/security/request-rate-limit') return { limitPublicRequest: async () => null }
    if (name.startsWith('@/')) return {}
    return require(name)
  }
  new Function('require', 'module', 'exports', js)(load, module, module.exports)
  return module.exports
}

test('invalid bearer fails before checkout data or payments are written', async () => {
  let databaseTouched = false
  const handler = route('app/api/mobile/checkout/payment-intent/route.ts', {
    '@/lib/supabase/config': { getSupabasePublicConfig: () => ({ configured: true, url: 'https://fixture.invalid', anonKey: 'fixture' }) },
    '@supabase/supabase-js': { createClient: () => ({ auth: { getUser: async token => {
      assert.equal(token, 'expired')
      return { data: { user: null }, error: { message: 'expired' } }
    } } }) },
    '@/lib/supabase-admin': { supabaseAdmin: { from: () => { databaseTouched = true; throw Error('Unexpected DB call') } } },
  })
  const response = await handler.POST(new NextRequest('https://fixture.invalid/api/mobile/checkout/payment-intent', {
    method: 'POST', headers: { authorization: 'Bearer expired' }, body: '{}',
  }))
  assert.equal(response.status, 401)
  assert.equal(databaseTouched, false)
})

for (const count of [0, 2]) {
  test(`paid order with ${count} items is ${count ? 'confirmed' : 'pending'}`, async () => {
    const handler = route('app/api/mobile/checkout/status/route.ts', {
      '@/lib/stripe': { getStripe: () => ({ paymentIntents: { retrieve: async () => ({ status: 'succeeded', metadata: {} }) } }) },
      '@/lib/orders/guest-checkout': { resolveCheckoutMode: () => 'guest', GUEST_CHECKOUT_MODE: 'guest' },
      '@/lib/supabase-admin': { supabaseAdmin: { from: table => {
        const query = {
          select() { return this }, eq() { return this },
          maybeSingle: async () => ({ data: { id: 'order-1', total_amount: 20 } }),
          then(resolve) { return Promise.resolve({ count, error: null }).then(resolve) },
        }
        assert.ok(['orders', 'order_items'].includes(table))
        return query
      } } },
    })
    const response = await handler.GET(new NextRequest('https://fixture.invalid/api/mobile/checkout/status?payment_intent=pi_fixture'))
    assert.equal((await response.json()).status, count ? 'complete' : 'processing')
  })
}
