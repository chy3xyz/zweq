import { httpGet } from '@/http/http'
import { DEFAULT_ACCOUNT_ID } from '@/utils/env'

export interface IPaged<T> {
  list: T[]
  total: number
  page: number
  pageSize: number
}

export interface ICategory {
  id: number
  account_id: number
  name: string
  parent_id: number
  sort: number
}

export interface IProduct {
  id: number
  account_id: number
  category_id: number
  name: string
  image: string
  images: string | null
  content: string
  price: number
  original_price: number
  stock: number
  sales: number
  status: number
  created_at: number
}

export interface ISku {
  id: number
  product_id: number
  spec_json: string
  image: string
  price: number
  stock: number
}

export interface IProductDetail {
  product: IProduct
  skus: ISku[]
}

export function listCategories(accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<ICategory[] | null>('/api/v1/shop/categories', { account_id: accountId })
    .then(list => list ?? [])
}

export function listProducts(
  categoryId: number,
  page: number,
  pageSize: number,
  keyword = '',
  accountId: number = DEFAULT_ACCOUNT_ID,
) {
  const query: Record<string, string | number> = { account_id: accountId, page, page_size: pageSize }
  if (categoryId > 0)
    query.category_id = categoryId
  if (keyword !== '')
    query.keyword = keyword
  return httpGet<IPaged<IProduct>>('/api/v1/shop/products', query)
}

export function getProductDetail(id: number) {
  return httpGet<IProductDetail>(`/api/v1/shop/products/${id}`)
}
