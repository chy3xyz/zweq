import { getEnvelope, http, postEnvelope } from '#ui/api/client';

import { TASK_PATH, taskCancel, taskDetail, taskListQuery, taskRetry } from './path';
import type { TaskItem, TaskListResult, TaskStats } from './types';

export async function listTasks(page: number, pageSize: number, status?: string): Promise<TaskListResult> {
  return getEnvelope<TaskListResult>(taskListQuery(page, pageSize, status));
}

export async function getTask(id: number): Promise<TaskItem> {
  return getEnvelope<TaskItem>(taskDetail(id));
}

export async function taskStats(): Promise<TaskStats> {
  return getEnvelope<TaskStats>(TASK_PATH.stats);
}

export async function retryTask(id: number): Promise<void> {
  await postEnvelope<null>(taskRetry(id));
}

export async function cancelTask(id: number): Promise<void> {
  await postEnvelope<null>(taskCancel(id));
}

export async function purgeTasks(): Promise<void> {
  await postEnvelope<null>(TASK_PATH.purge);
}

export async function deleteTask(id: number): Promise<void> {
  await http.delete(taskDetail(id));
}
