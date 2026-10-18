import { limitPublicRequest } from '@/lib/security/request-rate-limit'
import { checkLocalDeliveryEligibility } from '@/lib/delivery/local-delivery-eligibility'
import { LOCAL_DELIVERY_MIN_SUBTOTAL } from '@/lib/shipping'
import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { supabaseAdmin } from '@/lib/supabase-admin'
import { sanitizeCartItems } from '@/lib/order-pricing'
import {
  computeCheckoutTotals,
  fetchCheckoutProductMap,
  type ProductWithCategory,
} from '@/lib/checkout-totals'
import {
  formatAddressLine,
  isUnitedStatesCountry,
  resolveShippingAddress,
  verifyUsDeliveryAddress,
} from '@/lib/address/verify-us-address'
import {
  normalizeShippingCountry,
  normalizeShippingRegion,
  SHIPPING_METHOD_LABEL,
  type ShippingMethod,
} from '@/lib/shipping'
import type { CartItem } from '@/types'
import { CHECKOUT_STRIPE_PAYMENT_METHOD_TYPES, getStripe } from '@/lib/stripe'
import { getPublicSiteUrl } from '@/lib/site-url'
import { assertSameOrigin } from '@/lib/security/same-origin'
import { maxCartQuantity } from '@/lib/product-pricing'

export const runtime = 'nodejs'

export async function POST(req: NextRequest) {
  const limited = await limitPublicRequest(req, 'checkout', 30)
  if (limited) return limited

  const originCheck = assertSameOrigin(req)
  if (!originCheck.ok) return originCheck.response

  try {
    const supabaseUser = await createClient()
    const {
      data: { user },
    } = await supabaseUser.auth.getUser()

    if (!user) {
      return NextResponse.json({ error: 'Please sign in before checking out.' }, { status: 401 })
    }

    const accountEmail = user.email?.trim().toLowerCase()
    if (!accountEmail) {
      return NextResponse.json({ error: 'Your account is missing an email address.' }, { status: 400 })
    }

    const body = await req.json()
    const {
      name,
      phone,
      address,
      address1,
      address2,
      city,
      state,
      country,
      postalCode,
      items,
      shippingMethod: rawShippingMethod,
    } = body

    const addressLine1 =
      typeof address1 === 'string'
        ? address1.trim()
        : typeof address === 'string'
          ? address.trim()
          : ''
    const addressLine2 = typeof address2 === 'string' ? address2.trim() : ''

    if (!name || !addressLine1 || !city || !country || !items?.length) {
      return NextResponse.json({ error: 'Missing required fields.' }, { status: 400 })
    }

    const cartItems = (Array.isArray(items) ? items : []) as CartItem[]
    const phoneTrim = typeof phone === 'string' ? phone.trim() : ''
    if (!phoneTrim) {
      return NextResponse.json(
        { error: 'Phone number is required so we can confirm your order.' },
        { status: 400 }
      )
    }

    let sanitizedItems: ReturnType<typeof sanitizeCartItems>
    try { sanitizedItems = sanitizeCartItems(cartItems) } catch (error) {
      return NextResponse.json({ error: error instanceof Error ? error.message : 'Invalid cart.' }, { status: 400 })
    }
    if (sanitizedItems.length === 0) {
      return NextResponse.json({ error: 'Your cart is empty or invalid.' }, { status: 400 })
    }

    const candidateProductIds = Array.from(new Set(sanitizedItems.map((item) => item.productId)))
    const { productMap, error: productError } = await fetchCheckoutProductMap(
      supabaseAdmin,
      candidateProductIds
    )

    if (productError) {
      console.error('Product lookup error:', productError)
      return NextResponse.json({ error: 'Could not verify cart items.' }, { status: 500 })
    }

    if (productMap.size !== candidateProductIds.length) {
      return NextResponse.json(
        { error: 'One or more items are no longer available. Please review your cart.' },
        { status: 400 }
      )
    }

    const unavailable = sanitizedItems
      .map((item) => productMap.get(item.productId))
      .filter((product): product is ProductWithCategory => !!product && !product.in_stock)

    if (unavailable.length > 0) {
      return NextResponse.json(
        {
          error: `These items are currently unavailable: ${unavailable.map((p) => p.name).join(', ')}.`,
        },
        { status: 400 }
      )
    }

    const overStock = sanitizedItems
      .map((item) => {
        const product = productMap.get(item.productId)
        if (!product) return null
        const max = maxCartQuantity(product)
        if (item.quantity <= max) return null
        return { name: product.name, max }
      })
      .filter((row): row is { name: string; max: number } => row != null)

    if (overStock.length > 0) {
      return NextResponse.json(
        {
          error: `Reduce quantity for: ${overStock
            .map((r) => `${r.name} (max ${r.max})`)
            .join(', ')}.`,
        },
        { status: 400 }
      )
    }

    const normalizedCountry = normalizeShippingCountry(country)
    const normalizedState = normalizeShippingRegion(state)
    const totals = computeCheckoutTotals({
      items: sanitizedItems,
      productMap,
      country: normalizedCountry,
      state: normalizedState,
      shippingMethod: rawShippingMethod,
    })
    const { orderItems: authoritativeItems, shipping, tax } = totals
    const shipping_method = shipping.method

    let shippingAddress = {
      line1: addressLine1,
      line2: addressLine2,
      city: String(city).trim(),
      state: normalizedState || String(state).trim(),
      postalCode: typeof postalCode === 'string' ? postalCode.trim() : '',
    }

    if (shipping_method !== 'pickup' && isUnitedStatesCountry(String(country))) {
      const zip = shippingAddress.postalCode
      if (!zip) {
        return NextResponse.json({ error: 'ZIP code is required.' }, { status: 400 })
      }
      const verified = await verifyUsDeliveryAddress({
        line1: shippingAddress.line1,
        line2: shippingAddress.line2,
        city: shippingAddress.city,
        state: shippingAddress.state,
        postalCode: zip,
        country: String(country).trim(),
      })
      if (!verified.ok) {
        return NextResponse.json(
          {
            error: verified.error,
            suggested: verified.suggested ?? null,
            corrections: verified.corrections ?? [],
          },
          { status: 400 }
        )
      }
      shippingAddress = resolveShippingAddress(
        {
          line1: shippingAddress.line1,
          line2: shippingAddress.line2,
          city: shippingAddress.city,
          state: shippingAddress.state,
          postalCode: zip,
          country: String(country).trim(),
        },
        verified
      )
    }

    if (shipping_method === 'local_delivery') {
      if (totals.subtotal < LOCAL_DELIVERY_MIN_SUBTOTAL) return NextResponse.json({ error: 'Local delivery minimum not met.' }, { status: 400 })
      const eligibility = await checkLocalDeliveryEligibility({ ...shippingAddress, country: normalizedCountry })
      if (!eligibility.ok || !eligibility.eligible) return NextResponse.json({ error: 'Address is outside the local delivery area.' }, { status: 400 })
    }
    const addressLine = formatAddressLine(shippingAddress)

    const stripeKey = process.env.STRIPE_SECRET_KEY?.trim()
    if (!stripeKey) {
      return NextResponse.json({ error: 'Online payments are temporarily unavailable.' }, { status: 503 })
    }

    const stripe = getStripe()
    const baseUrl = getPublicSiteUrl()

    const productLines = authoritativeItems.map((item) => ({
      quantity: item.quantity,
      price_data: {
        currency: 'usd',
        unit_amount: Math.round(item.product_price * 100),
        product_data: {
          name: item.product_name,
          metadata: {
            product_id: item.product_id,
          },
        },
      },
    }))

    const shippingLine = {
      quantity: 1,
      price_data: {
        currency: 'usd',
        unit_amount: Math.round(shipping.fee * 100),
        product_data: {
          name: `Shipping (${SHIPPING_METHOD_LABEL[shipping_method as ShippingMethod] ?? shipping_method})`,
          metadata: {
            type: 'shipping',
          },
        },
      },
    }

    const taxLine =
      tax.taxAmount > 0
        ? {
            quantity: 1,
            price_data: {
              currency: 'usd',
              unit_amount: Math.round(tax.taxAmount * 100),
              product_data: {
                name: 'Sales tax (Ohio)',
                metadata: { type: 'tax' },
              },
            },
          }
        : null

    const lineItemsPayload = [
      ...productLines,
      ...(shipping.fee > 0 ? [shippingLine] : []),
      ...(taxLine ? [taxLine] : []),
    ]

    const session = await stripe.checkout.sessions.create({
      mode: 'payment',
      payment_method_types: [...CHECKOUT_STRIPE_PAYMENT_METHOD_TYPES],
      customer_email: accountEmail,
      client_reference_id: user.id,
      line_items: lineItemsPayload,
      success_url: `${baseUrl}/checkout/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${baseUrl}/checkout/cancel`,
      metadata: {
        user_id: user.id,
        customer_name: String(name).trim(),
        customer_phone: phoneTrim,
        address_line: addressLine,
        city: shippingAddress.city,
        state: shippingAddress.state || '',
        country: normalizedCountry || '',
        postal_code: shippingAddress.postalCode || '',
        shipping_method,
        shipping_zone: shipping.zone,
      },
      payment_intent_data: {
        metadata: {
          user_id: user.id,
        },
      },
    })

    if (!session.url) {
      return NextResponse.json({ error: 'Could not start Stripe Checkout.' }, { status: 500 })
    }

    return NextResponse.json({ url: session.url })
  } catch (err) {
    console.error('checkout session error:', err)
    return NextResponse.json({ error: 'Could not start checkout.' }, { status: 500 })
  }
}
