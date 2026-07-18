import { SEASONAL_EVENTS, type SeasonalEventDef } from "../config.js";
import { now } from "../clock.js";

/**
 * Aktives Saison-Event für ein Datum (UTC). Zeitfenster sind inklusive und
 * dürfen über den Jahreswechsel gehen (z. B. 27.12.–02.01.).
 */
export function activeEvent(date: Date = new Date(now())): SeasonalEventDef | null {
  const mmdd = date.toISOString().slice(5, 10);
  for (const event of SEASONAL_EVENTS) {
    const inRange =
      event.from <= event.to
        ? mmdd >= event.from && mmdd <= event.to
        : mmdd >= event.from || mmdd <= event.to;
    if (inRange) return event;
  }
  return null;
}

export interface EventFactors {
  event: SeasonalEventDef | null;
  kurs: number;
  collect: number;
  donation: number;
}

export function eventFactors(date: Date = new Date(now())): EventFactors {
  const event = activeEvent(date);
  return {
    event,
    kurs: event?.kursFactor ?? 1,
    collect: event?.collectFactor ?? 1,
    donation: event?.donationFactor ?? 1,
  };
}
