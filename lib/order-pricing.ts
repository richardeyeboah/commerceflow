import type { CartItem } from '@/types'

export type SanitizedCartLine = {
  productId: string
  quantity: number
}

export type AuthoritativeProduct = {
  id: string
  name: string
  price: number
  in_stock: boolean
}

export type AuthoritativeOrderItem = {
  product_id: string
  product_name: string
  product_price: number
  quantity: number
  subtotal: number
  tax_amount?: number
}

export function sanitizeCartItems(items: CartItem[]) {
  const quantities = new Map<string, number>()
  for (const item of items) {
    const productId = item?.product?.id?.trim()
    const quantity = Number(item?.quantity ?? 0)
    if (!productId || !Number.isInteger(quantity) || quantity < 1 || quantity > 99) {
      throw new Error('Each cart line must contain a product and quantity from 1 to 99.')
    }
    const combined = (quantities.get(productId) ?? 0) + quantity
    if (combined > 99) throw new Error('Maximum quantity per product is 99.')
    quantities.set(productId, combined)
  }
  return [...quantities].map(([productId, quantity]) => ({ productId, quantity }))
}

export function buildAuthoritativeOrderItems(
  items: SanitizedCartLine[],
  productMap: Map<string, AuthoritativeProduct>
) {
  const orderItems: AuthoritativeOrderItem[] = items.map((item) => {
    const product = productMap.get(item.productId)
    if (!product) {
      throw new Error(`Missing authoritative product for ${item.productId}`)
    }

    return {
      product_id: product.id,
      product_name: product.name,
      product_price: product.price,
      quantity: item.quantity,
      subtotal: product.price * item.quantity,
    }
  })

  const subtotal = orderItems.reduce((sum, item) => sum + item.subtotal, 0)

  return { orderItems, subtotal }
}
