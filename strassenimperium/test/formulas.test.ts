import test from "node:test";
import assert from "node:assert/strict";
import {
  attackRange,
  collectYield,
  fightScores,
  kursCentsFor,
  lootAmount,
  trainingCost,
  trainingDurationMinutes,
} from "../src/game/formulas.js";
import { GAME } from "../src/config.js";
import { openDb } from "../src/db.js";
import { addMoney, capacityFor } from "../src/game/money.js";

test("Tageskurs: deterministisch, in den Grenzen, variiert über Tage", () => {
  const seen = new Set<number>();
  for (let i = 0; i < 60; i++) {
    const d = new Date(Date.UTC(2026, 0, 1 + i));
    const a = kursCentsFor(d);
    const b = kursCentsFor(new Date(d));
    assert.equal(a, b, "gleicher Tag muss gleichen Kurs liefern");
    assert.ok(a >= GAME.KURS_MIN && a < GAME.KURS_MIN + GAME.KURS_SPAN);
    seen.add(a);
  }
  assert.ok(seen.size >= 2, "Kurs sollte über 60 Tage variieren");
});

test("Sammelertrag: steigt mit Dauer und Geschick, Effizienz sinkt pro Minute", () => {
  const durations = GAME.COLLECT_MINUTES;
  for (let i = 1; i < durations.length; i++) {
    const prev = collectYield(durations[i - 1], 0);
    const cur = collectYield(durations[i], 0);
    assert.ok(cur > prev, `${durations[i]} Min. muss mehr bringen als ${durations[i - 1]} Min.`);
    const prevRate = prev / durations[i - 1];
    const curRate = cur / durations[i];
    assert.ok(curRate < prevRate, "Ertrag pro Minute muss mit der Dauer sinken");
  }
  assert.ok(collectYield(60, 10) > collectYield(60, 0), "Geschick erhöht den Ertrag");
  assert.ok(collectYield(10, 0) >= 1, "Minimum 1 Flasche");
});

test("Weiterbildung: Kosten und Dauer wachsen strikt pro Stufe", () => {
  for (let level = 2; level <= 25; level++) {
    assert.ok(trainingCost(level) > trainingCost(level - 1));
    assert.ok(trainingDurationMinutes(level) >= trainingDurationMinutes(level - 1));
  }
  assert.equal(trainingCost(1), GAME.TRAINING_BASE_COST);
});

test("Angriffs-Spanne: eigene Punkte liegen immer in der eigenen Spanne", () => {
  for (const p of [0, 1, 50, 1000, 123456]) {
    const r = attackRange(p);
    assert.ok(r.min <= p && p <= r.max);
    assert.ok(r.min >= 0);
  }
});

test("Kampfformel: klar Stärkerer gewinnt immer, Gleichstand ist ausgeglichen", () => {
  for (let i = 0; i < 500; i++) {
    assert.equal(fightScores(50, 5).outcome, "win");
    assert.equal(fightScores(5, 50).outcome, "loss");
  }
  let win = 0;
  let loss = 0;
  for (let i = 0; i < 4000; i++) {
    const o = fightScores(10, 10).outcome;
    if (o === "win") win++;
    else if (o === "loss") loss++;
  }
  assert.ok(win > 0 && loss > 0, "bei Gleichstand müssen beide Ausgänge vorkommen");
  const rate = win / (win + loss);
  assert.ok(rate > 0.4 && rate < 0.6, `Gewinnquote bei Gleichstand war ${rate}`);
});

test("Beute: begrenzt durch Beutefaktor, steigt mit ATT, sinkt mit DEF", () => {
  const money = 10_000;
  for (const att of [0, 5, 20]) {
    for (const def of [0, 5, 20]) {
      const loot = lootAmount(money, att, def);
      assert.ok(loot >= 0 && loot <= money * GAME.FIGHT_LOOT_FACTOR);
    }
  }
  assert.ok(lootAmount(money, 20, 5) > lootAmount(money, 2, 5));
  assert.ok(lootAmount(money, 5, 20) < lootAmount(money, 5, 2));
});

test("Geld-Kapazität: Überlauf geht verloren (Kap. 3)", () => {
  const db = openDb(":memory:");
  db.prepare(
    "INSERT INTO users (username, email, password_hash, created_at, money) VALUES ('cap_test', 'cap@example.com', 'x', 0, ?)",
  ).run(GAME.BASE_CAPACITY - 100);
  const userId = Number(
    (db.prepare("SELECT id FROM users WHERE username = 'cap_test'").get() as any).id,
  );
  assert.equal(capacityFor(db, userId), GAME.BASE_CAPACITY);
  const result = addMoney(db, userId, 250);
  assert.equal(result.added, 100);
  assert.equal(result.lost, 150);
  assert.equal(result.newBalance, GAME.BASE_CAPACITY);
  db.close();
});
