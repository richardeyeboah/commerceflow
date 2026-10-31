import { NextResponse } from 'next/server'
import { fetchBestsellers } from '@/lib/supabase/bestsellers'

// Public catalog data only (no order details); recomputed at most every 10 minutes.
export const revalidate = 600

/** Top-selling in-stock products for the native app's Home screen. */
export async function GET() {
  const products = await fetchBestsellers(8)
  return NextResponse.json({ products })
}
