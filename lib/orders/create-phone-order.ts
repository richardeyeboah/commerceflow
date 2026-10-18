import { randomUUID } from 'node:crypto'
import { recordOrder } from '@/lib/orders/record-order'
import { STORE } from '@/lib/constants/store'
import {
  MANUAL_SETTLE_OPTIONS,
  normalizeManualSettleMethod,
  type ManualSettleMethod,
  type PaymentMethod,
} from '@/lib/payment-methods'
import {
  PHONE_ORDER_PLACEHOLDER_EMAIL,
  normalizeOrderSource,
  normalizePaymentStatus,
  type OrderSource,
  type PaymentStatus,
} from '@/lib/orders/order-source'
import { calculateShipping, normalizeShippingMethod, type ShippingMethod } from '@/lib/shipping'
import { calculateSalesTax } from '@/lib/tax/sales-tax'
import { toDialable } from '@/lib/phone-link'
import { supabaseAdmin } from '@/lib/supabase-admin'

export type PhoneOrderLineInput = {
  productId: string
  quantity: number
}

export type CreatePhoneOrderInput = {
  customerName: string
  customerPhone: string
  customerEmail?: string | null
  source: OrderSource
  shippingMethod: ShippingMethod
  paymentStatus: PaymentStatus
  /** Required when paymentStatus is paid; ignored when unpaid (defaults to cash). */
  paymentMethod?: ManualSettleMethod
  addressLine?: string | null
  city?: string | null
  state?: string | null
  postalCode?: string | null
  country?: string | null
  pickupContactName?: string | null
  note?: string | null
  lines: PhoneOrderLineInput[]
}

export type CreatePhoneOrderResult =
  | { ok: true; orderId: string; orderNumber: number | null; totalAmount: number }
  | { ok: false; error: string; status: number }

function money(n: number): number {
  return Math.round(n * 100) / 100
}

export async function createPhoneOrder(
  input: CreatePhoneOrderInput
): Promise<CreatePhoneOrderResult> {
  const customerName = input.customerName.trim()
  if (customerName.length < 2) {
    return { ok: false, error: 'Customer name is required.', status: 400 }
  }

  const phone = input.customerPhone.trim()
  if (!toDialable(phone)) {
    return { ok: false, error: 'A reachable phone number is required.', status: 400 }
  }

  const source = normalizeOrderSource(input.source)
  if (source === 'online') {
    return { ok: false, error: 'Use phone, WhatsApp, or in-store for this desk.', status: 400 }
  }

  const shippingMethod = normalizeShippingMethod(input.shippingMethod)
  const paymentStatus = normalizePaymentStatus(input.paymentStatus)
  const paymentMethod: PaymentMethod =
    paymentStatus === 'paid'
      ? normalizeManualSettleMethod(input.paymentMethod)
      : normalizeManualSettleMethod(input.paymentMethod ?? 'cod')

  if (!input.lines.length) {
    return { ok: false, error: 'Add at least one item.', status: 400 }
  }

  const qtyById = new Map<string, number>()
  for (const line of input.lines) {
    const id = typeof line.productId === 'string' ? line.productId.trim() : ''
    const qty = Math.trunc(Number(line.quantity))
    if (!id || !Number.isFinite(qty) || qty < 1 || qty > 99) {
      return { ok: false, error: 'Each line needs a product and quantity 1–99.', status: 400 }
    }
    qtyById.set(id, (qtyById.get(id) ?? 0) + qty)
  }

  const productIds = [...qtyById.keys()]
  const { data: products, error: productsError } = await supabaseAdmin
    .from('products')
    .select('id, name, price, category')
    .in('id', productIds)

  if (productsError) {
    console.error('[phone-order] products', productsError.message)
    return { ok: false, error: 'Could not load products.', status: 500 }
  }

  if (!products || products.length !== productIds.length) {
    return { ok: false, error: 'One or more products were not found.', status: 400 }
  }

  const productById = new Map(products.map((p) => [p.id as string, p]))
  const itemRows: Array<{
    product_id: string
    product_name: string
    product_price: number
    quantity: number
    subtotal: number
    category: string
  }> = []

  let subtotal = 0
  for (const [productId, quantity] of qtyById) {
    const product = productById.get(productId)!
    const price = money(Number(product.price ?? 0))
    if (price <= 0) {
      return { ok: false, error: `${product.name} has no price.`, status: 400 }
    }
    const lineSubtotal = money(price * quantity)
    subtotal = money(subtotal + lineSubtotal)
    itemRows.push({
      product_id: productId,
      product_name: String(product.name ?? 'Item'),
      product_price: price,
      quantity,
      subtotal: lineSubtotal,
      category: String(product.category ?? ''),
    })
  }

  const needsAddress = shippingMethod !== 'pickup'
  const addressLine = (input.addressLine ?? '').trim()
  const city = (input.city ?? '').trim()
  const state = (input.state ?? '').trim()
  const postalCode = (input.postalCode ?? '').trim()
  const country = (input.country ?? 'United States').trim() || 'United States'

  if (needsAddress && (!addressLine || !city || !state || !postalCode)) {
    return {
      ok: false,
      error: 'Address, city, state, and ZIP are required for delivery or shipping.',
      status: 400,
    }
  }

  const shipping = calculateShipping({
    subtotal,
    country,
    state: needsAddress ? state : 'OH',
    method: shippingMethod,
  })

  const tax = calculateSalesTax(
    itemRows.map((r) => ({ category: r.category, lineSubtotal: r.subtotal })),
    {
      country: needsAddress ? country : 'United States',
      state: needsAddress ? state : 'OH',
      shippingMethod,
    }
  )

  const totalAmount = money(subtotal + shipping.fee + tax.taxAmount)
  const email = (input.customerEmail ?? '').trim() || PHONE_ORDER_PLACEHOLDER_EMAIL
  const nowIso = new Date().toISOString()
  const paidAt = paymentStatus === 'paid' ? nowIso : null
  const note = (input.note ?? '').trim().slice(0, 500)
  const pickupContactName = (input.pickupContactName ?? '').trim().slice(0, 120) || null

  const baseOrder = {
    id: randomUUID(),
    customer_name: customerName.slice(0, 120),
    customer_email: email.slice(0, 200),
    customer_phone: phone.slice(0, 40),
    address_line: needsAddress ? addressLine.slice(0, 200) : STORE.address,
    city: needsAddress ? city.slice(0, 80) : STORE.shipFrom.city,
    state: needsAddress ? state.slice(0, 40) : STORE.shipFrom.state,
    country: needsAddress ? country.slice(0, 80) : 'United States',
    postal_code: needsAddress ? postalCode.slice(0, 20) : STORE.shipFrom.zip,
    subtotal_amount: subtotal,
    shipping_fee: shipping.fee,
    tax_amount: tax.taxAmount,
    shipping_method: shippingMethod,
    shipping_zone: shipping.zone,
    total_amount: totalAmount,
    status: 'ordered' as const,
    ordered_at: nowIso,
    payment_method: paymentMethod,
    payment_status: paymentStatus,
    paid_at: paidAt,
    order_source: source,
    user_id: null,
    stripe_checkout_session_id: null,
    stripe_payment_intent_id: null,
  }

  let order: { id: string; order_number: number | null }
  try {
    const recorded = await recordOrder({ ...baseOrder, pickup_contact_name: pickupContactName }, itemRows)
    order = recorded.order
  } catch (error) {
    console.error('[phone-order] transaction failed', error)
    return { ok: false, error: 'Could not record the order. No partial order was saved.', status: 500 }
  }

  const logNoteParts = [
    `Source: ${source}`,
    `Payment: ${paymentStatus}${paymentStatus === 'paid' ? ` (${paymentMethod})` : ''}`,
    note ? `Note: ${note}` : null,
  ].filter(Boolean)

  await supabaseAdmin.from('order_status_logs').insert({
    order_id: order.id,
    from_status: null,
    to_status: 'ordered',
    changed_by: 'admin',
    note: logNoteParts.join(' · '),
  })

  return {
    ok: true,
    orderId: order.id,
    orderNumber: order.order_number,
    totalAmount,
  }
}

export { MANUAL_SETTLE_OPTIONS }
