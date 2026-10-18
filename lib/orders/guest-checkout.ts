/** Sentinel user_id for guest checkout snapshots (checkout_snapshots.user_id is NOT NULL). */
export const GUEST_CHECKOUT_USER_ID = '00000000-0000-0000-0000-000000000001'

export const GUEST_CHECKOUT_MODE = 'guest' as const
export const ACCOUNT_CHECKOUT_MODE = 'account' as const

export type CheckoutMode = typeof GUEST_CHECKOUT_MODE | typeof ACCOUNT_CHECKOUT_MODE

export function isGuestCheckoutUserId(userId: string | null | undefined): boolean {
  return (userId ?? '').trim() === GUEST_CHECKOUT_USER_ID
}

export function isGuestCheckoutMode(mode: string | null | undefined): boolean {
  return (mode ?? '').trim() === GUEST_CHECKOUT_MODE
}

export function resolveCheckoutMode(metadata: {
  checkout_mode?: string | null
  user_id?: string | null
}): CheckoutMode {
  if (isGuestCheckoutMode(metadata.checkout_mode)) return GUEST_CHECKOUT_MODE
  if (isGuestCheckoutUserId(metadata.user_id)) return GUEST_CHECKOUT_MODE
  return ACCOUNT_CHECKOUT_MODE
}

export function normalizeGuestEmail(raw: unknown): string | null {
  if (typeof raw !== 'string') return null
  const email = raw.trim().toLowerCase()
  if (email.length > 254 || /[%]/.test(email) || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return null
  return email.slice(0, 254)
}
