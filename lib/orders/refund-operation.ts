import { sendShortfallEmail } from '@/lib/email/send-order-emails'
import { supabaseAdmin } from '@/lib/supabase-admin'
import { getStripe } from '@/lib/stripe'

export type RefundOperation = {
  id: string; request_key: string; order_id: string; kind: 'refund' | 'shortfall';
  amount_cents: number; state: 'pending' | 'succeeded' | 'failed'; created_at: string;
  provider_refund_id: string | null;
  payload: { fingerprint: string; paymentIntentId: string | null; response: Record<string, unknown>;
    notification?: Parameters<typeof sendShortfallEmail>[0];
    lines?: { itemId: string; previousQuantity: number; fulfilledQuantity: number }[]; reason: string }
}

export function refundRequestKey(req: Request): string {
  const key = req.headers.get('idempotency-key') ?? ''
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(key)) {
    throw new Error('A UUID Idempotency-Key is required. Refresh and retry.')
  }
  return key
}

export async function findRefundOperation(key: string, orderId: string, kind: string, fingerprint: string) {
  const { data, error } = await supabaseAdmin.from('commerce_operations').select('*').eq('request_key', key).maybeSingle()
  if (error) throw new Error(error.message)
  let saved = data
  if (!saved) {
    // A refreshed browser may have lost its UUID; resume the matching pending
    // operation instead of forcing staff to recover a client-side identifier.
    const pending = await supabaseAdmin.from('commerce_operations').select('*').eq('order_id', orderId).eq('state', 'pending').maybeSingle()
    if (pending.error) throw new Error(pending.error.message)
    saved = pending.data
  }
  if (!saved) return null
  const op = saved as RefundOperation
  if (op.order_id !== orderId || op.kind !== kind || op.payload.fingerprint !== fingerprint) {
    throw new Error('This refund request changed. Retry the original request or refresh.')
  }
  return op
}

export async function prepareRefund(input: {
  key: string; orderId: string; kind: 'refund' | 'shortfall'; amountCents: number;
  expectedRefund: number; payload: RefundOperation['payload']
}) {
  const { data, error } = await supabaseAdmin.rpc('prepare_commerce_refund', {
    p_key: input.key, p_order_id: input.orderId, p_kind: input.kind,
    p_amount: input.amountCents, p_payload: input.payload, p_expected_refund: input.expectedRefund,
  })
  if (error) throw new Error(error.message)
  return data as RefundOperation
}

export async function finishRefund(id: string, refundId: string | null, state: 'succeeded' | 'failed') {
  const { data, error } = await supabaseAdmin.rpc('finish_commerce_refund', {
    p_id: id, p_provider_id: refundId, p_state: state,
  })
  if (error) throw new Error(error.message)
  return data as RefundOperation
}

/** Pending operations survive network failures. Provider metadata allows recovery
 * even after Stripe's idempotency retention window, without blindly refunding again. */
export async function executeRefund(op: RefundOperation) {
  if (op.state === 'failed') throw new Error('This refund failed. Refresh before starting another refund.')
  if (op.state === 'succeeded') return { ...op.payload.response, ok: true, refundId: op.provider_refund_id }
  if (!op.payload.paymentIntentId || op.amount_cents === 0) {
    await finishRefund(op.id, null, 'succeeded')
    await notifyShortfall(op)
    return { ...op.payload.response, ok: true, refundId: null }
  }
  const stripe = getStripe()
  let refund = null
  // Iterate every page: never assume the matching refund is among the first 100.
  for await (const candidate of stripe.refunds.list({ payment_intent: op.payload.paymentIntentId, limit: 100 })) {
    if (candidate.metadata?.commerce_operation_id === op.id) { refund = candidate; break }
  }
  if (!refund) {
    if (Date.now() - Date.parse(op.created_at) > 23 * 60 * 60 * 1000) {
      throw new Error('Refund needs provider reconciliation before retrying. No additional money was moved.')
    }
    refund = await stripe.refunds.create({
      payment_intent: op.payload.paymentIntentId, amount: op.amount_cents,
      reason: 'requested_by_customer', metadata: { commerce_operation_id: op.id },
    }, { idempotencyKey: `commerce-refund-${op.id}` })
  }
  if (refund.amount !== op.amount_cents || refund.payment_intent !== op.payload.paymentIntentId) {
    throw new Error('Provider refund does not match the saved operation.')
  }
  if (refund.status === 'failed' || refund.status === 'canceled') {
    await finishRefund(op.id, refund.id, 'failed')
    throw new Error('Stripe could not complete this refund. Refresh and try a new request.')
  }
  if (refund.status !== 'succeeded') throw new Error('Refund is pending with Stripe. Retry this request to check its status.')
  await finishRefund(op.id, refund.id, 'succeeded')
  await notifyShortfall(op)
  return { ...op.payload.response, ok: true, refundId: refund.id }
}

/** Signed webhook reconciliation for asynchronous provider refunds. */
export async function reconcileRefund(refund: { id: string; amount: number; payment_intent: string | { id: string } | null; status?: string | null; metadata: Record<string, string> | null }) {
  const operationId = refund.metadata?.commerce_operation_id
  if (!operationId) return
  const { data, error } = await supabaseAdmin.from('commerce_operations').select('*').eq('id', operationId).maybeSingle()
  if (error) throw new Error(error.message)
  if (!data) throw new Error('Unknown refund operation')
  const op = data as RefundOperation
  const paymentId = typeof refund.payment_intent === 'string' ? refund.payment_intent : refund.payment_intent?.id
  if (refund.amount !== op.amount_cents || paymentId !== op.payload.paymentIntentId) throw new Error('Refund operation mismatch')
  if (refund.status === 'succeeded') {
    await finishRefund(op.id, refund.id, 'succeeded')
    if (op.state === 'pending') await notifyShortfall(op)
  }
  else if (refund.status === 'failed' || refund.status === 'canceled') await finishRefund(op.id, refund.id, 'failed')
}

async function notifyShortfall(op: RefundOperation) {
  if (!op.payload.notification) return
  try { await sendShortfallEmail(op.payload.notification) } catch (error) {
    console.error('[refund] post-commit notification failed', error)
  }
}
