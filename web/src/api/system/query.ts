import { getEnvelope } from '#ui/api/client';

import { SYSTEM_PATH } from './path';
import type { DashboardData } from './types';

export async function getDashboard(): Promise<DashboardData> {
  return getEnvelope<DashboardData>(SYSTEM_PATH.dashboard);
}
