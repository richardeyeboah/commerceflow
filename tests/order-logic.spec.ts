import { expect, test } from '@playwright/test'
import { buildAuthoritativeOrderItems } from '../lib/order-pricing'
import { calculateShipping } from '../lib/shipping'

test.describe('Order Logic', () => {
  test('authoritative pricing ignores tampered client prices', () => {
    const productMap = new Map([
      [
        'prod-1',
        {
          id: 'prod-1',
          name: 'Malt Drink',
          price: 7.5,
          in_stock: true,
        },
      ],
    ])

    const { orderItems, subtotal } = buildAuthoritativeOrderItems(
      [{ productId: 'prod-1', quantity: 3 }],
      productMap
    )

    expect(orderItems[0]).toMatchObject({
      product_id: 'prod-1',
      product_price: 7.5,
      quantity: 3,
      subtotal: 22.5,
    })
    expect(subtotal).toBe(22.5)
  })

  test('shipping normalizes Ohio State into local US delivery', () => {
    const quote = calculateShipping({
      subtotal: 80,
      country: 'USA',
      state: 'Ohio State',
      method: 'standard',
    })

    expect(quote.zone).toBe('local')
    expect(quote.fee).toBe(9.99)
  })

  test('standard US shipping is free at configured subtotal threshold', () => {
    const below = calculateShipping({
      subtotal: 119.99,
      country: 'US',
      state: 'Texas',
      method: 'standard',
    })
    const at = calculateShipping({
      subtotal: 120,
      country: 'US',
      state: 'Texas',
      method: 'standard',
    })

    expect(below.fee).toBeGreaterThan(0)
    expect(at.fee).toBe(0)
    expect(at.zone).toBe('national')
  })
})
