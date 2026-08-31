/**
 * Parse a numeric query param coming from a search bar.
 *
 * Empty/absent values must fall back rather than coerce: `Number('')` is `0`,
 * which would silently turn "no status filter" into "status = 0".
 */
export function intParam(value: string | undefined | null, fallback: number): number {
  if (value == null || value === '') return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}
