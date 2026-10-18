import { supabaseAdmin } from '@/lib/supabase-admin'
import type { AuthoritativeOrderItem } from '@/lib/order-pricing'

/** The RPC is the sole writer of order headers, lines, and allocated inventory. */
export async function recordOrder(order: Record<string, unknown>, items: AuthoritativeOrderItem[]) {
  const { data, error } = await supabaseAdmin.rpc('record_commerce_order', {
    p_order: order,
    p_items: items,
  })
  if (error || !data?.order?.id) throw new Error(error?.message ?? 'Order transaction failed')
  return data as { order: Record<string, unknown> & {
    id: string; order_number: number | null; customer_name: string; customer_email: string;
    customer_phone: string; address_line: string; city: string; state: string | null;
    country: string; postal_code: string | null; subtotal_amount: number; shipping_fee: number;
    total_amount: number; shipping_method: string; payment_method: string;
  }; created: boolean }
}
