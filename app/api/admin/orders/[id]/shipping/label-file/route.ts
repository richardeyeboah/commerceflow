import { shippingLabelPath } from '@/lib/shipping/private-label'
import { NextRequest, NextResponse } from 'next/server'
import { requireAdminApi } from '@/lib/auth/require-admin-api'
import { assertSameOrigin } from '@/lib/security/same-origin'
import { supabaseAdmin } from '@/lib/supabase-admin'

export const runtime = 'nodejs'

/**
 * Streams the order's shipping label PDF from storage / saved URL
 * so Android Chrome can download a real .pdf into Files/Downloads.
 */
export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const originCheck = assertSameOrigin(req)
  if (!originCheck.ok) return originCheck.response

  const auth = await requireAdminApi()
  if (!auth.ok) return auth.response

  const { id: orderId } = await params
  const { data: order, error } = await supabaseAdmin
    .from('orders')
    .select('id, tracking_number, shipping_label_url')
    .eq('id', orderId)
    .single()

  if (error || !order) {
    return NextResponse.json({ error: 'Order not found.' }, { status: 404 })
  }

  const labelUrl =
    typeof order.shipping_label_url === 'string' ? order.shipping_label_url.trim() : ''
  if (!labelUrl) {
    return NextResponse.json({ error: 'No label PDF on this order yet.' }, { status: 404 })
  }

  let path: string
  try { path = shippingLabelPath(labelUrl) } catch {
    return NextResponse.json({ error: 'Label requires migration to private storage.' }, { status: 409 })
  }
  const { data: pdf, error: downloadError } = await supabaseAdmin.storage.from('shipping-labels').download(path)
  if (downloadError || !pdf) return NextResponse.json({ error: 'Could not fetch label PDF.' }, { status: 502 })
  const bytes = Buffer.from(await pdf.arrayBuffer())
  const tracking =
    typeof order.tracking_number === 'string' && order.tracking_number
      ? order.tracking_number
      : orderId.slice(0, 8)
  const filename = `shipping-label-${tracking}.pdf`

  return new NextResponse(bytes, {
    status: 200,
    headers: {
      'Content-Type': 'application/pdf',
      'Content-Disposition': `attachment; filename="${filename}"`,
      'Cache-Control': 'no-store',
      'Content-Length': String(bytes.length),
    },
  })
}
