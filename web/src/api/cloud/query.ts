import { getEnvelope, postEnvelope } from '#ui/api/client';

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

export async function generateLicense(body: GenerateLicenseRequest): Promise<LicenseItem> {
  return postEnvelope<LicenseItem>(CLOUD_PATH.licenses, body);
}

export async function listLicenses(page: number, pageSize: number): Promise<LicenseListResult> {
  return getEnvelope<LicenseListResult>(licenseListQuery(page, pageSize));
}

export async function revokeLicense(id: number): Promise<void> {
  await postEnvelope<null>(licenseRevoke(id));
}

export async function verifyLicense(body: VerifyLicenseRequest): Promise<VerifyLicenseResult> {
  return postEnvelope<VerifyLicenseResult>(CLOUD_PATH.verify, body);
}

export async function listMarket(page: number, pageSize: number): Promise<MarketListResult> {
  return getEnvelope<MarketListResult>(marketListQuery(page, pageSize));
}

export async function publishPackage(body: PublishPackageRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(CLOUD_PATH.market, body);
}

export async function installPackage(name: string, body: InstallPackageRequest): Promise<{ module_id: number }> {
  return postEnvelope<{ module_id: number }>(marketInstall(name), body);
}

export type { LicenseItem, MarketItem };
