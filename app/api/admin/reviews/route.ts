import { NextRequest, NextResponse } from 'next/server'
import { requireAdminApi } from '@/lib/auth/require-admin-api'
import { supabaseAdmin } from '@/lib/supabase-admin'

export const runtime = 'nodejs'

/**
 * Review moderation queue for the native store manager.
 * `status` = pending (default) | approved. Approve/delete use the `[id]` routes.
 */
export async function GET(req: NextRequest) {
  const auth = await requireAdminApi()
  if (!auth.ok) return auth.response

  const approved = req.nextUrl.searchParams.get('status') === 'approved'
  const { data, error } = await supabaseAdmin
    .from('product_reviews')
    .select('id, product_id, reviewer_name, rating, comment, created_at, approved, products(name)')
    .eq('approved', approved)
    .order('created_at', { ascending: false })
    .limit(100)

  if (error) {
    console.error('[admin/reviews GET] failed:', error.message)
    return NextResponse.json({ error: 'Could not load reviews.' }, { status: 500 })
  }

  return NextResponse.json({
    reviews: (data ?? []).map((r) => {
      const product = Array.isArray(r.products) ? r.products[0] : r.products
      return {
        id: r.id,
        product_id: r.product_id,
        product_name: (product as { name?: string } | null)?.name ?? null,
        reviewer_name: r.reviewer_name ?? null,
        rating: r.rating,
        comment: r.comment ?? null,
        created_at: r.created_at,
        approved: r.approved,
      }
    }),
  })
}
