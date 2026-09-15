import test from "node:test";
import assert from "node:assert/strict";
import { initialGame, transact } from "../src/game.js";
test("achat : débit, stock et inventaire cohérents sans modifier la source", () => {
  const s = initialGame();
  const r = transact(s, { type: "buy", id: "maille" }).state;
  assert.equal(r.gold, 725);
  assert.equal(r.stock.maille, 2);
  assert.equal(r.inventory.find((i) => i.id === "maille").quantity, 1);
  assert.equal(s.gold, 905);
  assert.equal(r.log[0].amount, -180);
});
test("stock épuisé et solde insuffisant : aucune mutation", () => {
  const s = initialGame();
  s.gold = 0;
  const snapshot = JSON.stringify(s);
  assert.match(transact(s, { type: "buy", id: "epee" }).error, /pièces/);
  assert.equal(JSON.stringify(s), snapshot);
  s.gold = 905;
  s.stock.epee = 0;
  assert.match(transact(s, { type: "buy", id: "epee" }).error, /épuisé/);
});
test("fabrication consomme toutes les ressources, puis refuse la répétition impossible", () => {
  const s = initialGame();
  const r = transact(s, { type: "craft", id: "maille" }).state;
  assert.deepEqual(r.resources, { metal: 15, leather: 10, wood: 10 });
  assert.equal(r.gold, 905);
  assert.match(
    transact(r, { type: "craft", id: "maille" }).error,
    /Ressources/,
  );
  assert.equal(r.inventory.find((i) => i.id === "maille").quantity, 1);
});
test("potions : consommation sans modifier les caractéristiques", () => {
  const s = initialGame();
  s.inventory[0].quantity = 1;
  const r = transact(s, { type: "use", id: "potion" }).state;
  assert.equal(r.health, 2);
  assert.equal(r.inventory.length, 0);
  const full = initialGame();
  full.health = 3;
  assert.equal(transact(full, { type: "use", id: "potion" }).state.health, 3);
});
test("équiper puis ranger un objet possédé", () => {
  const bought = transact(initialGame(), { type: "buy", id: "epee" }).state;
  const eq = transact(bought, { type: "equip", id: "epee" }).state;
  assert.equal(eq.inventory.find((i) => i.id === "epee").equipped, true);
  assert.equal(
    transact(eq, { type: "equip", id: "epee" }).state.inventory.find(
      (i) => i.id === "epee",
    ).equipped,
    false,
  );
});
import {
  INITIAL_DORMITORY,
  updateDormitory,
  stepDurations,
} from "../src/dormitory.js";
import { INITIAL_TRAINING, stepTraining } from "../src/training-data.js";
import {
  INITIAL_TREASURY,
  changeTreasury,
  treasuryTotal,
} from "../src/treasury-data.js";
test("durées : bornes 0–5, incrément global, aucune sortie automatique", () => {
  const area = structuredClone(INITIAL_DORMITORY);
  area.beds[0].remaining = 5;
  const next = stepDurations(area, 1);
  assert.equal(next.beds[0].remaining, 5);
  assert.equal(next.beds[0].heroId, area.beds[0].heroId);
  assert.equal(stepDurations(area, -10).beds[0].remaining, 0);
  assert.match(
    updateDormitory(area, { type: "duration", slot: 0, remaining: 6 }).error,
    /0 à 5/,
  );
  assert.equal(stepTraining(INITIAL_TRAINING).instructor.remaining, 3);
});
test("repos : pas de doublon ni de placement sur un lit verrouillé", () => {
  assert.match(
    updateDormitory(INITIAL_DORMITORY, {
      type: "place",
      slot: 1,
      heroId: "tavoul",
      remaining: 2,
    }).error,
    /déjà/,
  );
  assert.match(
    updateDormitory(INITIAL_DORMITORY, {
      type: "place",
      slot: 10,
      heroId: "orik",
      remaining: 2,
    }).error,
    /débloqué/,
  );
});
test("trésorerie : édition du budget sans annuler les achats déjà faits", () => {
  assert.equal(treasuryTotal(INITIAL_TREASURY), 2095);
  const r = changeTreasury(INITIAL_TREASURY, { id: "entretien", amount: 200 });
  assert.equal(r.delta, -50);
  assert.equal(805 + r.delta, 755);
  assert.equal(
    changeTreasury(INITIAL_TREASURY, { id: "income", amount: 4000 }).delta,
    1000,
  );
  assert.match(
    changeTreasury(INITIAL_TREASURY, { id: "income", amount: -1 }).error,
    /entier/,
  );
});
