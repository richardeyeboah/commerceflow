import { recordOrder } from '@/lib/orders/record-order'
import type Stripe from 'stripe'
import { supabaseAdmin } from '@/lib/supabase-admin'
import { sendOrderEmails } from '@/lib/email/send-order-emails'
import { sendOrderSmsToMerchant } from '@/lib/notifications/send-order-sms'
import type { AuthoritativeOrderItem } from '@/lib/order-pricing'
import { getStripe } from '@/lib/stripe'

function isProductObject(
  p: string | Stripe.Product | Stripe.DeletedProduct | null | undefined
): p is Stripe.Product {
  return typeof p === 'object' && p !== null && !('deleted' in p && (p as Stripe.DeletedProduct).deleted)
}

/**
 * Creates order + items + emails after Stripe confirms payment.
 * Idempotent: same checkout session only creates one order.
 */
export async function fulfillOrderFromStripeSession(sessionId: string): Promise<{ orderId: string; created: boolean }> {
  const stripe = getStripe()

  const { data: existing } = await supabaseAdmin
    .from('orders')
    .select('id')
    .eq('stripe_checkout_session_id', sessionId)
    .maybeSingle()

  if (existing?.id) {
    const { count, error } = await supabaseAdmin.from('order_items').select('id', { count: 'exact', head: true }).eq('order_id', existing.id)
    if (error) throw new Error(error.message)
    if (count) return { orderId: existing.id, created: false }
  }

  const session = await stripe.checkout.sessions.retrieve(sessionId)

  if (session.payment_status !== 'paid') {
    console.warn('[stripe] session not paid, skipping fulfillment', sessionId, session.payment_status)
    return { orderId: '', created: false }
  }

  const lineItemsRes = stripe.checkout.sessions.listLineItems(sessionId, {
    limit: 100,
    expand: ['data.price.product'],
  })

  const userId = session.metadata?.user_id?.trim()
  if (!userId) {
    throw new Error('Missing user_id in Checkout Session metadata')
  }

  const customerName = session.metadata?.customer_name?.trim() ?? ''
  const customerPhone = session.metadata?.customer_phone?.trim() ?? ''
  const addressLine = session.metadata?.address_line?.trim() ?? ''
  const city = session.metadata?.city?.trim() ?? ''
  const state = session.metadata?.state?.trim() || null
  const country = session.metadata?.country?.trim() ?? ''
  const postalCode = session.metadata?.postal_code?.trim() || null
  const shippingMethod = session.metadata?.shipping_method?.trim() ?? 'standard'
  const shippingZone = session.metadata?.shipping_zone?.trim() || null

  const customerEmail = session.customer_details?.email?.trim().toLowerCase() ?? session.customer_email?.trim().toLowerCase()
  if (!customerEmail) {
    throw new Error('Missing customer email on Checkout Session')
  }

  const lineItems: Stripe.LineItem[] = []
  for await (const line of lineItemsRes) lineItems.push(line)
  const orderItems: AuthoritativeOrderItem[] = []
  let shippingFee = 0
  let taxAmount = 0

  for (const li of lineItems) {
    const price = li.price
    if (!price) continue
    const product = price.product
    if (!isProductObject(product)) continue
    const meta = product.metadata ?? {}
    if (meta.type === 'shipping') {
      shippingFee += (li.amount_total ?? 0) / 100
      continue
    }
    if (meta.type === 'tax') {
      taxAmount += (li.amount_total ?? 0) / 100
      continue
    }
    const productId = meta.product_id?.trim()
    if (!productId) continue
    const qty = li.quantity ?? 0
    const unit = (li.amount_total ?? 0) / 100 / Math.max(qty, 1)
    const subtotal = (li.amount_total ?? 0) / 100
    orderItems.push({
      product_id: productId,
      product_name: product.name,
      product_price: unit,
      quantity: qty,
      subtotal,
    })
  }

  if (orderItems.length === 0) {
    throw new Error('No product line items found on paid Checkout Session')
  }

  const subtotal = orderItems.reduce((s, i) => s + i.subtotal, 0)
  const totalFromStripe = (session.amount_total ?? 0) / 100
  const computedTotal = Number((subtotal + shippingFee + taxAmount).toFixed(2))
  if (session.currency !== 'usd' || Math.round(computedTotal * 100) !== Math.round(totalFromStripe * 100)) {
    console.error('[stripe] total mismatch', { computedTotal, totalFromStripe, sessionId })
    throw new Error('Order total mismatch — manual review required')
  }

  const paymentIntentId =
    typeof session.payment_intent === 'string'
      ? session.payment_intent
      : session.payment_intent?.id ?? null

  const { order, created } = await recordOrder({
      customer_name: customerName,
      customer_email: customerEmail,
      customer_phone: customerPhone,
      address_line: addressLine,
      city,
      state,
      country,
      postal_code: postalCode,
      subtotal_amount: subtotal,
      shipping_fee: shippingFee,
      tax_amount: taxAmount,
      shipping_method: shippingMethod,
      shipping_zone: shippingZone,
      total_amount: totalFromStripe,
      status: 'ordered',
      ordered_at: new Date().toISOString(),
      payment_method: 'stripe',
      user_id: userId,
      stripe_checkout_session_id: sessionId,
      stripe_payment_intent_id: paymentIntentId,
    }, orderItems)
  if (!created) return { orderId: order.id, created: false }

  try {
    await sendOrderEmails(
      {
        id: order.id,
        order_number: order.order_number ?? null,
        customer_name: order.customer_name,
        customer_email: order.customer_email,
        customer_phone: order.customer_phone,
        address_line: order.address_line,
        city: order.city,
        state: order.state,
        country: order.country,
        postal_code: order.postal_code,
        subtotal_amount: Number(order.subtotal_amount),
        shipping_fee: Number(order.shipping_fee),
        tax_amount: Number((order as { tax_amount?: number }).tax_amount ?? taxAmount),
        total_amount: Number(order.total_amount),
        shipping_method: order.shipping_method,
        payment_method: order.payment_method,
      },
      orderItems
    )
  } catch (e) {
    console.error('[stripe] post-order email error:', e)
  }

  try {
    await sendOrderSmsToMerchant({
      orderId: order.id,
      orderNumber: order.order_number ?? null,
      customerName: order.customer_name,
      totalAmount: Number(order.total_amount),
      city: order.city,
    })
  } catch (e) {
    console.error('[stripe] post-order SMS error:', e)
  }

  return { orderId: order.id, created: true }
}
