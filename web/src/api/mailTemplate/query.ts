import { getEnvelope, putEnvelope } from '#ui/api/client';

import { mailTemplateDetail, mailTemplateListQuery } from './path';
import type { MailTemplateListResult } from './types';

export async function listMailTemplates(page: number, pageSize: number): Promise<MailTemplateListResult> {
  return getEnvelope<MailTemplateListResult>(
    mailTemplateListQuery(page, pageSize),
  );
}

export async function upsertMailTemplate(code: string, subject: string, body: string): Promise<void> {
  await putEnvelope<null>(mailTemplateDetail(code), { subject, body });
}
