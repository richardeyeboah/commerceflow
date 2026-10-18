import { NextRequest, NextResponse } from 'next/server'
import { requireAdminApi } from '@/lib/auth/require-admin-api'
import { assertSameOrigin } from '@/lib/security/same-origin'
import { supabaseAdmin } from '@/lib/supabase-admin'
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
    const reason = typeof body.reason === 'string' ? body.reason.trim().slice(0,200) : ''
    const fingerprint = JSON.stringify({ manual: true, reason })
    const previous = await findRefundOperation(key,id,'refund',fingerprint)
    if (previous) return NextResponse.json(await executeRefund(previous))
    const { data: order, error } = await supabaseAdmin.from('orders').select('payment_method,payment_status,total_amount,refund_amount').eq('id',id).single()
    if (error || !order) return NextResponse.json({ error: 'Order not found.' }, { status: 404 })
    if (order.payment_method === 'stripe' || order.payment_status === 'unpaid') return NextResponse.json({ error: 'Use Stripe refund tools for card payments. Unpaid orders have no collected payment to refund.' }, { status: 400 })
    const amountCents = Math.round((Number(order.total_amount)-Number(order.refund_amount ?? 0))*100)
    if (amountCents <= 0) return NextResponse.json({ error: 'Nothing left to refund.' }, { status: 400 })
    const op = await prepareRefund({ key, orderId: id, kind: 'refund', amountCents, expectedRefund: Number(order.refund_amount ?? 0),
      payload: { fingerprint, reason, paymentIntentId: null, response: {} } })
    return NextResponse.json(await executeRefund(op))
  } catch (error) {
    return NextResponse.json({ error: error instanceof Error ? error.message : 'Could not record refund.' }, { status: 409 })
  }
}
