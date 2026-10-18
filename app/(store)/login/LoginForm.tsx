'use client'

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useEffect, useRef, useState } from 'react'
import { createClient, isSupabaseBrowserConfigured } from '@/lib/supabase/client'
import { useClientSearchParams } from '@/lib/hooks/use-client-search-params'
import { mapSignInError } from '@/lib/auth/map-auth-error'
import { AuthShell } from '@/components/auth/AuthShell'
import { PasswordField } from '@/components/auth/PasswordField'
import { GoogleAuthButton } from '@/components/auth/GoogleAuthButton'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

const REMEMBER_EMAIL_KEY = 'lq_remember_email'

export function LoginForm() {
  const router = useRouter()
  const { next, error: err } = useClientSearchParams()
  const emailRef = useRef<HTMLInputElement>(null)

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [rememberDevice, setRememberDevice] = useState(true)

  useEffect(() => {
    try {
      const saved = localStorage.getItem(REMEMBER_EMAIL_KEY)
      if (saved) setEmail(saved)
    } catch {
      /* ignore */
    }
    emailRef.current?.focus()
  }, [])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!isSupabaseBrowserConfigured()) {
      setError('Sign-in is temporarily unavailable.')
      return
    }
    setLoading(true)
    setError('')
    const supabase = createClient()
    const trimmed = email.trim().toLowerCase()

    const { error: signError } = await supabase.auth.signInWithPassword({
      email: trimmed,
      password,
    })

    setLoading(false)
    if (signError) {
      setError(mapSignInError(signError.message))
      return
    }
    try {
      if (rememberDevice) localStorage.setItem(REMEMBER_EMAIL_KEY, trimmed)
      else localStorage.removeItem(REMEMBER_EMAIL_KEY)
    } catch {
      /* ignore */
    }
    router.push(next)
    router.refresh()
  }

  return (
    <AuthShell title="Sign in" subtitle="Welcome back to Kintampo African Market">
      {err === 'auth' && (
        <p className="error mb-4">
          That link expired or was already used. Sign in below or reset your password.
        </p>
      )}
      {err === 'configuration' && (
        <p className="error mb-4">Sign-in is temporarily unavailable.</p>
      )}

      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label htmlFor="login-email" className="form-label">
            Email
          </label>
          <Input
            ref={emailRef}
            id="login-email"
            type="email"
            inputMode="email"
            autoComplete="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
        </div>

        <PasswordField
          label="Password"
          value={password}
          onChange={setPassword}
          autoComplete="current-password"
          disabled={loading}
        />

        <label className="flex min-h-11 cursor-pointer items-center gap-3 text-sm text-earth-600">
          <input
            type="checkbox"
            className="h-5 w-5 rounded border-earth-300"
            checked={rememberDevice}
            onChange={(e) => setRememberDevice(e.target.checked)}
          />
          Remember my email on this device
        </label>

        {error && (
          <p className="error" role="alert">
            {error}
          </p>
        )}

        <Button type="submit" className="h-12 w-full rounded-xl" size="lg" disabled={loading}>
          {loading ? 'Signing in…' : 'Sign in'}
        </Button>
      </form>

      <div className="mt-5">
        <GoogleAuthButton next={next} />
      </div>

      <p className="mt-4 text-center text-sm">
        <Link
          href={`/forgot-password?next=${encodeURIComponent(next)}`}
          className="inline-flex min-h-11 items-center"
        >
          Forgot password?
        </Link>
      </p>
      <p className="text-center text-sm text-earth-500">
        New here?{' '}
        <Link
          href={`/signup?next=${encodeURIComponent(next)}`}
          className="inline-flex min-h-11 items-center font-semibold"
        >
          Create an account
        </Link>
      </p>
    </AuthShell>
  )
}
