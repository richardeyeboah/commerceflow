import { NextRequest, NextResponse } from 'next/server'
import { requireAdminApi } from '@/lib/auth/require-admin-api'
import { supabaseAdmin } from '@/lib/supabase-admin'
import { assertSameOrigin } from '@/lib/security/same-origin'
import { executeRefund, findRefundOperation, prepareRefund, refundRequestKey } from '@/lib/orders/refund-operation'

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const origin = assertSameOrigin(req)
  if (!origin.ok) return origin.response
  const auth = await requireAdminApi()
  if (!auth.ok) return auth.response
  try {
    const { id } = await params
    const key = refundRequestKey(req)
    const body = await req.json()
    const amountCents = Math.round(Number(body.amount) * 100)
    const reason = typeof body.reason === 'string' ? body.reason.trim().slice(0, 200) : ''
    if (!Number.isSafeInteger(amountCents) || amountCents <= 0) {
      return NextResponse.json({ error: 'Invalid refund amount.' }, { status: 400 })
    }
    const fingerprint = JSON.stringify({ amountCents, reason })
    const previous = await findRefundOperation(key, id, 'refund', fingerprint)
    if (previous) return NextResponse.json(await executeRefund(previous))
    const { data: order, error } = await supabaseAdmin.from('orders')
      .select('id,payment_method,stripe_payment_intent_id,total_amount,refund_amount').eq('id', id).single()
    if (error || !order) return NextResponse.json({ error: 'Order not found.' }, { status: 404 })
    if (order.payment_method !== 'stripe' || !order.stripe_payment_intent_id) {
      return NextResponse.json({ error: 'Order has no Stripe payment.' }, { status: 400 })
    }
    const op = await prepareRefund({ key, orderId: id, kind: 'refund', amountCents,
      expectedRefund: Number(order.refund_amount ?? 0),
      payload: { fingerprint, reason, paymentIntentId: order.stripe_payment_intent_id, response: {} } })
    return NextResponse.json(await executeRefund(op))
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Refund failed.' }, { status: 409 })
  }
}
