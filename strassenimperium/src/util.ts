/** Cent-Betrag als deutschen Euro-String formatieren. */
export function fmtMoney(cents: number): string {
  return (cents / 100).toLocaleString("de-DE", {
    style: "currency",
    currency: "EUR",
  });
}

/** Dauer (ms) menschenlesbar, z. B. „2 Std. 30 Min.". */
export function fmtDuration(ms: number): string {
  const totalSec = Math.max(0, Math.round(ms / 1000));
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  const parts: string[] = [];
  if (h > 0) parts.push(`${h} Std.`);
  if (m > 0) parts.push(`${m} Min.`);
  if (h === 0 && (s > 0 || parts.length === 0)) parts.push(`${s} Sek.`);
  return parts.join(" ");
}

/** Zeitstempel als deutsches Datum mit Uhrzeit. */
export function fmtDateTime(ts: number): string {
  return new Date(ts).toLocaleString("de-DE", {
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function parsePositiveInt(v: unknown): number | null {
  const n = Number(v);
  if (!Number.isInteger(n) || n <= 0) return null;
  return n;
}
