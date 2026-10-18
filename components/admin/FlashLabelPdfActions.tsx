'use client'

import { useState } from 'react'
import { Check, Copy, Download, ExternalLink } from 'lucide-react'
import { Button } from '@/components/ui/button'
import {
  downloadPdfFile,
  isAbortError,
  pdfFileFromBase64,
  pdfFileFromUrl,
  uploadPdfForShare,
} from '@/lib/client/share-label-pdf'

type Props = {
  orderId: string
  labelUrl?: string | null
  pdfBase64?: string | null
  tracking?: string | null
  kind?: PdfKind
  getFile?: () => Promise<File>
  className?: string
}

type PdfKind = 'label' | 'address-slip' | 'pickup-ticket'

const FILENAME_PREFIX: Record<PdfKind, string> = {
  label: 'shipping-label',
  'address-slip': 'address-slip',
  'pickup-ticket': 'pickup-ticket',
}

const PRINTER_APP_PACKAGE = 'com.flashlabel.flashlabelpro'

function openLabelPrinterApp() {
  window.location.href = `intent://#Intent;package=${PRINTER_APP_PACKAGE};scheme=https;end`
}

export function FlashLabelPdfActions({
  orderId,
  labelUrl,
  pdfBase64,
  tracking,
  kind = 'label',
  getFile,
  className,
}: Props) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [status, setStatus] = useState('')
  const [copied, setCopied] = useState(false)

  const filename = `${FILENAME_PREFIX[kind]}-${tracking || orderId.slice(0, 8)}.pdf`

  async function resolveFile(): Promise<File> {
    if (getFile) return getFile()
    if (pdfBase64) return pdfFileFromBase64(pdfBase64, filename)
    if (labelUrl && kind !== 'label') return pdfFileFromUrl(labelUrl, filename)
    const res = await fetch(`/api/admin/orders/${orderId}/shipping/label-file`)
    if (!res.ok) {
      const data = await res.json().catch(() => ({}))
      throw new Error(typeof data.error === 'string' ? data.error : 'No label PDF available.')
    }
    return new File([await res.blob()], filename, { type: 'application/pdf' })
  }

  async function handleDownload() {
    setBusy(true)
    setError('')
    setStatus('')
    try {
      const file = await resolveFile()
      const head = new Uint8Array(await file.slice(0, 5).arrayBuffer())
      const magic = String.fromCharCode(...head)
      if (!magic.startsWith('%PDF')) {
        throw new Error('Could not prepare a valid PDF.')
      }
      downloadPdfFile(file)
      setStatus('PDF downloaded.')
    } catch (err) {
      if (isAbortError(err)) return
      setError(err instanceof Error ? err.message : 'Could not download PDF.')
    } finally {
      setBusy(false)
    }
  }

  async function handleCopyLink() {
    setBusy(true)
    setError('')
    setStatus('')
    try {
      const file = await resolveFile()
      const url = await uploadPdfForShare(orderId, file, kind)
      await navigator.clipboard.writeText(url)
      setCopied(true)
      setStatus('Link copied. Expires in 5 minutes.')
      window.setTimeout(() => setCopied(false), 2000)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not copy link.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className={className}>
      <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap">
        <Button type="button" onClick={() => void handleDownload()} disabled={busy}>
          <Download className="mr-1.5 h-4 w-4" aria-hidden />
          {busy ? 'Preparing…' : 'Download PDF'}
        </Button>
        <Button type="button" variant="outline" onClick={openLabelPrinterApp}>
          <ExternalLink className="mr-1.5 h-4 w-4" aria-hidden />
          Open label printer
        </Button>
        <Button type="button" variant="outline" onClick={() => void handleCopyLink()} disabled={busy}>
          {copied ? <Check className="mr-1.5 h-4 w-4" aria-hidden /> : <Copy className="mr-1.5 h-4 w-4" aria-hidden />}
          {copied ? 'Copied' : 'Copy link'}
        </Button>
        {kind === 'label' ? (
          <a
            href={`/api/admin/orders/${orderId}/shipping/label-file`}
            className="inline-flex h-11 items-center px-1 text-sm font-medium text-brand-700 no-underline hover:underline"
            download={filename}
          >
            Browser download
          </a>
        ) : null}
      </div>
      {status ? <p className="mt-2 text-sm text-emerald-800">{status}</p> : null}
      {error ? (
        <p className="mt-2 text-sm font-medium text-red-700" role="alert">
          {error}
        </p>
      ) : null}
    </div>
  )
}
