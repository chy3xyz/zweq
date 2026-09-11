import { getEnvelope } from '#ui/api/client';

import { auditListQuery, type AuditQuery } from './path';
import type { AuditListResult } from './types';

export async function listAuditLogs(page: number, pageSize: number, q: AuditQuery = {}): Promise<AuditListResult> {
  return getEnvelope<AuditListResult>(auditListQuery(page, pageSize, q));
}
