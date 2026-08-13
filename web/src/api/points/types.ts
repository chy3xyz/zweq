export interface PointsProduct {
  id: number;
  name: string;
  points: number;
  stock: number;
  created_at: number;
}

export interface PointsProductListResult {
  list: PointsProduct[];
  total: number;
  page: number;
  pageSize: number;
}

export interface PointsOrder {
  id: number;
  openid: string;
  product_name: string;
  points: number;
  created_at: number;
}

export interface CreateProductRequest {
  name: string;
  points: number;
  stock: number;
}

export interface UpdateProductRequest {
  name: string;
  points: number;
  stock: number;
}

export interface RedeemRequest {
  openid: string;
  product_id: number;
}

export interface AdjustRequest {
  openid: string;
  delta: number;
}
