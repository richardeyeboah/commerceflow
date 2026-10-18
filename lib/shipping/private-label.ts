import { supabaseAdmin } from '@/lib/supabase-admin'

/** Accept only our bucket references, including legacy public Supabase URLs. */
export function shippingLabelPath(reference: string): string {
  if (reference.startsWith('storage://shipping-labels/')) return reference.slice('storage://shipping-labels/'.length)
  const url = new URL(reference)
  if (url.origin !== new URL(process.env.NEXT_PUBLIC_SUPABASE_URL!).origin) throw new Error('Untrusted label URL')
  const prefix = '/storage/v1/object/public/shipping-labels/'
  if (!url.pathname.startsWith(prefix)) throw new Error('Untrusted label path')
  return decodeURIComponent(url.pathname.slice(prefix.length))
}

export async function signedShippingLabel(reference: string | null | undefined): Promise<string | null> {
  if (!reference) return null
  const path = shippingLabelPath(reference)
  const { data, error } = await supabaseAdmin.storage.from('shipping-labels').createSignedUrl(path, 300)
  if (error) throw new Error('Could not prepare the shipping label.')
  return data.signedUrl
}
