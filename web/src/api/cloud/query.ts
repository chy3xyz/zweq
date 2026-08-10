import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { CLOUD_PATH, licenseListQuery, licenseRevoke, marketInstall, marketListQuery } from './path';
import type {
  GenerateLicenseRequest,
  InstallPackageRequest,
  LicenseItem,
  LicenseListResult,
  MarketItem,
  MarketListResult,
  PublishPackageRequest,
  VerifyLicenseRequest,
  VerifyLicenseResult,
} from './types';

async function getEnvelope<T>(path: string): Promise<T> {
  const { data } = await http.get<{ code: number; msg: string; data: T }>(path);
  return unwrapEnvelope(data);
}

export async function generateLicense(body: GenerateLicenseRequest): Promise<LicenseItem> {
  const { data } = await http.post<{ code: number; msg: string; data: LicenseItem }>(CLOUD_PATH.licenses, body);
  return unwrapEnvelope(data);
}

export async function listLicenses(page: number, pageSize: number): Promise<LicenseListResult> {
  return getEnvelope<LicenseListResult>(licenseListQuery(page, pageSize));
}

export async function revokeLicense(id: number): Promise<void> {
  const { data } = await http.post<{ code: number; msg: string; data: null }>(licenseRevoke(id));
  unwrapEnvelope(data);
}

export async function verifyLicense(body: VerifyLicenseRequest): Promise<VerifyLicenseResult> {
  const { data } = await http.post<{ code: number; msg: string; data: VerifyLicenseResult }>(CLOUD_PATH.verify, body);
  return unwrapEnvelope(data);
}

export async function listMarket(page: number, pageSize: number): Promise<MarketListResult> {
  return getEnvelope<MarketListResult>(marketListQuery(page, pageSize));
}

export async function publishPackage(body: PublishPackageRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(CLOUD_PATH.market, body);
  return unwrapEnvelope(data);
}

export async function installPackage(name: string, body: InstallPackageRequest): Promise<{ module_id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { module_id: number } }>(marketInstall(name), body);
  return unwrapEnvelope(data);
}

export type { LicenseItem, MarketItem };
