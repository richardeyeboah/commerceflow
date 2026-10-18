/**
 * Mirrors .github/workflows/ci.yml for local runs.
 * Usage: node scripts/ci.mjs
 */
import { readFileSync } from 'node:fs'
import { execSync } from 'node:child_process'

const env = {
  ...process.env,
  // Mask every local provider setting before Next reads .env.local.
  ...Object.fromEntries([...readFileSync('.env.example','utf8').matchAll(/^([A-Z][A-Z0-9_]*)=/gm)].map((m) => [m[1], ''])),
  NEXT_PUBLIC_SUPABASE_URL: 'https://placeholder.supabase.co',
  NEXT_PUBLIC_SUPABASE_ANON_KEY: 'placeholder-anon-key',
  SUPABASE_SERVICE_ROLE_KEY: 'placeholder-service-role',
  STRIPE_SECRET_KEY: 'sk_test_placeholder',
  NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY: 'pk_test_placeholder',
  STRIPE_WEBHOOK_SECRET: 'whsec_placeholder',
  NEXT_PUBLIC_SITE_URL: 'https://placeholder.example',
  ADMIN_PASSWORD: 'ci-placeholder',
  ADMIN_SESSION_SECRET: 'ci-placeholder-secret',
}

function run(cmd) {
  console.log(`\n> ${cmd}\n`)
  execSync(cmd, { stdio: 'inherit', env })
}

if (!process.argv.includes('--smoke-only')) {
  run('npm run lint')
  run('npm test')
  run('npm run test:logic')
  run('npm run typecheck')
  run('npm run build')
}
if (process.argv.includes('--browser') || process.argv.includes('--smoke-only')) {
  env.CI = 'true'
  env.PLAYWRIGHT_NEXT_START = '1'
  run('npm run test:smoke')
}
