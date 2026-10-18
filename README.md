# Full-Stack E-Commerce & Order Management Platform

**Next.js · TypeScript · Supabase · PostgreSQL · Stripe**

[Live Site](https://kintampoafricanmarket.com) | [GitHub](https://github.com/richardeyeboah/kintampo-african-market)

Production e-commerce platform for Kintampo African Market, an African and Caribbean grocery store in Columbus, Ohio.

- Storefront: [kintampoafricanmarket.com](https://kintampoafricanmarket.com)
- Web stack: Next.js 16, React 19, TypeScript, Supabase/PostgreSQL, Stripe, Upstash Redis, Postmark
- Native clients: SwiftUI apps for iPhone, Mac, and Apple Watch in [`apple/`](apple/README.md)

## What the application does

### Customer experience

- Browse and search a catalog of 150+ products
- Create an account, save addresses, manage a wishlist, and review products
- Check out as a guest or signed-in customer
- Choose local pickup or nationwide shipping
- Pay through Stripe and receive an email receipt
- View order status and order history

### Store operations

- Manage products, categories, prices, images, and inventory
- Review customers and orders from protected staff tools
- Process refunds and update fulfillment status
- Generate receipts, pickup labels, and shipping information
- Keep an audit trail of order-status changes

## Reliability and payment controls

Prices and totals are calculated on the server before a Stripe Checkout Session is created. Checkout snapshots preserve the purchased item data, and unique Stripe session and payment identifiers prevent the same payment from being recorded twice. Webhooks update payment and fulfillment records after Stripe confirms an event.

Rate limits use Upstash Redis when configured. Sensitive staff and payment operations run on protected server routes, and secrets stay in local or hosting environment variables.

## Testing

The Playwright suite currently contains **61 tests across 13 files**. It covers:

- Server-side protection against price tampering
- Guest and signed-in checkout
- Tax and shipping rules
- Stripe webhooks, refunds, and payment shortfalls
- Receipts and pickup labels
- Cart, navigation, homepage, and mobile behavior
- Shipping-address verification
- Staff and administrative API access

List the tests without running browsers:

```bash
npx playwright test --list
```

Run the full end-to-end suite:

```bash
npx playwright test
```

## Local development

Requirements: Node.js 20+, npm, a Supabase project, and Stripe test credentials.

```bash
npm install
cp .env.example .env.local
npm run dev
```

Open [http://localhost:3000](http://localhost:3000). Add the required values from `.env.example` to `.env.local`; never commit credentials.

Useful checks:

```bash
npm run lint
npm run build
npx playwright test --list
```

## Deployment

The production site is deployed on Vercel from `main`. Supabase provides authentication and PostgreSQL storage, Stripe handles payment processing, and Postmark sends transactional email.

## Repository layout

- `app/` — storefront, account pages, staff tools, and server routes
- `components/` — shared React UI
- `lib/` — data access, checkout, email, rate limiting, and utilities
- `supabase/` — database migrations and policies
- `tests/` — Playwright end-to-end coverage
- `apple/` — SwiftUI clients and setup notes

This repository contains application code. Product, customer, order, payment, and credential data must remain in the configured services and environment variables.
