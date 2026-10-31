import { NextRequest, NextResponse } from 'next/server'
import { requireAdminApi } from '@/lib/auth/require-admin-api'
import { assertSameOrigin } from '@/lib/security/same-origin'
import { createPhoneOrder } from '@/lib/orders/create-phone-order'
import { normalizeOrderSource, normalizePaymentStatus } from '@/lib/orders/order-source'
import { normalizeManualSettleMethod } from '@/lib/payment-methods'
import { normalizeShippingMethod } from '@/lib/shipping'
import { supabaseAdmin } from '@/lib/supabase-admin'
import { normalizeOrderStatus } from '@/lib/order-status'
import { NEEDS_ACTION_STATUSES } from '@/lib/admin/ops-health'
import { parseOrderRef } from '@/lib/orders/order-number'

export const runtime = 'nodejs'

const LIST_LIMIT = 50

/**
 * Admin order queue for the native app. Mirrors the `/admin/orders` page filters:
 * `queue=needs_action` (default), `queue=all`, `status=<status>`, and `q=<name|email|LQ-number>`.
 */
export async function GET(req: NextRequest) {
  const auth = await requireAdminApi()
  if (!auth.ok) return auth.response

  const params = req.nextUrl.searchParams
  const rawStatus = params.get('status')?.trim()
  const status = rawStatus ? normalizeOrderStatus(rawStatus) : null
  // PostgREST `or()` treats , ( ) as syntax, so strip them from free-text search.
  const term = (params.get('q') ?? '').replace(/[,()%*"\\]/g, ' ').trim().slice(0, 80)
  const queue = status || term ? 'all' : params.get('queue') === 'all' ? 'all' : 'needs_action'

  let query = supabaseAdmin
    .from('orders')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(LIST_LIMIT)

  if (status) query = query.eq('status', status)
  else if (queue === 'needs_action') query = query.in('status', [...NEEDS_ACTION_STATUSES])

  if (term) {
    const ref = parseOrderRef(term)
    const filters = [`customer_name.ilike.%${term}%`, `customer_email.ilike.%${term}%`]
    if (ref?.type === 'number') filters.push(`order_number.eq.${ref.value}`)
    if (ref?.type === 'uuid') filters.push(`id.eq.${ref.value}`)
    query = query.or(filters.join(','))
  }

  const { data, error } = await query
  if (error) {
    console.error('[admin/orders GET] failed:', error.message)
    return NextResponse.json({ error: 'Could not load orders.' }, { status: 500 })
  }

  return NextResponse.json({
    queue,
    orders: (data ?? []).map((row) => ({
      id: row.id,
      order_number: row.order_number ?? null,
      created_at: row.created_at,
      status: normalizeOrderStatus(row.status),
      customer_name: row.customer_name ?? null,
      customer_email: row.customer_email ?? null,
      customer_phone: row.customer_phone ?? null,
      total_amount: row.total_amount ?? null,
      shipping_method: row.shipping_method ?? null,
      tracking_number: row.tracking_number ?? null,
      payment_status: row.payment_status ?? null,
      city: row.city ?? null,
    })),
  })
}

export async function POST(req: NextRequest) {
  const originCheck = assertSameOrigin(req)
  if (!originCheck.ok) return originCheck.response

  const auth = await requireAdminApi()
  if (!auth.ok) return auth.response

  const body = await req.json().catch(() => null)
  if (!body || typeof body !== 'object') {
    return NextResponse.json({ error: 'Invalid body.' }, { status: 400 })
  }

  const linesRaw = Array.isArray(body.lines) ? body.lines : []
  const lines = linesRaw
    .map((line: unknown) => {
      if (!line || typeof line !== 'object') return null
      const row = line as Record<string, unknown>
      return {
        productId: typeof row.productId === 'string' ? row.productId : '',
        quantity: Number(row.quantity),
      }
    })
    .filter((l: { productId: string; quantity: number } | null): l is { productId: string; quantity: number } =>
      Boolean(l)
    )

  const result = await createPhoneOrder({
    customerName: typeof body.customerName === 'string' ? body.customerName : '',
    customerPhone: typeof body.customerPhone === 'string' ? body.customerPhone : '',
    customerEmail: typeof body.customerEmail === 'string' ? body.customerEmail : null,
    source: normalizeOrderSource(body.source),
    shippingMethod: normalizeShippingMethod(
      typeof body.shippingMethod === 'string' ? body.shippingMethod : 'pickup'
    ),
    paymentStatus: normalizePaymentStatus(body.paymentStatus),
    paymentMethod: normalizeManualSettleMethod(body.paymentMethod),
    addressLine: typeof body.addressLine === 'string' ? body.addressLine : null,
    city: typeof body.city === 'string' ? body.city : null,
    state: typeof body.state === 'string' ? body.state : null,
    postalCode: typeof body.postalCode === 'string' ? body.postalCode : null,
    country: typeof body.country === 'string' ? body.country : null,
    pickupContactName:
      typeof body.pickupContactName === 'string' ? body.pickupContactName : null,
    note: typeof body.note === 'string' ? body.note : null,
    lines,
  })

  if (!result.ok) {
    return NextResponse.json({ error: result.error }, { status: result.status })
  }

  return NextResponse.json({
    ok: true,
    orderId: result.orderId,
    orderNumber: result.orderNumber,
    totalAmount: result.totalAmount,
  })
}
