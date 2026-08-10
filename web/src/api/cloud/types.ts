export type LicenseStatus = 'active' | 'expired' | 'revoked';

export interface LicenseItem {
  id: number;
  license_key: string;
  status: LicenseStatus;
  expires_at: number;
  created_at: number;
}

export interface LicenseListResult {
  list: LicenseItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface MarketItem {
  id: number;
  name: string;
  title: string;
  version: string;
  description: string;
  download_url: string;
  updated_at: number;
}

export interface MarketListResult {
  list: MarketItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface GenerateLicenseRequest {
  days: number;
}

export interface VerifyLicenseRequest {
  key: string;
}

export interface VerifyLicenseResult {
  valid: boolean;
  reason: string;
}

export interface PublishPackageRequest {
  name: string;
  title: string;
  version: string;
  description: string;
  download_url: string;
}

export interface InstallPackageRequest {
  account_id: number;
}
