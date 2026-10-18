import { NextRequest, NextResponse } from 'next/server'
import { isSupabaseAdminRoleBypassEnabled } from '@/lib/auth/admin-access-mode'
import {
  ADMIN_COOKIE_NAME,
  ADMIN_SESSION_TTL_SECONDS,
  constantTimeEquals,
  createAdminSessionToken,
} from '@/lib/auth/admin-session'
import {
  clearLoginFailures,
  isAdminLoginRateLimitDisabled,
  isLoginAllowed,
  recordFailedLogin,
} from '@/lib/security/login-rate-limit'
import { assertSameOrigin } from '@/lib/security/same-origin'

export const runtime = 'nodejs'

function getClientIp(req: NextRequest): string {
  return req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown'
}

function warnProductionMisconfig() {
  if (process.env.NODE_ENV !== 'production') return

  if (!process.env.ADMIN_SESSION_SECRET?.trim()) {
    console.warn(
      '[admin-login] ADMIN_SESSION_SECRET is not set — session cookies are signed with ADMIN_PASSWORD. Set a dedicated secret in production.'
    )
  }

  if (isSupabaseAdminRoleBypassEnabled()) {
    console.warn(
      '[admin-login] ADMIN_ALLOW_SUPABASE_ROLE=1 is enabled in production — password cookie is not required for Supabase admin profiles.'
    )
  }
}

export async function POST(req: NextRequest) {
  const originCheck = assertSameOrigin(req)
  if (!originCheck.ok) return originCheck.response

  warnProductionMisconfig()

  const ip = getClientIp(req)

  if (process.env.NODE_ENV === 'production' && !isAdminLoginRateLimitDisabled()) {
    const { allowed, retryAfterSecs } = await isLoginAllowed(ip)
    if (!allowed) {
      return NextResponse.json(
        { error: `Too many login attempts. Try again in ${Math.ceil(retryAfterSecs / 60)} minute(s).` },
        { status: 429, headers: { 'Retry-After': String(retryAfterSecs) } }
      )
    }
  }

  const expected = process.env.ADMIN_PASSWORD?.trim()
  if (!expected) {
    console.error('[admin-login] ADMIN_PASSWORD is not configured.')
    return NextResponse.json({ error: 'Admin login is not configured.' }, { status: 503 })
  }

  let suppliedRaw: unknown
  try {
    const body = await req.json()
    suppliedRaw = body?.password
  } catch {
    return NextResponse.json({ error: 'Invalid request body.' }, { status: 400 })
  }

  const supplied =
    typeof suppliedRaw === 'string' ? suppliedRaw.trim().normalize('NFKC') : ''
  const expectedNorm = expected.normalize('NFKC')

  if (supplied.length === 0 || !constantTimeEquals(supplied, expectedNorm)) {
    if (process.env.NODE_ENV === 'production' && !isAdminLoginRateLimitDisabled()) {
      await recordFailedLogin(ip)
    }
    return NextResponse.json({ error: 'Invalid password.' }, { status: 401 })
  }

  await clearLoginFailures(ip)

  const { token } = await createAdminSessionToken()

  const res = NextResponse.json({ success: true })
  res.cookies.set(ADMIN_COOKIE_NAME, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    maxAge: ADMIN_SESSION_TTL_SECONDS,
    path: '/',
  })
  return res
}
