import { limitPublicRequest } from '@/lib/security/request-rate-limit'
import { NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabase-admin'
import { isPasswordAcceptableForSignup } from '@/lib/auth/password-strength'

export const runtime = 'nodejs'

type Body = {
  email?: string
  password?: string
  firstName?: string
  lastName?: string
  phone?: string
  marketingOptIn?: boolean
  termsAccepted?: boolean
}

function isValidOptionalPhone(phone: string): boolean {
  if (!phone) return true
  const digits = phone.replace(/\D/g, '')
  return digits.length >= 10 && digits.length <= 15
}

/** New accounts only. Existing accounts must use verified password recovery. */
export async function POST(request: Request) {
  const limited = await limitPublicRequest(request, 'signup', 10)
  if (limited) return limited

  let body: Body
  try {
    body = (await request.json()) as Body
  } catch {
    return NextResponse.json({ error: 'Invalid request.' }, { status: 400 })
  }

  const email = body.email?.trim().toLowerCase() ?? ''
  const password = body.password ?? ''
  const firstName = body.firstName?.trim() ?? ''
  const lastName = body.lastName?.trim() ?? ''
  const phone = body.phone?.trim() ?? ''
  const marketingOptIn = Boolean(body.marketingOptIn)
  const termsAccepted = Boolean(body.termsAccepted)

  if (!email || !email.includes('@')) {
    return NextResponse.json({ error: 'Enter a valid email.' }, { status: 400 })
  }
  if (!firstName || !lastName) {
    return NextResponse.json({ error: 'Enter your first and last name.' }, { status: 400 })
  }
  if (!termsAccepted) {
    return NextResponse.json({ error: 'Please accept the Terms and Privacy Policy.' }, { status: 400 })
  }
  if (!isValidOptionalPhone(phone)) {
    return NextResponse.json(
      { error: 'Enter a valid phone number, or leave it blank.' },
      { status: 400 }
    )
  }
  if (!isPasswordAcceptableForSignup(password)) {
    return NextResponse.json(
      { error: 'Use a stronger password (8+ chars, upper, lower, number, special).' },
      { status: 400 }
    )
  }

  const fullName = `${firstName} ${lastName}`.trim()
  const userMeta = {
    first_name: firstName,
    last_name: lastName,
    full_name: fullName,
    phone: phone || null,
    marketing_opt_in: marketingOptIn,
    terms_accepted_at: new Date().toISOString(),
  }

  try {
    const { data, error } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: userMeta,
    })

    if (!error && data.user) {
      return NextResponse.json({ ok: true })
    }

    const msg = (error?.message ?? '').toLowerCase()
    const already =
      msg.includes('already') || msg.includes('registered') || msg.includes('exists')

    if (!already) {
      console.error('[auth/signup] createUser', error?.message)
      return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 })
    }

    return NextResponse.json(
      { error: 'An account with this email already exists. Sign in or reset your password.' },
      { status: 409 }
    )
  } catch (e) {
    console.error('[auth/signup]', e)
    return NextResponse.json({ error: 'Sign-up is temporarily unavailable.' }, { status: 503 })
  }
}
