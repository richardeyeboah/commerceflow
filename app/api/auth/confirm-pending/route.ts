import { NextResponse } from 'next/server'

/** Email possession must be verified through Supabase recovery, never an admin bypass. */
export async function POST() {
  return NextResponse.json(
    { error: 'Use the password reset link sent to your email to recover this account.' },
    { status: 410 }
  )
}
