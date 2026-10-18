/* eslint-disable @typescript-eslint/no-require-imports -- Node fixture server uses CommonJS. */
// Local simulator fixture. Database/account data stays in memory; Stripe calls
// are refused unless BOTH configured keys are explicitly test-mode keys.
const http = require('node:http')
const Stripe = require('stripe')
const secret = process.env.STRIPE_SECRET_KEY || ''
const publishableKey = process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY || ''
if (!secret.startsWith('sk_test_') || !publishableKey.startsWith('pk_test_')) throw Error('Test Stripe keys required')
const stripe = new Stripe(secret)
const createdAt = '2026-01-01T00:00:00Z'
const products = [
  { id: '11111111-1111-4111-8111-111111111111', name: 'Test Yam', price: 5, category: 'Fresh Produce', in_stock: true, created_at: createdAt, stock_quantity: 2 },
  { id: '22222222-2222-4222-8222-222222222222', name: 'Test Rice', price: 10, category: 'Flours & Rice', in_stock: true, created_at: createdAt, stock_quantity: 8 },
]
let profile = { id: '33333333-3333-4333-8333-333333333333', full_name: 'Test Shopper', phone: '2025550148', role: 'customer' }
const intents = new Map()
const orders = []
const user = { id: profile.id, email: 'shopper@example.com' }
const token = ['e30', Buffer.from(JSON.stringify({ sub: user.id })).toString('base64url'), 'fixture'].join('.')
http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1:4317')
  const chunks = []
  for await (const chunk of req) chunks.push(chunk)
  const body = chunks.length ? JSON.parse(Buffer.concat(chunks)) : {}
  const send = (status, data) => { res.writeHead(status, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(data)) }
  try {
    console.log(req.method, url.pathname)
    if (url.pathname === '/auth/v1/token') return send(200, { access_token: token, refresh_token: 'fixture-refresh', expires_in: 3600, user })
    if (url.pathname === '/api/auth/signup') { profile.full_name = `${body.firstName} ${body.lastName}`; return send(200, { ok: true }) }
    if (url.pathname === '/rest/v1/profiles') return send(200, [profile])
    if (url.pathname === '/rest/v1/products') {
      const id = url.searchParams.get('id')
      return send(200, id?.startsWith('eq.') ? products.filter(p => p.id === id.slice(3)) : products)
    }
    if (url.pathname === '/rest/v1/orders') return send(200, orders)
    if (url.pathname.startsWith('/rest/v1/')) return send(200, [])
    if (url.pathname === '/api/mobile/checkout/payment-intent') {
      if (!body.name?.trim() || !body.phone?.trim()) return send(400, { error: 'Enter a name and phone number.' })
      const total = body.items.reduce((sum, item) => sum + products.find(p => p.id === item.product.id).price * item.quantity, 0)
      const pi = await stripe.paymentIntents.create({ amount: Math.round(total * 100), currency: 'usd', payment_method_types: ['card'], metadata: { purpose: 'local-simulator-regression' } })
      intents.set(pi.id, { total, email: body.email })
      return send(200, { clientSecret: pi.client_secret, paymentIntentId: pi.id, publishableKey, subtotal: total, shippingFee: 0, taxAmount: 0, total })
    }
    if (url.pathname === '/api/mobile/checkout/status') {
      const id = url.searchParams.get('payment_intent')
      const fixture = intents.get(id)
      if (!fixture) return send(404, { error: 'Unknown test payment' })
      const pi = await stripe.paymentIntents.retrieve(id)
      if (pi.status !== 'succeeded') return send(200, { status: 'unpaid', paymentStatus: pi.status })
      if (!orders.length) orders.push({ id: 'fixture-order-1', order_number: 1042, created_at: createdAt, status: 'ordered', total_amount: fixture.total, customer_email: fixture.email })
      return send(200, { status: 'complete', orderId: orders[0].id, orderNumber: 1042, totalAmount: fixture.total })
    }
    if (url.pathname === '/api/orders/track') {
      if (!orders.length) return send(404, { error: 'No completed test order' })
      return send(200, { order: orders[0], items: [], logs: [] })
    }
    send(404, { error: 'Unknown fixture route' })
  } catch (error) { console.error(error.type ?? error.name); send(500, { error: 'Fixture request failed' }) }
}).listen(4317, '127.0.0.1', () => console.log('Fixture server ready on loopback port 4317; Stripe TEST mode only'))
