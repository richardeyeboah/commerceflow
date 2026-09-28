import { NextResponse } from 'next/server'

export const dynamic = 'force-dynamic'

/** Lets https://kintampoafricanmarket.com/products/{id} open the iPhone app. */
export function GET() {
  const team = process.env.APPLE_TEAM_ID?.trim()
  if (!team) {
    return NextResponse.json({ applinks: { apps: [], details: [] } })
  }
  return NextResponse.json({
    applinks: {
      apps: [],
      details: [
        {
          appIDs: [`${team}.com.kintampoafricanmarket.app`],
          components: [{ '/': '/products/*', comment: 'Open a product in the app' }],
        },
      ],
    },
  })
}
