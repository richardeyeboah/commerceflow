import { NextRequest, NextResponse } from 'next/server'
import { requireAdminApi } from '@/lib/auth/require-admin-api'
import { assertSameOrigin } from '@/lib/security/same-origin'
import { supabaseAdmin } from '@/lib/supabase-admin'

export const runtime = 'nodejs'

/**
 * Upload a label/address-slip PDF to the private shipping-labels bucket
 * so FlashLabel Pro can open a real https://…pdf link from Share.
 */
export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const originCheck = assertSameOrigin(req)
  if (!originCheck.ok) return originCheck.response

  const auth = await requireAdminApi()
  if (!auth.ok) return auth.response

  const { id: orderId } = await params
  const body = await req.json().catch(() => ({}))
  const pdfBase64 = typeof body.pdfBase64 === 'string' ? body.pdfBase64 : ''
  const kind =
    body.kind === 'address-slip' || body.kind === 'pickup-ticket' ? body.kind : 'label'
  const rawName = typeof body.filename === 'string' ? body.filename : `${kind}.pdf`
  const safeName = rawName.replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 80)
  const filename = safeName.toLowerCase().endsWith('.pdf') ? safeName : `${safeName}.pdf`

  if (!pdfBase64 || pdfBase64.length < 64) {
    return NextResponse.json({ error: 'Missing PDF data.' }, { status: 400 })
  }

  let pdf: Buffer
  try {
    pdf = Buffer.from(pdfBase64, 'base64')
  } catch {
    return NextResponse.json({ error: 'Invalid PDF data.' }, { status: 400 })
  }

  if (pdf.length < 100 || pdf.subarray(0, 4).toString('utf8') !== '%PDF') {
    return NextResponse.json({ error: 'File is not a valid PDF.' }, { status: 400 })
  }

  // Cap ~8MB
  if (pdf.length > 8 * 1024 * 1024) {
    return NextResponse.json({ error: 'PDF too large.' }, { status: 400 })
  }

  const { data: order, error: orderErr } = await supabaseAdmin
    .from('orders')
    .select('id')
    .eq('id', orderId)
    .single()

  if (orderErr || !order) {
    return NextResponse.json({ error: 'Order not found.' }, { status: 404 })
  }

  const path = `orders/${orderId}/${kind}-${Date.now()}-${filename}`
  const { error: uploadErr } = await supabaseAdmin.storage.from('shipping-labels').upload(path, pdf, {
    contentType: 'application/pdf',
    upsert: true,
  })

  if (uploadErr) {
    console.error('[upload-pdf]', uploadErr.message)
    return NextResponse.json(
      { error: `Could not store PDF: ${uploadErr.message}` },
      { status: 500 }
    )
  }

  const { data, error: signError } = await supabaseAdmin.storage.from('shipping-labels').createSignedUrl(path, 300)
  if (signError || !data?.signedUrl) return NextResponse.json({ error: 'Could not create PDF link.' }, { status: 500 })
  // Keep the existing response field for printer clients; the URL expires in five minutes.
  return NextResponse.json({ ok: true, publicUrl: data.signedUrl, expiresIn: 300, path })
}
