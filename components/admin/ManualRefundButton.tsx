'use client'

import { useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import { Button } from '@/components/ui/button'

export function ManualRefundButton({
  orderId,
  amount,
}: {
  orderId: string
  amount: number
}) {
  const router = useRouter()
  const requestKey = useRef<string | null>(null)
  const [confirming, setConfirming] = useState(false)
  const [reason, setReason] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  async function handleRefund() {
    requestKey.current ??= crypto.randomUUID()
    setLoading(true)
    setError('')
    try {
      const res = await fetch(`/api/admin/orders/${orderId}/manual-refund`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Idempotency-Key': requestKey.current },
        body: JSON.stringify({ reason }),
      })
      if (!res.ok) {
        const data = await res.json().catch(() => ({}))
        setError(data.error ?? 'Could not mark refund.')
        return
      }
      router.refresh()
    } finally {
      setLoading(false)
    }
  }

  if (!confirming) {
    return (
      <Button
        type="button"
        variant="outline"
        className="border-amber-300 text-amber-800 hover:bg-amber-50"
        onClick={() => setConfirming(true)}
      >
        Mark as refunded (cash/manual)
      </Button>
    )
  }

  return (
    <div className="space-y-3 rounded-lg border border-amber-200 bg-amber-50 p-4">
      <p className="text-sm font-semibold text-amber-900">
        Mark ${amount.toFixed(2)} as manually refunded?
      </p>
      <p className="text-xs text-amber-700">
        This records the refund in your admin and cancels the order. It does NOT process any payment.
      </p>
      <div className="space-y-1.5">
        <label className="form-label text-amber-800">Reason (optional)</label>
        <input
          type="text"
          className="form-input"
          placeholder="Reason"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          maxLength={200}
        />
      </div>
      {error && <p className="text-sm text-red-600">{error}</p>}
      <div className="flex gap-2">
        <Button
          type="button"
          className="bg-amber-700 hover:bg-amber-800 text-white"
          onClick={handleRefund}
          disabled={loading}
        >
          {loading ? 'Saving…' : 'Confirm refund'}
        </Button>
        <Button type="button" variant="outline" onClick={() => setConfirming(false)}>
          Cancel
        </Button>
      </div>
    </div>
  )
}
