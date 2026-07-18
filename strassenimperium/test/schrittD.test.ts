import test from "node:test";
import assert from "node:assert/strict";
import { activeEvent, eventFactors } from "../src/game/events.js";
import { SEASONAL_EVENTS } from "../src/config.js";
import { kursCentsFor } from "../src/game/formulas.js";
import { kursToday } from "../src/game/svc.js";
import { now } from "../src/clock.js";

test("Saison-Events: Zeitfenster inkl. Jahreswechsel, sonst keins", () => {
  const inJuly = activeEvent(new Date(Date.UTC(2026, 6, 15)));
  assert.equal(inJuly?.key, "pfandfestival", "Mitte Juli läuft das Pfandfestival");
  assert.equal(activeEvent(new Date(Date.UTC(2026, 6, 9))), null, "9. Juli: noch nichts");
  assert.equal(activeEvent(new Date(Date.UTC(2026, 2, 3))), null, "März: eventfrei");
  // Jahresübergreifendes Fenster 27.12.–02.01.
  assert.equal(activeEvent(new Date(Date.UTC(2026, 11, 29)))?.key, "silvester");
  assert.equal(activeEvent(new Date(Date.UTC(2027, 0, 1)))?.key, "silvester");
  assert.equal(activeEvent(new Date(Date.UTC(2027, 0, 3))), null);
});

test("Saison-Events: Faktoren fließen in den Tageskurs ein", () => {
  const date = new Date(now());
  const raw = kursCentsFor(date);
  const factors = eventFactors(date);
  assert.equal(kursToday(), Math.round(raw * factors.kurs));
  // Und die Definitionen selbst sind plausibel:
  for (const e of SEASONAL_EVENTS) {
    assert.match(e.from, /^\d{2}-\d{2}$/);
    assert.match(e.to, /^\d{2}-\d{2}$/);
    assert.ok(e.kursFactor >= 1 && e.collectFactor >= 1 && e.donationFactor >= 1);
  }
});
