import { createHash } from 'node:crypto'
import { Redis } from '@upstash/redis'
import { NextResponse } from 'next/server'

const memory = new Map<string, { count: number; expires: number }>()
/** Shared fixed-window limiter. Production fails closed without distributed storage. */
export async function limitPublicRequest(request: Request, scope: string, max: number, windowSeconds = 900): Promise<NextResponse | null> {
  const ip = request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown'
  const window = Math.floor(Date.now() / (windowSeconds * 1000))
  const key = `commerce:limit:${scope}:${window}:${createHash('sha256').update(ip).digest('hex').slice(0,32)}`
  let count: number
  const url = process.env.UPSTASH_REDIS_REST_URL?.trim()
  const token = process.env.UPSTASH_REDIS_REST_TOKEN?.trim()
  if (url && token) {
    try {
      const redis = new Redis({ url, token })
      // Atomic count + TTL: failures cannot leave an immortal lockout key.
      count = Number(await redis.eval("local n=redis.call('INCR',KEYS[1]); redis.call('EXPIRE',KEYS[1],ARGV[1]); return n", [key], [windowSeconds]))
    } catch {
      return NextResponse.json({ error: 'Please try again shortly.' }, { status: 503 })
    }
  } else {
    if (process.env.NODE_ENV === 'production') return NextResponse.json({ error: 'Please try again shortly.' }, { status: 503 })
    const now = Date.now()
    for (const [k, v] of memory) if (v.expires <= now) memory.delete(k)
    const entry = memory.get(key) ?? { count: 0, expires: now + windowSeconds * 1000 }
    entry.count += 1; memory.set(key, entry); count = entry.count
  }
  return count > max ? NextResponse.json({ error: 'Too many requests. Please try again later.' }, {
    status: 429, headers: { 'Retry-After': String(windowSeconds), 'Cache-Control': 'no-store' },
  }) : null
}
