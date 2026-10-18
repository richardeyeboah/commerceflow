import { createClientOptional } from '@/lib/supabase/server'
import { getSupabasePublicConfig, formatCatalogError, SupabaseConfigError } from '@/lib/supabase/config'
import { fetchCuratedHomepageShowcase } from '@/lib/supabase/homepage-curation'
import { filterStorefrontProducts, isHiddenFromStorefront } from '@/lib/catalog/public-product-filter'
import {
  STOREFRONT_PRODUCT_SELECT,
  STOREFRONT_PRODUCT_SELECT_LEGACY,
} from '@/lib/product-pricing'
import { fashionQueryCategories } from '@/lib/constants/categories'
import type { Product } from '@/types'

export type ProductsQueryResult = {
  products: Product[]
  errorMessage: string | null
  configured: boolean
}

export type SortOption = 'featured' | 'price-asc' | 'price-desc' | 'name-asc' | 'newest'

const SORT_CONFIG: Record<SortOption, { column: string; ascending: boolean }> = {
  featured: { column: 'created_at', ascending: false },
  newest: { column: 'created_at', ascending: false },
  'price-asc': { column: 'price', ascending: true },
  'price-desc': { column: 'price', ascending: false },
  'name-asc': { column: 'name', ascending: true },
}


export async function fetchProductsForShop(options?: {
  q?: string
  category?: string
  /** When set (and no single category), limit to these categories — e.g. fashion dept. */
  categories?: readonly string[]
  brand?: string
  dietary?: string
  minPrice?: number
  maxPrice?: number
  inStockOnly?: boolean
  sort?: SortOption
}): Promise<ProductsQueryResult> {
  const { configured } = getSupabasePublicConfig()
  if (!configured) {
    return {
      products: [],
      errorMessage: formatCatalogError(null, false),
      configured: false,
    }
  }

  try {
    const supabase = await createClientOptional()
    if (!supabase) {
      return {
        products: [],
        errorMessage: formatCatalogError(null, false),
        configured: false,
      }
    }

    const q = options?.q?.trim() ?? ''
    let products: Product[] = []
    const scoped =
      Boolean(options?.category?.trim()) || Boolean(options?.categories?.length)

    // Fuzzy RPC ranks across the whole catalog (grocery-heavy). When the shop is
    // scoped to a department/category, skip it and query with .eq/.in so fashion
    // (and other hubs) actually return matches instead of empty post-filters.
    if (q && !scoped) {
      const { data: fuzzy, error: fuzzyErr } = await supabase.rpc('search_products_fuzzy', {
        search_query: q,
        result_limit: 60,
      })
      if (!fuzzyErr && Array.isArray(fuzzy)) {
        products = fuzzy as Product[]
      }
    }

    if (!q || products.length === 0 || scoped) {
      let built = supabase.from('products').select(STOREFRONT_PRODUCT_SELECT)
      if (q) {
        const terms = expandSearchTerms(q).filter((t) => t.trim().length > 0).slice(0, 6)
        const orFilter = terms
          .flatMap((t) => [
            `name.ilike.%${t}%`,
            `category.ilike.%${t}%`,
            `description.ilike.%${t}%`,
            `brand.ilike.%${t}%`,
          ])
          .join(',')
        built = built.or(orFilter)
      }
      if (options?.category) built = built.eq('category', options.category)
      else if (options?.categories?.length) {
        built = built.in('category', [...options.categories])
      }
      if (options?.brand?.trim()) built = built.ilike('brand', options.brand.trim())
      if (options?.dietary?.trim()) built = built.contains('dietary_tags', [options.dietary.trim()])
      if (options?.minPrice != null && !Number.isNaN(options.minPrice)) {
        built = built.gte('price', options.minPrice)
      }
      if (options?.maxPrice != null && !Number.isNaN(options.maxPrice)) {
        built = built.lte('price', options.maxPrice)
      }
      if (options?.inStockOnly) {
        built = built.eq('in_stock', true)
      }

      const sort = SORT_CONFIG[options?.sort ?? 'featured']
      // In-stock first, then requested sort — better hub browsing.
      let { data, error } = await built
        .order('in_stock', { ascending: false })
        .order(sort.column, { ascending: sort.ascending })

      if (error && /brand|dietary_tags|column/i.test(error.message)) {
        let legacy = supabase.from('products').select(STOREFRONT_PRODUCT_SELECT_LEGACY)
        if (q) {
          const terms = expandSearchTerms(q).filter((t) => t.trim().length > 0).slice(0, 6)
          const orFilter = terms
            .flatMap((t) => [
              `name.ilike.%${t}%`,
              `category.ilike.%${t}%`,
              `description.ilike.%${t}%`,
            ])
            .join(',')
          legacy = legacy.or(orFilter)
        }
        if (options?.category) legacy = legacy.eq('category', options.category)
        else if (options?.categories?.length) {
          legacy = legacy.in('category', [...options.categories])
        }
        if (options?.minPrice != null && !Number.isNaN(options.minPrice)) {
          legacy = legacy.gte('price', options.minPrice)
        }
        if (options?.maxPrice != null && !Number.isNaN(options.maxPrice)) {
          legacy = legacy.lte('price', options.maxPrice)
        }
        if (options?.inStockOnly) legacy = legacy.eq('in_stock', true)
        const legacyRes = await legacy
          .order('in_stock', { ascending: false })
          .order(sort.column, { ascending: sort.ascending })
        data = legacyRes.data as typeof data
        error = legacyRes.error
      }

      if (error) {
        return {
          products: [],
          errorMessage: formatCatalogError(error, true),
          configured: true,
        }
      }
      products = (data ?? []) as Product[]
    } else {
      // Apply non-search filters client-side after fuzzy RPC.
      if (options?.category) {
        products = products.filter((p) => p.category === options.category)
      } else if (options?.categories?.length) {
        const allowed = new Set(options.categories)
        products = products.filter((p) => allowed.has(p.category))
      }
      if (options?.brand?.trim()) {
        const b = options.brand.trim().toLowerCase()
        products = products.filter((p) => (p.brand ?? '').toLowerCase() === b)
      }
      if (options?.dietary?.trim()) {
        const tag = options.dietary.trim()
        products = products.filter((p) => (p.dietary_tags ?? []).includes(tag))
      }
      if (options?.minPrice != null && !Number.isNaN(options.minPrice)) {
        products = products.filter((p) => p.price >= options.minPrice!)
      }
      if (options?.maxPrice != null && !Number.isNaN(options.maxPrice)) {
        products = products.filter((p) => p.price <= options.maxPrice!)
      }
      if (options?.inStockOnly) {
        products = products.filter((p) => p.in_stock)
      }
      const sort = options?.sort ?? 'featured'
      products = [...products].sort((a, b) => {
        if (a.in_stock !== b.in_stock) return a.in_stock ? -1 : 1
        if (sort === 'price-asc') return a.price - b.price
        if (sort === 'price-desc') return b.price - a.price
        if (sort === 'name-asc') return a.name.localeCompare(b.name)
        return new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
      })
    }

    return {
      products: filterStorefrontProducts(products),
      errorMessage: null,
      configured: true,
    }
  } catch (e) {
    const err = e instanceof SupabaseConfigError ? null : e
    const message =
      e instanceof SupabaseConfigError
        ? formatCatalogError(null, false)
        : formatCatalogError(err instanceof Error ? err : { message: String(e) }, configured)
    return {
      products: [],
      errorMessage: message,
      configured,
    }
  }
}

export async function fetchDistinctBrands(options?: {
  categories?: readonly string[]
}): Promise<string[]> {
  const { configured } = getSupabasePublicConfig()
  if (!configured) return []
  try {
    const supabase = await createClientOptional()
    if (!supabase) return []
    let built = supabase
      .from('products')
      .select('brand')
      .not('brand', 'is', null)
      .eq('in_stock', true)
    if (options?.categories?.length) {
      built = built.in('category', [...options.categories])
    }
    const { data, error } = await built
    if (error) return []
    const set = new Set<string>()
    for (const row of data ?? []) {
      const b = typeof row.brand === 'string' ? row.brand.trim() : ''
      if (b) set.add(b)
    }
    return [...set].sort((a, b) => a.localeCompare(b))
  } catch {
    return []
  }
}

export async function fetchCategoryCounts(): Promise<Record<string, number>> {
  const { configured } = getSupabasePublicConfig()
  if (!configured) return {}

  try {
    const supabase = await createClientOptional()
    if (!supabase) return {}
    const { data } = await supabase.from('products').select('category,name').eq('in_stock', true)
    return ((data ?? []) as { category: string | null; name: string | null }[])
      .filter((row) => !isHiddenFromStorefront(row))
      .reduce<Record<string, number>>((acc, row) => {
        const name = row.category?.trim()
        if (!name) return acc
        acc[name] = (acc[name] ?? 0) + 1
        return acc
      }, {})
  } catch {
    return {}
  }
}

// Synonym map for African & Caribbean grocery search
// If someone types the left term, we also search the right terms
const SEARCH_SYNONYMS: Record<string, string[]> = {
  'fufu': ['fufuf', 'cassava', 'cocoyam'],
  'garri': ['gari', 'cassava'],
  'gari': ['garri', 'cassava'],
  'palm oil': ['zomi', 'red palm'],
  'zomi': ['palm oil', 'red palm'],
  'stockfish': ['stock fish', 'dried fish', 'okporoko'],
  'stock fish': ['stockfish', 'dried fish'],
  'egusi': ['melon seed', 'agushi'],
  'crayfish': ['dried shrimp', 'ground crayfish'],
  'plantain': ['dodo', 'boli'],
  'ogbono': ['draw soup', 'apon'],
  'groundnut': ['peanut', 'groundnut oil'],
  'peanut': ['groundnut'],
  'malt': ['malta', 'maltina', 'supermalt'],
  'malta': ['malt', 'maltina'],
  'suya': ['suya spice', 'yaji'],
  'jollof': ['jollof rice', 'benachin'],
  'pepper soup': ['peppersoup', 'pepper soup spice'],
  'eba': ['cassava', 'garri'],
  'amala': ['yam flour', 'poundo'],
  'pounded yam': ['poundo', 'pound yam', 'iyan'],
  'poundo': ['pounded yam', 'pound yam'],
  'ofe': ['soup', 'stew'],
  'bitters': ['alomo', 'orijin', 'adonko'],
  'semovita': ['semo', 'semolina'],
  'konkonte': ['cassava flour', 'abolo'],
  'banku': ['banku mix', 'corn dough'],
  'shea butter': ['nkuto', 'ori', 'shea'],
  'black soap': ['alata soap', 'dudu osun'],
  // Fashion / fabric / hair
  ankara: ['wax', 'wax print', 'hollandais', 'african print'],
  wax: ['ankara', 'wax print', 'hollandais', 'african print'],
  'african print': ['ankara', 'wax', 'wax print', 'hollandais'],
  lace: ['cord lace', 'guipure', 'net lace'],
  kente: ['woven', 'aso oke'],
  brocade: ['bazin', 'voile', 'damask'],
  bazin: ['brocade', 'voile'],
  headtie: ['gele', 'headwrap', 'head tie'],
  gele: ['headtie', 'headwrap', 'head tie'],
  dashiki: ['ready-to-wear', 'shirt'],
  fabric: ['wax', 'lace', 'yard', 'ankara'],
  wig: ['hair', 'braiding', 'closure'],
  braid: ['braiding', 'hair', 'extension'],
  braiding: ['braid', 'hair', 'extension'],
}

function expandSearchTerms(term: string): string[] {
  const lower = term.toLowerCase()
  const terms = new Set([lower])
  // Check if any synonym key is in the search term
  for (const [key, synonyms] of Object.entries(SEARCH_SYNONYMS)) {
    if (lower.includes(key)) {
      synonyms.forEach((s) => terms.add(s))
    }
    // Also check if search term matches a synonym value
    if (synonyms.some((s) => lower.includes(s))) {
      terms.add(key)
    }
  }
  return [...terms]
}

export async function searchProductsLite(
  q: string,
  limit = 6,
  options?: { categories?: readonly string[] }
): Promise<Product[]> {
  const term = q.trim()
  if (!term) return []
  const { configured } = getSupabasePublicConfig()
  if (!configured) return []
  try {
    const supabase = await createClientOptional()
    if (!supabase) return []

    const categories = options?.categories
    const scoped = Boolean(categories?.length)

    if (!scoped) {
      const { data: fuzzy } = await supabase.rpc('search_products_fuzzy', {
        search_query: term,
        result_limit: limit * 3,
      })
      if (Array.isArray(fuzzy) && fuzzy.length > 0) {
        return filterStorefrontProducts(fuzzy as Product[]).slice(0, limit)
      }
    }

    // Expand search with synonyms
    const terms = expandSearchTerms(term)

    // Build OR filter across name, category, and description (synonym-expanded).
    const cleanTerms = terms.filter((t) => t.trim().length > 0).slice(0, 6)
    const orFilter = cleanTerms
      .flatMap((t) => [
        `name.ilike.%${t}%`,
        `category.ilike.%${t}%`,
        `description.ilike.%${t}%`,
      ])
      .join(',')

    let built = supabase
      .from('products')
      .select('id,name,price,image_url,category,in_stock,description')
      .or(orFilter)
    if (categories?.length) built = built.in('category', [...categories])

    const { data } = await built
      .order('in_stock', { ascending: false })
      .limit(scoped ? limit : limit * 2)

    // Sort: exact name matches first, then category hits, then in-stock
    const needle = term.toLowerCase()
    const sorted = ((data ?? []) as Product[]).sort((a, b) => {
      const score = (p: Product) => {
        const name = p.name.toLowerCase()
        const cat = (p.category ?? '').toLowerCase()
        if (name === needle) return 3
        if (name.includes(needle)) return 2
        if (cat.includes(needle)) return 1
        return 0
      }
      const diff = score(b) - score(a)
      if (diff !== 0) return diff
      if (b.in_stock !== a.in_stock) return b.in_stock ? 1 : -1
      return 0
    })

    return filterStorefrontProducts(sorted).slice(0, limit)
  } catch {
    return []
  }
}

export async function fetchFashionProducts(limit = 8): Promise<Product[]> {
  const { products } = await fetchProductsForShop({
    categories: fashionQueryCategories(),
    inStockOnly: true,
    sort: 'newest',
  })
  return products.slice(0, limit)
}

export async function fetchHomepageProducts(): Promise<{
  staples: Product[]
  trending: Product[]
  newArrivals: Product[]
  categoryCount: Record<string, number>
  inStockCount: number
  configured: boolean
  errorMessage: string | null
}> {
  const empty = {
    staples: [] as Product[],
    trending: [] as Product[],
    newArrivals: [] as Product[],
    categoryCount: {} as Record<string, number>,
    inStockCount: 0,
  }

  const { configured } = getSupabasePublicConfig()
  if (!configured) {
    return {
      ...empty,
      configured: false,
      errorMessage: formatCatalogError(null, false),
    }
  }

  try {
    const supabase = await createClientOptional()
    if (!supabase) {
      return {
        ...empty,
        configured: false,
        errorMessage: formatCatalogError(null, false),
      }
    }
    const [showcase, catRes] = await Promise.all([
      fetchCuratedHomepageShowcase(supabase),
      supabase.from('products').select('category,name').eq('in_stock', true),
    ])

    if (catRes.error) {
      return {
        ...empty,
        configured: true,
        errorMessage: formatCatalogError(catRes.error, true),
      }
    }

    const categoryCount = ((catRes.data ?? []) as { category: string | null; name: string | null }[])
      .filter((row) => !isHiddenFromStorefront(row))
      .reduce<Record<string, number>>((acc, row) => {
      const name = row.category?.trim()
      if (!name) return acc
      acc[name] = (acc[name] ?? 0) + 1
      return acc
    }, {})

    const inStockCount = Object.values(categoryCount).reduce((sum, n) => sum + n, 0)

    return {
      staples: showcase.staples,
      trending: showcase.trending,
      newArrivals: showcase.newArrivals,
      categoryCount,
      inStockCount,
      configured: true,
      errorMessage: null,
    }
  } catch (e) {
    return {
      ...empty,
      configured: configured,
      errorMessage: formatCatalogError(e instanceof Error ? e : { message: String(e) }, configured),
    }
  }
}
