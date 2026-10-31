/* eslint-disable @typescript-eslint/no-require-imports -- Node CommonJS simulator fixture. */
// Local simulator fixture. Database/account data stays in memory; Stripe calls
// are refused unless BOTH configured keys are explicitly test-mode keys.
const http = require('node:http')
const secret = process.env.STRIPE_SECRET_KEY || ''
const publishableKey = process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY || ''
// Without test keys the fixture still serves browsing, accounts and store-manager routes.
const stripe = secret.startsWith('sk_test_') && publishableKey.startsWith('pk_test_') ? new (require('stripe'))(secret) : null
const createdAt = '2026-01-01T00:00:00Z'
const products = [
  { id: '11111111-1111-4111-8111-111111111111', name: 'Test Yam', price: 5, category: 'Fresh Produce', in_stock: true, created_at: createdAt, stock_quantity: 2 },
  { id: '22222222-2222-4222-8222-222222222222', name: 'Test Rice', price: 10, category: 'Flours & Rice', in_stock: true, created_at: createdAt, stock_quantity: 8 },
]
let profile = { id: '33333333-3333-4333-8333-333333333333', full_name: 'Test Shopper', phone: '2025550148', role: 'customer' }
const intents = new Map()
const orders = []
// Store-manager fixture: password `fixture-admin`, plus one pickup order so the queue is never empty.
const adminCookie = 'admin_session=fixture-admin-session'
const staffOrders = [{ id: '44444444-4444-4444-8444-444444444444', order_number: 1001, created_at: createdAt, status: 'ordered', customer_name: 'Ama Mensah', customer_email: 'ama@example.com', customer_phone: '6145550123', total_amount: 15, shipping_method: 'pickup', pickup_contact_name: 'Ama Mensah', tracking_number: null }]
const staffItems = { [staffOrders[0].id]: [{ id: 'item-1', product_id: products[0].id, product_name: 'Test Yam', product_price: 5, quantity: 3 }] }
const statusLogs = {}
const allOrders = () => [...orders, ...staffOrders]
const isAdmin = (req) => (req.headers.cookie ?? '').split(/;\s*/).includes(adminCookie)
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
    if (url.pathname.startsWith('/api/mobile/checkout/') && !stripe) return send(503, { error: 'Fixture needs Stripe TEST keys for checkout.' })
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
    if (url.pathname === '/api/feedback') {
      if (!body.email?.includes('@') || (body.message ?? '').trim().length < 10) return send(400, { error: 'Message must be at least 10 characters.' })
      return send(200, { ok: true })
    }
    if (url.pathname === '/api/admin/login') {
      if (body.password !== 'fixture-admin') return send(401, { error: 'Invalid password.' })
      res.setHeader('Set-Cookie', `${adminCookie}; Path=/; HttpOnly; SameSite=Lax; Max-Age=28800`)
      return send(200, { success: true })
    }
    if (url.pathname.startsWith('/api/admin/')) {
      if (!isAdmin(req)) return send(401, { error: 'Unauthorized.' })
      if (url.pathname === '/api/admin/logout') {
        res.setHeader('Set-Cookie', 'admin_session=; Path=/; Max-Age=0')
        return send(200, { success: true })
      }
      if (url.pathname === '/api/admin/orders') {
        const status = url.searchParams.get('status')
        const q = (url.searchParams.get('q') ?? '').toLowerCase()
        const needsAction = !status && !q && url.searchParams.get('queue') !== 'all'
        const list = allOrders().filter(o =>
          (!status || o.status === status) &&
          (!needsAction || ['ordered', 'processing', 'ready_for_pickup'].includes(o.status)) &&
          (!q || `${o.customer_name} ${o.customer_email} lq-${o.order_number}`.toLowerCase().includes(q)))
        return send(200, { queue: needsAction ? 'needs_action' : 'all', orders: list })
      }
      const order = allOrders().find(o => url.pathname === `/api/admin/orders/${o.id}`)
      if (!order) return send(404, { error: 'Order not found.' })
      if (req.method === 'PATCH') {
        if (order.shipping_method === 'pickup' && ['shipped', 'out_for_delivery'].includes(body.status)) return send(400, { error: 'Pickup orders cannot be marked shipped or out for delivery.' })
        ;(statusLogs[order.id] ??= []).push({ id: `log-${Date.now()}`, from_status: order.status, to_status: body.status, changed_at: new Date().toISOString(), changed_by: 'admin', note: body.note || null })
        order.status = body.status
        order.tracking_number = body.trackingNumber || null
        return send(200, order)
      }
      return send(200, { order, items: staffItems[order.id] ?? [], logs: statusLogs[order.id] ?? [] })
    }
    if (url.pathname === '/api/orders/track') {
      if (!orders.length) return send(404, { error: 'No completed test order' })
      return send(200, { order: orders[0], items: [], logs: [] })
    }
    send(404, { error: 'Unknown fixture route' })
  } catch (error) { console.error(error.type ?? error.name); send(500, { error: 'Fixture request failed' }) }
}).listen(4317, '127.0.0.1', () => console.log(`Fixture server ready on loopback port 4317; checkout ${stripe ? 'uses Stripe TEST mode' : 'disabled (no test keys)'}`))
