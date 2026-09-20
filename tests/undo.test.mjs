import test from "node:test";
import assert from "node:assert/strict";
import { initialGame, transact, materialQuantity, undoLast } from "../src/game.js";

const dague = { id: "a1", nom: "Dague test", icone: null, racine: "Armes", cout_achat_or: 40 };

test("annulation d'un achat catalogue : or, arsenal et journal reviennent exactement à l'état d'avant", () => {
  const before = initialGame();
  const r = transact(before, { type: "buy-catalogue", arme: dague });
  const stack = [{ kind: "buy", before, after: r.state, message: r.message }];
  const undone = undoLast(stack, r.state);
  assert.equal(undone.kind, "buy");
  assert.equal(undone.state, before);
  assert.equal(undone.state.gold, 905);
  assert.ok(!undone.state.inventory.some((i) => i.id === "catalogue:a1"));
  assert.equal(undone.state.log.length, before.log.length);
  assert.deepEqual(undone.stack, []);
});

test("annulation d'une fabrication catalogue : ressources restituées et atelier libéré (fabrication en attente comme livrée tout de suite)", () => {
  const enAttente = {
    id: "b1",
    nom: "Arbalète",
    icone: null,
    racine: "Armes",
    duree_fabrication_instances: 2,
    ingredientsList: [{ nom: "Fer", quantite: 10 }],
  };
  const immediate = { ...enAttente, id: "b2", duree_fabrication_instances: null };
  for (const arme of [enAttente, immediate]) {
    const before = initialGame();
    const r = transact(before, { type: "craft-catalogue", arme, route: "forge" });
    assert.equal(materialQuantity(r.state.inventory, "metal"), 35);
    const undone = undoLast(
      [{ kind: "craft", before, after: r.state, message: r.message }],
      r.state,
    );
    assert.equal(materialQuantity(undone.state.inventory, "metal"), 45);
    assert.ok(!undone.state.craftingQueue.forge);
    assert.ok(!undone.state.inventory.some((i) => i.id === `catalogue:${arme.id}`));
    // L'atelier est de nouveau libre : la même fabrication peut être relancée.
    assert.ok(transact(undone.state, { type: "craft-catalogue", arme, route: "forge" }).state);
  }
});

test("annulation : plusieurs achats sur la même fiche s'annulent du dernier au premier ; refus si la situation a changé", () => {
  const s0 = initialGame();
  const r1 = transact(s0, { type: "buy-catalogue", arme: dague });
  const r2 = transact(r1.state, { type: "buy-catalogue", arme: dague });
  const stack = [
    { kind: "buy", before: s0, after: r1.state },
    { kind: "buy", before: r1.state, after: r2.state },
  ];
  // Autre changement entre-temps (ex. une vente) : on ne restaure pas un vieil
  // état par-dessus une situation qui a évolué.
  const modifie = transact(r2.state, { type: "sell", id: "catalogue:a1", quantity: 1 }).state;
  assert.match(undoLast(stack, modifie).error, /a changé/);
  const u1 = undoLast(stack, r2.state);
  assert.equal(u1.state.gold, 865);
  assert.equal(u1.state.inventory.find((i) => i.id === "catalogue:a1").quantity, 1);
  const u2 = undoLast(u1.stack, u1.state);
  assert.equal(u2.state.gold, 905);
  assert.ok(!u2.state.inventory.some((i) => i.id === "catalogue:a1"));
  assert.match(undoLast(u2.stack, u2.state).error, /Aucune opération/);
});
