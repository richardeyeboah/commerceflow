import Link from 'next/link'
import {
  AlertTriangle,
  ArrowDownRight,
  ArrowUpRight,
  Box,
  ChevronRight,
  DollarSign,
  Download,
  ExternalLink,
  Package,
  Plus,
  ReceiptText,
  ShoppingBag,
  TrendingUp,
  Users,
} from 'lucide-react'
import { supabaseAdmin } from '@/lib/supabase-admin'
import { ORDER_STATUS_LABEL, normalizeOrderStatus, type OrderStatus } from '@/lib/order-status'
import { requireAdminPage } from '@/lib/auth/require-admin-page'
import { getReportTimeZoneLabel, money } from '@/lib/admin/revenue-stats'
import {
  RANGE_OPTIONS,
  deltaPct,
  resolveRange,
  type RangeKey,
} from '@/lib/admin/date-range'
import {
  computePeriodStats,
  countableOrderIdsFrom,
  topProducts,
  type PeriodOrderItem,
  type PeriodOrderRow,
} from '@/lib/admin/period-stats'
import { formatOrderNumber } from '@/lib/orders/order-number'
import { NEEDS_ACTION_STATUSES } from '@/lib/admin/ops-health'
import { Input } from '@/components/ui/input'
import { Button } from '@/components/ui/button'

const STATUS_PILL_COLORS: Record<OrderStatus, string> = {
  ordered: 'bg-blue-50 text-blue-700',
  processing: 'bg-amber-50 text-amber-700',
  ready_for_pickup: 'bg-teal-50 text-teal-700',
  shipped: 'bg-violet-50 text-violet-700',
  out_for_delivery: 'bg-indigo-50 text-indigo-700',
  delivered: 'bg-emerald-50 text-emerald-700',
  cancelled: 'bg-red-50 text-red-700',
}

const VALID_RANGE_KEYS = new Set(RANGE_OPTIONS.map((o) => o.id))

function pill(status: OrderStatus) {
  return (
    <span className={`admin-status-pill ${STATUS_PILL_COLORS[status]}`}>
      {ORDER_STATUS_LABEL[status]}
    </span>
  )
}

function buildHref(params: Record<string, string | undefined>): string {
  const sp = new URLSearchParams()
  for (const [k, v] of Object.entries(params)) {
    if (v) sp.set(k, v)
  }
  const s = sp.toString()
  return s ? `/admin?${s}` : '/admin'
}

const DASHBOARD_ORDER_COLUMNS =
  'id, total_amount, subtotal_amount, shipping_fee, status, refunded_at, refund_amount, created_at, order_number, customer_name'

async function fetchOrdersAndItems(startIso: string | null, endIso: string) {
  const buildQuery = (columns: string) => {
    let q = supabaseAdmin.from('orders').select(columns).lt('created_at', endIso)
    if (startIso) q = q.gte('created_at', startIso)
    return q
  }

  // payment_status only exists after the phone-orders migration; fall back without it.
  const initialResult = await buildQuery(
    `${DASHBOARD_ORDER_COLUMNS}, payment_status`
  )
  let rawOrders = initialResult.data
  const error = initialResult.error
  if (error && /payment_status/i.test(error.message)) {
    ;({ data: rawOrders } = await buildQuery(DASHBOARD_ORDER_COLUMNS))
  }
  const orders = (rawOrders ?? []) as unknown as Array<
    PeriodOrderRow & { order_number: number | null; customer_name: string | null }
  >

  if (orders.length === 0) {
    return { orders, items: [] as PeriodOrderItem[] }
  }

  const ids = orders.map((o) => o.id)
  const { data: rawItems } = await supabaseAdmin
    .from('order_items')
    .select('order_id, product_id, product_name, quantity, subtotal, product_price')
    .in('order_id', ids)
  return { orders, items: (rawItems ?? []) as PeriodOrderItem[] }
}

export default async function AdminDashboard({
  searchParams,
}: {
  searchParams: Promise<{ range?: string; from?: string; to?: string }>
}) {
  await requireAdminPage()
  const sp = await searchParams

  const rangeKey = (VALID_RANGE_KEYS.has(sp.range as RangeKey)
    ? (sp.range as RangeKey)
    : '7d') as RangeKey
  const range = resolveRange(rangeKey, sp.from, sp.to)
  const startIso = range.start?.toUTC().toISO() ?? null
  const endIso = range.end.toUTC().toISO()!

  const prevStartIso = range.prevStart?.toUTC().toISO() ?? null
  const prevEndIso = range.prevEnd?.toUTC().toISO() ?? null

  const [
    { orders: currOrders, items: currItems },
    prev,
    { count: productsCount },
    { count: lowStockCount },
    { count: customersCount },
    { count: ordersAllTime },
    { data: recentOrders },
    { count: pendingReviewsCount },
    { count: readyPickupCount },
    { count: needsActionCount },
  ] = await Promise.all([
    fetchOrdersAndItems(startIso, endIso),
    prevStartIso && prevEndIso
      ? fetchOrdersAndItems(prevStartIso, prevEndIso)
      : Promise.resolve({ orders: [], items: [] as PeriodOrderItem[] }),
    supabaseAdmin.from('products').select('*', { count: 'exact', head: true }),
    supabaseAdmin
      .from('products')
      .select('*', { count: 'exact', head: true })
      .eq('in_stock', false),
    supabaseAdmin.from('profiles').select('*', { count: 'exact', head: true }),
    supabaseAdmin.from('orders').select('*', { count: 'exact', head: true }),
    supabaseAdmin
      .from('orders')
      .select('id, order_number, customer_name, total_amount, status, created_at')
      .order('created_at', { ascending: false })
      .limit(8),
    supabaseAdmin
      .from('product_reviews')
      .select('id', { count: 'exact', head: true })
      .eq('approved', false),
    supabaseAdmin
      .from('orders')
      .select('id', { count: 'exact', head: true })
      .eq('status', 'ready_for_pickup'),
    supabaseAdmin
      .from('orders')
      .select('id', { count: 'exact', head: true })
      .in('status', [...NEEDS_ACTION_STATUSES]),
  ])

  const periodStats = computePeriodStats(currOrders, currItems)
  const prevStats = computePeriodStats(prev.orders as PeriodOrderRow[], prev.items)

  const bestSellers = topProducts(currItems, countableOrderIdsFrom(currOrders), 5)

  // For the export link, preserve the same range/from/to.
  const exportHref =
    `/api/admin/orders/export?range=${rangeKey}` +
    (sp.from ? `&from=${encodeURIComponent(sp.from)}` : '') +
    (sp.to ? `&to=${encodeURIComponent(sp.to)}` : '')

  const customParam = (k: 'from' | 'to') => (rangeKey === 'custom' ? sp[k] : undefined)

  return (
    <div className="mx-auto max-w-[1500px] space-y-6 sm:space-y-8">
      <header className="flex flex-col gap-4 xl:flex-row xl:items-end xl:justify-between">
        <div>
          <p className="text-xs font-medium text-slate-500">Overview</p>
          <h1 className="admin-page-title mt-1">Dashboard</h1>
          <p className="mt-1.5 text-sm text-slate-500">
            Sales, fulfillment, and inventory.
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Link href="/" target="_blank" className="no-underline">
            <Button size="sm" variant="outline" className="gap-1.5 rounded-lg px-3.5">
              <ExternalLink className="h-4 w-4" aria-hidden />
              View store
            </Button>
          </Link>
          <Link href="/admin/products/new" className="no-underline">
            <Button size="sm" className="gap-1.5 rounded-lg px-3.5">
              <Plus className="h-4 w-4" aria-hidden />
              Add product
            </Button>
          </Link>
        </div>
      </header>

      <section className="admin-card p-0 sm:p-0">
        <div className="flex flex-col gap-2 border-b border-slate-100 px-5 py-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 className="admin-section-title">Needs attention</h2>
            <p className="mt-0.5 text-xs text-slate-500">Open work across the store.</p>
          </div>
          <span className="inline-flex w-fit items-center rounded-full bg-slate-100 px-2.5 py-1 text-[11px] font-medium text-slate-600">
            Today
          </span>
        </div>
        <div className="grid grid-cols-2 xl:grid-cols-4">
          <TaskCard
            icon={ShoppingBag}
            label="Needs action"
            value={needsActionCount ?? 0}
            href="/admin/orders?queue=needs_action"
            tone="blue"
          />
          <TaskCard
            icon={Box}
            label="Ready for pickup"
            value={readyPickupCount ?? 0}
            href="/admin/orders?status=ready_for_pickup"
            tone="teal"
          />
          <TaskCard
            icon={AlertTriangle}
            label="Out of stock"
            value={lowStockCount ?? 0}
            href="/admin/products?stock=out"
            tone="amber"
          />
          <TaskCard
            icon={ReceiptText}
            label="Reviews to approve"
            value={pendingReviewsCount ?? 0}
            href="/admin/reviews"
            tone="violet"
          />
        </div>
      </section>

      <section className="flex flex-col gap-3 rounded-2xl border border-slate-200 bg-white p-3 shadow-[0_1px_2px_rgb(15_23_42/0.04)] sm:flex-row sm:items-center sm:justify-between">
        <div className="flex min-w-0 flex-wrap gap-1.5">
          {RANGE_OPTIONS.map((opt) => {
            const active = opt.id === rangeKey
            const params: Record<string, string | undefined> = { range: opt.id }
            if (opt.id === 'custom') {
              params.from = customParam('from')
              params.to = customParam('to')
            }
            return (
              <Link
                key={opt.id}
                href={buildHref(params)}
                className={`admin-status-pill no-underline ${
                  active
                    ? 'bg-slate-950 text-white'
                    : 'text-slate-600 hover:bg-slate-100 hover:text-slate-950'
                }`}
              >
                {opt.label}
              </Link>
            )
          })}
        </div>
        <div className="flex items-center gap-2 px-1 text-xs text-slate-500">
          <span className="hidden md:inline">{range.formattedRange} · {getReportTimeZoneLabel()}</span>
          <Link href={exportHref} className="no-underline">
            <Button size="sm" variant="ghost" className="gap-1.5 rounded-lg px-2.5">
              <Download className="h-3.5 w-3.5" aria-hidden />
              Export
            </Button>
          </Link>
        </div>
      </section>

      {rangeKey === 'custom' && (
        <form
          method="GET"
          className="flex flex-wrap items-end gap-2 rounded-xl border border-earth-200 bg-white p-3"
        >
          <input type="hidden" name="range" value="custom" />
          <label className="flex flex-col text-xs font-semibold uppercase tracking-wider text-earth-500">
            From
            <Input
              type="date"
              name="from"
              defaultValue={sp.from ?? ''}
              className="mt-1 h-11 w-44"
              required
            />
          </label>
          <label className="flex flex-col text-xs font-semibold uppercase tracking-wider text-earth-500">
            To
            <Input
              type="date"
              name="to"
              defaultValue={sp.to ?? ''}
              className="mt-1 h-11 w-44"
              required
            />
          </label>
          <Button type="submit" size="sm">
            Apply
          </Button>
        </form>
      )}

      {/* Headline KPIs */}
      <section>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4 sm:gap-4">
          <Kpi
            icon={DollarSign}
            label="Gross revenue"
            value={money(periodStats.gross)}
            delta={deltaPct(periodStats.gross, prevStats.gross)}
            deltaLabel="vs. previous"
            sub={
              periodStats.unpaidCount > 0
                ? `+ ${money(periodStats.unpaidTotal)} unpaid (${periodStats.unpaidCount}) not counted`
                : undefined
            }
          />
          <Kpi
            icon={ShoppingBag}
            label="Orders"
            value={String(periodStats.ordersCount)}
            delta={deltaPct(periodStats.ordersCount, prevStats.ordersCount)}
            deltaLabel="vs. previous"
          />
          <Kpi
            icon={Package}
            label="Units sold"
            value={String(periodStats.unitsSold)}
            delta={deltaPct(periodStats.unitsSold, prevStats.unitsSold)}
            deltaLabel="vs. previous"
          />
          <Kpi
            icon={TrendingUp}
            label="Avg order value"
            value={money(periodStats.averageOrderValue)}
            delta={deltaPct(periodStats.averageOrderValue, prevStats.averageOrderValue)}
            deltaLabel="vs. previous"
          />
        </div>
      </section>

      {/* Secondary stats */}
      <section>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4 sm:gap-4">
          <Kpi
            icon={ReceiptText}
            label="Net revenue"
            value={money(periodStats.netRevenue)}
            sub={`After ${money(periodStats.refundsTotal)} refunds`}
          />
          <Kpi
            icon={ArrowDownRight}
            label="Refunds"
            value={periodStats.refundsCount > 0 ? money(periodStats.refundsTotal) : '$0.00'}
            sub={`${periodStats.refundsCount} refund${periodStats.refundsCount === 1 ? '' : 's'}`}
            tone={periodStats.refundsCount > 0 ? 'warning' : 'neutral'}
          />
          <Kpi
            icon={AlertTriangle}
            label="Cancelled"
            value={String(periodStats.cancelledCount)}
            sub="not counted in gross"
            tone={periodStats.cancelledCount > 0 ? 'warning' : 'neutral'}
          />
          <Kpi
            label="Previous period"
            value={money(prevStats.gross)}
            sub={`${prevStats.ordersCount} orders`}
          />
        </div>
      </section>

      {/* Best sellers + operations */}
      <div className="grid gap-6 md:grid-cols-3">
        <section className="md:col-span-2">
          <div className="mb-3 flex items-center justify-between">
            <h2 className="admin-section-title">Top products in this period</h2>
            <Link
              href="/admin/products"
            className="inline-flex min-h-11 items-center gap-0.5 text-sm font-medium text-brand-700 no-underline hover:text-brand-800"
            >
              All products <ChevronRight className="h-4 w-4" />
            </Link>
          </div>
          {bestSellers.length === 0 ? (
            <div className="admin-card text-center text-sm text-earth-500">
              No items sold in this period.
            </div>
          ) : (
            <div className="admin-table-wrap overflow-x-auto">
              <table className="admin-table">
                <thead>
                  <tr>
                    <th>Product</th>
                    <th className="text-right">Units</th>
                    <th className="text-right">Revenue</th>
                  </tr>
                </thead>
                <tbody>
                  {bestSellers.map((b) => (
                    <tr key={`${b.productId ?? ''}-${b.productName}`}>
                      <td className="font-medium text-earth-900">{b.productName}</td>
                      <td className="text-right tabular-nums">{b.units}</td>
                      <td className="text-right tabular-nums">{money(b.revenue)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>

        <section>
          <h2 className="admin-section-title mb-3">Operations</h2>
          <div className="grid grid-cols-2 gap-3">
            <OpCard
              icon={Box}
              label="Needs action"
              value={needsActionCount ?? 0}
              href="/admin/orders?queue=needs_action"
              cta="Process"
              tone={(needsActionCount ?? 0) > 0 ? 'attention' : 'neutral'}
            />
            <OpCard
              icon={AlertTriangle}
              label="Out of stock"
              value={lowStockCount ?? 0}
              href="/admin/products?stock=out"
              cta="Restock"
              tone={Number(lowStockCount ?? 0) > 0 ? 'warning' : 'neutral'}
            />
            <OpCard
              icon={Package}
              label="Products"
              value={productsCount ?? 0}
              href="/admin/products"
              cta="Manage"
            />
            <OpCard
              icon={Users}
              label="Customers"
              value={customersCount ?? 0}
              href="/admin/customers"
              cta="View"
            />
            <OpCard
              icon={ShoppingBag}
              label="Orders (all time)"
              value={ordersAllTime ?? 0}
              href="/admin/orders?queue=all"
              cta="Browse"
            />
          </div>
        </section>
      </div>

      {/* Recent orders (always shows latest 8 regardless of range) */}
      <section>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="admin-section-title">Latest orders</h2>
          <Link
            href="/admin/orders?queue=all"
            className="inline-flex min-h-11 items-center gap-0.5 text-sm font-medium text-brand-700 no-underline hover:text-brand-800"
          >
            View all <ChevronRight className="h-4 w-4" />
          </Link>
        </div>
        {!recentOrders || recentOrders.length === 0 ? (
          <div className="admin-card text-center">
            <p className="text-sm text-earth-600">No orders yet.</p>
          </div>
        ) : (
          <>
            {/* Mobile cards */}
            <ul className="space-y-2 sm:hidden">
              {recentOrders.map((order) => {
                const st = normalizeOrderStatus(order.status)
                return (
                  <li key={order.id}>
                    <Link
                      href={`/admin/orders/${order.id}`}
                      className="admin-card flex flex-col gap-1 no-underline"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <p className="font-mono text-xs font-semibold text-earth-900">
                            {formatOrderNumber(order.order_number) || '—'}
                          </p>
                          <p className="text-sm font-medium text-earth-800">{order.customer_name ?? '—'}</p>
                        </div>
                        <span className="tabular-nums text-sm font-semibold text-earth-900">
                          {money(Number(order.total_amount ?? 0))}
                        </span>
                      </div>
                      <div className="mt-1 flex items-center justify-between gap-3">
                        {pill(st)}
                        <span className="text-xs text-earth-500">
                          {new Date(order.created_at).toLocaleDateString()}
                        </span>
                      </div>
                    </Link>
                  </li>
                )
              })}
            </ul>
            {/* Desktop table */}
            <div className="admin-table-wrap hidden overflow-x-auto sm:block">
              <table className="admin-table">
                <thead>
                  <tr>
                    <th>Order</th>
                    <th>Customer</th>
                    <th>Total</th>
                    <th>Status</th>
                    <th>Date</th>
                    <th aria-label="Actions"></th>
                  </tr>
                </thead>
                <tbody>
                  {recentOrders.map((order) => {
                    const st = normalizeOrderStatus(order.status)
                    return (
                      <tr key={order.id}>
                        <td className="font-mono text-xs font-semibold text-earth-900">
                          {formatOrderNumber(order.order_number) || '—'}
                        </td>
                        <td className="font-medium text-earth-900">{order.customer_name ?? '—'}</td>
                        <td className="tabular-nums">{money(Number(order.total_amount ?? 0))}</td>
                        <td>{pill(st)}</td>
                        <td className="text-earth-600">
                          {new Date(order.created_at).toLocaleString(undefined, {
                            month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
                          })}
                        </td>
                        <td className="text-right">
                          <Link
                            href={`/admin/orders/${order.id}`}
                            className="text-sm font-medium text-brand-700 no-underline hover:text-brand-800"
                          >
                            View
                          </Link>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          </>
        )}
      </section>
    </div>
  )
}

type IconCmp = React.ComponentType<{ className?: string; strokeWidth?: number; 'aria-hidden'?: boolean }>

function TaskCard({
  icon: Icon,
  label,
  value,
  href,
  tone,
}: {
  icon: IconCmp
  label: string
  value: number
  href: string
  tone: 'blue' | 'teal' | 'amber' | 'violet'
}) {
  const tones = {
    blue: 'bg-blue-50 text-blue-700',
    teal: 'bg-teal-50 text-teal-700',
    amber: 'bg-amber-50 text-amber-700',
    violet: 'bg-violet-50 text-violet-700',
  }

  return (
    <Link
      href={href}
      className="group relative flex min-h-32 flex-col items-start gap-3 border-b border-slate-100 px-4 py-5 no-underline even:border-l hover:bg-slate-50 sm:min-h-28 sm:flex-row sm:items-center sm:gap-4 sm:px-5 xl:border-b-0 xl:border-l-0 xl:border-r xl:last:border-r-0"
    >
      <span className={`flex h-11 w-11 shrink-0 items-center justify-center rounded-xl ${tones[tone]}`}>
        <Icon className="h-5 w-5" strokeWidth={1.75} aria-hidden />
      </span>
      <span className="min-w-0">
        <span className="block text-2xl font-semibold tracking-[-0.03em] tabular-nums text-slate-950">
          {value}
        </span>
        <span className="mt-0.5 block text-xs font-medium text-slate-500 group-hover:text-slate-700">
          {label}
        </span>
      </span>
      <ChevronRight className="absolute right-4 top-5 h-4 w-4 shrink-0 text-slate-300 group-hover:text-slate-600 sm:static sm:ml-auto" aria-hidden />
    </Link>
  )
}

function Kpi({
  icon: Icon,
  label,
  value,
  delta,
  deltaLabel,
  sub,
  tone = 'neutral',
}: {
  icon?: IconCmp
  label: string
  value: string
  delta?: number | null
  deltaLabel?: string
  sub?: string
  tone?: 'neutral' | 'warning' | 'attention'
}) {
  const positive = typeof delta === 'number' && delta >= 0
  const DeltaIcon = positive ? ArrowUpRight : ArrowDownRight
  const valueClass =
    tone === 'warning'
      ? 'text-amber-700'
      : tone === 'attention'
        ? 'text-blue-700'
        : 'text-earth-900'

  return (
    <div className="admin-kpi">
      <div className="flex items-center justify-between">
        <p className="admin-kpi-label">{label}</p>
        {Icon && <Icon className="h-4 w-4 text-earth-400" strokeWidth={1.75} aria-hidden />}
      </div>
      <p className={`admin-kpi-value ${valueClass}`}>{value}</p>
      {typeof delta === 'number' ? (
        <p
          className={`admin-kpi-delta inline-flex items-center gap-1 ${
            positive ? 'text-emerald-700' : 'text-red-700'
          }`}
        >
          <DeltaIcon className="h-3 w-3" strokeWidth={2} aria-hidden />
          {positive ? '+' : ''}
          {delta.toFixed(1)}%
          {deltaLabel && <span className="font-normal text-earth-500"> {deltaLabel}</span>}
        </p>
      ) : delta === null && deltaLabel ? (
        <p className="admin-kpi-delta text-earth-500">— {deltaLabel}</p>
      ) : null}
      {sub && delta === undefined && <p className="admin-kpi-delta text-earth-500">{sub}</p>}
      {sub && delta !== undefined && (
        <p className="admin-kpi-delta text-earth-500">{sub}</p>
      )}
    </div>
  )
}

function OpCard({
  icon: Icon,
  label,
  value,
  sub,
  href,
  cta,
  tone = 'neutral',
}: {
  icon?: IconCmp
  label: string
  value: number | string
  sub?: string
  href?: string
  cta?: string
  tone?: 'neutral' | 'warning' | 'attention'
}) {
  const toneClass =
    tone === 'warning'
      ? 'text-amber-700'
      : tone === 'attention'
        ? 'text-blue-700'
        : 'text-earth-900'

  return (
    <div className="admin-kpi flex flex-col">
      <div className="flex items-center justify-between">
        <p className="admin-kpi-label">{label}</p>
        {Icon && <Icon className="h-4 w-4 text-earth-400" strokeWidth={1.75} aria-hidden />}
      </div>
      <p className={`admin-kpi-value ${toneClass}`}>{value}</p>
      {sub && <p className="admin-kpi-delta text-earth-500">{sub}</p>}
      {href && cta && (
        <Link
          href={href}
          className="mt-3 inline-flex min-h-11 items-center gap-0.5 text-xs font-semibold text-brand-700 no-underline hover:text-brand-800"
        >
          {cta} <ChevronRight className="h-3 w-3" />
        </Link>
      )}
    </div>
  )
}

export const dynamic = 'force-dynamic'
