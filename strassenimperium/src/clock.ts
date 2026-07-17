/**
 * Zentrale Server-Uhr. Alle Timer/Belohnungen werden ausschließlich
 * serverseitig über diese Uhr berechnet — der Client-Uhr wird nie vertraut
 * (Lastenheft Kap. 16, „Kritisch").
 */
let offsetMs = 0;

export function now(): number {
  return Date.now() + offsetMs;
}

/** Nur für Tests: Uhr künstlich verschieben. */
export function __setClockOffsetForTests(ms: number): void {
  offsetMs = ms;
}
