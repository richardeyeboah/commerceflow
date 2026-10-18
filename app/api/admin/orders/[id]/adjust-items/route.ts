import { NextRequest, NextResponse } from 'next/server'
import { requireAdminApi } from '@/lib/auth/require-admin-api'
import { supabaseAdmin } from '@/lib/supabase-admin'
import { assertSameOrigin } from '@/lib/security/same-origin'
import { getStoreSalesTaxRate } from '@/lib/tax/sales-tax'
import {
  computeShortfallRefund,
  type ShortfallLineInput,
} from '@/lib/orders/partial-refund'
import { executeRefund, findRefundOperation, prepareRefund, refundRequestKey } from '@/lib/orders/refund-operation'

type IncomingLine = { itemId?: unknown; fulfilledQuantity?: unknown }

/**
 * Record what was actually handed over and refund the difference.
 *
 * `preview: true` runs the same math and returns the quote without touching
 * Stripe or the database, so the admin UI and the server always agree on the
 * amount before anyone clicks refund.
 */
export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const originCheck = assertSameOrigin(req)
  if (!originCheck.ok) return originCheck.response

  const auth = await requireAdminApi()
  if (!auth.ok) return auth.response

  try {
    const { id } = await params
    const body = await req.json()
    const preview = body?.preview === true
    const reason = typeof body?.reason === 'string' ? body.reason.slice(0, 200).trim() : ''
    const incoming: IncomingLine[] = Array.isArray(body?.lines) ? body.lines.slice(0, 200) : []

    if (!incoming.length) {
      return NextResponse.json({ error: 'No item quantities were provided.' }, { status: 400 })
    }

    const key = preview ? null : refundRequestKey(req)
    const fingerprint = JSON.stringify({ reason, lines: [...incoming].sort((a,b) => String(a.itemId).localeCompare(String(b.itemId))) })
    if (key) {
      const previous = await findRefundOperation(key, id, 'shortfall', fingerprint)
      if (previous) return NextResponse.json(await executeRefund(previous))
    }

    const requestedByItem = new Map<string, number>()
    for (const line of incoming) {
      if (typeof line?.itemId !== 'string') continue
      const qty = Number(line.fulfilledQuantity)
      if (!Number.isFinite(qty) || qty < 0) continue
      requestedByItem.set(line.itemId, Math.trunc(qty))
    }
    if (!requestedByItem.size) {
      return NextResponse.json({ error: 'No valid item quantities were provided.' }, { status: 400 })
    }

    const { data: order, error: orderErr } = await supabaseAdmin
      .from('orders')
      .select('*')
      .eq('id', id)
      .single()

    if (orderErr || !order) {
      return NextResponse.json({ error: 'Order not found.' }, { status: 404 })
    }

    const { data: items, error: itemsErr } = await supabaseAdmin
      .from('order_items')
      .select('*')
      .eq('order_id', id)

    if (itemsErr || !items?.length) {
      return NextResponse.json({ error: 'This order has no items.' }, { status: 400 })
    }

    // Categories drive whether a refunded line carries sales tax back.
    const productIds = Array.from(
      new Set(
        items
          .map((i) => i.product_id)
          .filter((v): v is string => typeof v === 'string')
      )
    )
    const { data: productRows } = productIds.length
      ? await supabaseAdmin.from('products').select('id, category').in('id', productIds)
      : { data: [] }
    const categoryByProduct = new Map(
      (productRows ?? []).map((p) => [p.id as string, (p.category as string | null) ?? ''])
    )

    const orderRecord = order as Record<string, unknown>
    const lines: ShortfallLineInput[] = items
      .filter((item) => requestedByItem.has(item.id))
      .map((item) => {
        const ordered = Number(item.quantity ?? 0)
        const recorded = (item as Record<string, unknown>).fulfilled_quantity
        const previousFulfilled =
          typeof recorded === 'number' && Number.isFinite(recorded) ? recorded : ordered
        return {
          itemId: item.id,
          productName: String(item.product_name ?? 'Item'),
          unitPrice: Number(item.product_price ?? 0),
          orderedQuantity: ordered,
          previousFulfilledQuantity: previousFulfilled,
          nextFulfilledQuantity: requestedByItem.get(item.id) ?? previousFulfilled,
          lineTaxAmount: item.tax_amount == null ? undefined : Number(item.tax_amount),
          category:
            typeof item.product_id === 'string'
              ? (categoryByProduct.get(item.product_id) ?? '')
              : '',
        }
      })

    if (!lines.length) {
      return NextResponse.json({ error: 'None of those items belong to this order.' }, { status: 400 })
    }

    const orderTotal = Number(order.total_amount ?? 0)
    const alreadyRefunded = Number(order.refund_amount ?? 0)
    const maxRefundable = Math.max(0, Math.round((orderTotal - alreadyRefunded) * 100) / 100)

    const quote = computeShortfallRefund({
      lines,
      taxRate: getStoreSalesTaxRate(),
      orderTaxAmount: Number(orderRecord.tax_amount ?? 0),
      maxRefundable,
    })

    if (preview) {
      return NextResponse.json({ ok: true, preview: true, quote, maxRefundable })
    }

    const isStripe =
      order.payment_method === 'stripe' && typeof order.stripe_payment_intent_id === 'string'
    // No money was collected on an unpaid phone order — nothing to refund;
    // the shortfall just reduces what staff should collect at handoff.
    const isUnpaid = orderRecord.payment_status === 'unpaid'

    if (lines.some((line) => line.nextFulfilledQuantity > line.previousFulfilledQuantity)) {
      return NextResponse.json({ error: 'Fulfilled quantities cannot increase after an adjustment. Contact the customer to arrange a new purchase.' }, { status: 400 })
    }
    const op = await prepareRefund({
      key: key!, orderId: id, kind: 'shortfall',
      amountCents: isUnpaid ? 0 : Math.round(quote.totalRefund * 100),
      expectedRefund: alreadyRefunded,
      payload: { fingerprint, reason,
        paymentIntentId: isStripe && !isUnpaid ? order.stripe_payment_intent_id : null,
        lines: quote.lines.map((line) => ({ itemId: line.itemId,
          previousQuantity: lines.find((input) => input.itemId === line.itemId)!.previousFulfilledQuantity,
          fulfilledQuantity: line.fulfilledQuantity })),
        notification: quote.shortLines.length && order.customer_email ? {
          order: { id, order_number: order.order_number ?? null, customer_name: order.customer_name ?? 'there',
            customer_email: order.customer_email, total_amount: orderTotal, shipping_method: order.shipping_method ?? null },
          shortLines: quote.shortLines, refundAmount: !isUnpaid ? quote.totalRefund : 0,
        } : undefined,
        response: { quote, refunded: !isUnpaid && quote.totalRefund > 0, unpaid: isUnpaid },
      },
    })
    return NextResponse.json(await executeRefund(op))
  } catch (e) {
    const message = e instanceof Error ? e.message : 'Server error.'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
