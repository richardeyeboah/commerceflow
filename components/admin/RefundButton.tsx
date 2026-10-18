'use client'

import { useRouter } from 'next/navigation'
import { useRef, useState } from 'react'
import { Check } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

export function RefundButton({ orderId, maxAmount }: { orderId: string; maxAmount: number }) {
  const router = useRouter()
  const [amount, setAmount] = useState(maxAmount.toFixed(2))
  const [reason, setReason] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const requestKey = useRef<string | null>(null)
  const [done, setDone] = useState(false)

  async function refund(e: React.FormEvent) {
    e.preventDefault()
    if (!confirm(`Refund $${amount} for order ${orderId}? This cannot be undone.`)) return
    requestKey.current ??= crypto.randomUUID()
    setBusy(true)
    setError('')
    try {
      const res = await fetch(`/api/admin/orders/${orderId}/refund`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Idempotency-Key': requestKey.current },
        body: JSON.stringify({ amount: parseFloat(amount), reason }),
      })
      const data = await res.json().catch(() => ({}))
      if (!res.ok) {
        setError(data.error ?? 'Refund failed.')
        return
      }
      setDone(true)
      router.refresh()
    } catch {
      setError('Network error.')
    } finally {
      setBusy(false)
    }
  }

  if (done) {
    return (
      <p className="inline-flex items-center gap-1.5 rounded-lg bg-emerald-50 px-3 py-2 text-sm font-medium text-emerald-700">
        <Check className="h-4 w-4" strokeWidth={2.5} aria-hidden /> Refund issued.
      </p>
    )
  }

  return (
    <form onSubmit={refund} className="space-y-4">
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-1.5">
          <label className="form-label" htmlFor="refund-amount">
            Amount ($) — max ${maxAmount.toFixed(2)}
          </label>
          <Input
            id="refund-amount"
            type="number"
            step="0.01"
            min="0.01"
            max={maxAmount}
            value={amount}
            onChange={(e) => { requestKey.current = null; setAmount(e.target.value) }}
            required
          />
        </div>
        <div className="space-y-1.5">
          <label className="form-label" htmlFor="refund-reason">
            Reason (optional)
          </label>
          <Input
            id="refund-reason"
            type="text"
            value={reason}
            onChange={(e) => { requestKey.current = null; setReason(e.target.value) }}
          />
        </div>
      </div>

      {error && <p className="error">{error}</p>}

      <Button type="submit" variant="destructive" disabled={busy}>
        {busy ? 'Refunding…' : 'Issue refund via Stripe'}
      </Button>
    </form>
  )
}
