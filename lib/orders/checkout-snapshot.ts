import type { CheckoutTotals } from '@/lib/checkout-totals'

/** Stored in checkout_snapshots.payload — rebuilt server-side with DB prices on fulfill */
export type CheckoutSnapshotPayload = {
  items: { productId: string; quantity: number }[]
  /** Immutable server quote. Old snapshots use a compatibility path with reconciliation. */
  quote?: CheckoutTotals
  customer_name: string
  customer_phone: string
  address_line: string
  city: string
  state: string | null
  country: string
  postal_code: string | null
  shipping_method: string
  shipping_zone: string | null
  account_email: string
  /** For pickup orders: who is collecting (customer, friend, or courier). */
  pickup_contact_name?: string | null
  /** refund | call | substitute */
  substitution_pref?: string | null
  /** today_asap | today_afternoon | … */
  pickup_slot?: string | null
  /** Driver tip dollars */
  tip_amount?: number | null
}
