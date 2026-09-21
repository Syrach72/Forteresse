import test from "node:test";
import assert from "node:assert/strict";
import { initialGame, transact, materialQuantity } from "../src/game.js";
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
  assert.equal(materialQuantity(r.inventory, "metal"), 15);
  assert.equal(materialQuantity(r.inventory, "leather"), 10);
  assert.equal(materialQuantity(r.inventory, "wood"), 10);
  assert.equal(r.gold, 905);
  assert.match(
    transact(r, { type: "craft", id: "maille" }).error,
    /Ressources/,
  );
  assert.equal(r.inventory.find((i) => i.id === "maille").quantity, 1);
});
test("l'arsenal de départ ne contient plus de Potion de soin", () => {
  assert.ok(!initialGame().inventory.some((i) => i.id === "potion"));
});
test("potions : consommation sans modifier les caractéristiques", () => {
  const s = initialGame();
  s.inventory.unshift({ id: "potion", quantity: 1, equipped: false });
  const r = transact(s, { type: "use", id: "potion" }).state;
  assert.equal(r.health, 2);
  assert.ok(!r.inventory.some((i) => i.id === "potion"));
  const full = initialGame();
  full.inventory.unshift({ id: "potion", quantity: 1, equipped: false });
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
  firstFreeBed,
} from "../src/dormitory.js";
import { INITIAL_TRAINING } from "../src/training-data.js";
import {
  INITIAL_TREASURY,
  changeTreasury,
  treasuryTotal,
} from "../src/treasury-data.js";
test("le dortoir, l'infirmerie et l'entraînement démarrent vides (les mercenaires viennent du recrutement)", () => {
  assert.ok(INITIAL_DORMITORY.beds.every((b) => b === null));
  assert.equal(INITIAL_TRAINING.instructor, null);
  assert.ok(INITIAL_TRAINING.students.every((x) => x === null));
});
test("recrutement : premier lit libre et débloqué ; aucun lit si tous sont pris ou verrouillés", () => {
  const dormitory = structuredClone(INITIAL_DORMITORY);
  assert.equal(firstFreeBed(dormitory), 0);
  dormitory.beds[0] = { heroId: "a", remaining: 0 };
  dormitory.beds[2] = { heroId: "b", remaining: 0 };
  assert.equal(firstFreeBed(dormitory), 1);
  for (let i = 0; i < dormitory.capacity; i++)
    dormitory.beds[i] = { heroId: `h${i}`, remaining: 0 };
  // Les lits au-delà de la capacité restent vides mais verrouillés.
  assert.equal(dormitory.beds[dormitory.capacity], null);
  assert.equal(firstFreeBed(dormitory), -1);
  dormitory.capacity += 1;
  assert.equal(firstFreeBed(dormitory), dormitory.capacity - 1);
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
