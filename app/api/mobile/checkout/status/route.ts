import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { supabaseAdmin } from '@/lib/supabase-admin'
import { fulfillOrderFromPaymentIntent } from '@/lib/orders/fulfill-payment-intent'
import { getStripe } from '@/lib/stripe'
import { resolveCheckoutMode, GUEST_CHECKOUT_MODE } from '@/lib/orders/guest-checkout'
import { getSupabasePublicConfig } from '@/lib/supabase/config'

export const runtime = 'nodejs'

/** Poll payment + order for native apps (Bearer optional for account checkouts). */
export async function GET(req: NextRequest) {
  const paymentIntentId = req.nextUrl.searchParams.get('payment_intent')?.trim()
  if (!paymentIntentId) {
    return NextResponse.json({ error: 'Missing payment_intent' }, { status: 400 })
  }

  try {
    const stripe = getStripe()
    const pi = await stripe.paymentIntents.retrieve(paymentIntentId)
    const checkoutMode = resolveCheckoutMode(pi.metadata ?? {})
    const isGuest = checkoutMode === GUEST_CHECKOUT_MODE

    if (!isGuest) {
      const { url, anonKey, configured } = getSupabasePublicConfig()
      const authHeader = req.headers.get('authorization') ?? ''
      const bearer = authHeader.toLowerCase().startsWith('bearer ')
        ? authHeader.slice(7).trim()
        : ''
      if (!configured || !bearer || !url || !anonKey) {
        return NextResponse.json({ error: 'Please sign in.' }, { status: 401 })
      }
      const userClient = createClient(url, anonKey, {
        global: { headers: { Authorization: `Bearer ${bearer}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      })
      const { data } = await userClient.auth.getUser(bearer)
      if (!data.user || pi.metadata?.user_id !== data.user.id) {
        return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
      }
    }

    if (pi.status !== 'succeeded') {
      return NextResponse.json({ status: 'unpaid', paymentStatus: pi.status })
    }

    let orderQuery = supabaseAdmin
      .from('orders')
      .select('id, order_number, status, total_amount')
      .eq('stripe_payment_intent_id', paymentIntentId)

    if (!isGuest && pi.metadata?.user_id) {
      orderQuery = orderQuery.eq('user_id', pi.metadata.user_id)
    }

    let { data: order } = await orderQuery.maybeSingle()

    if (!order?.id) {
      try {
        const result = await fulfillOrderFromPaymentIntent(paymentIntentId)
        if (result.orderId) {
          const { data: created } = await supabaseAdmin
            .from('orders')
            .select('id, order_number, status, total_amount')
            .eq('id', result.orderId)
            .maybeSingle()
          order = created
        }
      } catch (e) {
        console.error('[mobile/checkout/status] fulfill', e)
      }
    }

    if (!order?.id) {
      return NextResponse.json({ status: 'processing', paymentStatus: pi.status })
    }

    // A payment/order header alone is not a complete order: item insertion may
    // have failed in fulfillment. Keep the client pending until items exist.
    const { count, error: itemsError } = await supabaseAdmin
      .from('order_items')
      .select('id', { count: 'exact', head: true })
      .eq('order_id', order.id)
    if (itemsError || !count) {
      return NextResponse.json({ status: 'processing', paymentStatus: pi.status })
    }

    return NextResponse.json({
      status: 'complete',
      orderId: order.id,
      orderNumber: order.order_number,
      orderStatus: order.status,
      totalAmount: order.total_amount,
    })
  } catch (err) {
    // Unknown or malformed payment id: Stripe answers with resource_missing / 404.
    const stripeErr = err as { code?: string; statusCode?: number }
    if (stripeErr?.code === 'resource_missing' || stripeErr?.statusCode === 404) {
      return NextResponse.json({ error: 'Payment not found.' }, { status: 404 })
    }
    console.error('[mobile/checkout/status]', err)
    return NextResponse.json({ error: 'Could not check payment status.' }, { status: 500 })
  }
}
