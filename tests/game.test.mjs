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
test("potions : consommation sans modifier les caractéristiques", () => {
  const s = initialGame();
  s.inventory[0].quantity = 1;
  const r = transact(s, { type: "use", id: "potion" }).state;
  assert.equal(r.health, 2);
  assert.ok(!r.inventory.some((i) => i.id === "potion"));
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
test("fabrication d'une arme du catalogue Supabase (Forge) : consomme les ressources nommées, ajoute au stock", () => {
  const arme = {
    id: "11111111-1111-1111-1111-111111111111",
    nom: "Épée longue",
    icone: "https://example.com/epee.png",
    ingredientsList: [
      { nom: "Fer", quantite: 10 },
      { nom: "Cuir", quantite: 5 },
      { nom: "Bois", quantite: 2 },
    ],
  };
  const r = transact(initialGame(), { type: "craft-catalogue", arme }).state;
  assert.equal(materialQuantity(r.inventory, "metal"), 35);
  assert.equal(materialQuantity(r.inventory, "leather"), 13);
  assert.equal(materialQuantity(r.inventory, "wood"), 38);
  const own = r.inventory.find((i) => i.id === "catalogue:11111111-1111-1111-1111-111111111111");
  assert.equal(own.quantity, 1);
  assert.equal(own.nom, "Épée longue");
  // Une deuxième fabrication incrémente la même ligne au lieu d'en créer une autre.
  const r2 = transact(r, { type: "craft-catalogue", arme }).state;
  assert.equal(
    r2.inventory.find((i) => i.id === "catalogue:11111111-1111-1111-1111-111111111111").quantity,
    2,
  );
  assert.equal(r2.inventory.length, r.inventory.length);
});
test("fabrication catalogue avec route et duree_fabrication_instances : mise en attente puis recuperation manuelle via collect-craft", () => {
  const arme = {
    id: "22222222-2222-2222-2222-222222222222",
    nom: "Arbalète légère",
    icone: "https://example.com/arbalete.png",
    racine: "Armes",
    duree_fabrication_instances: 2,
    ingredientsList: [{ nom: "Fer", quantite: 10 }],
  };
  const queued = transact(initialGame(), {
    type: "craft-catalogue",
    arme,
    route: "forge",
  }).state;
  assert.equal(materialQuantity(queued.inventory, "metal"), 35);
  assert.equal(queued.durations.forge, 2);
  assert.deepEqual(queued.craftingQueue.forge, {
    id: arme.id,
    nom: "Arbalète légère",
    icone: arme.icone,
    categorie: "Armes",
    cout: null,
  });
  assert.ok(!queued.inventory.some((i) => i.id === `catalogue:${arme.id}`));
  assert.match(
    transact(queued, { type: "craft-catalogue", arme, route: "forge" }).error,
    /déjà en cours/,
  );
  // Duree encore a 1 : la recuperation est refusee, rien n'est livre.
  const tooEarly = { ...queued, durations: { forge: 1 } };
  assert.match(
    transact(tooEarly, { type: "collect-craft", route: "forge" }).error,
    /n’est pas encore terminée/,
  );
  // Duree tombee a 0 : reste en attente tant qu'on ne clique pas
  // "Envoyer à l'Arsenal" (pas de livraison automatique).
  const ready = { ...queued, durations: { forge: 0 } };
  assert.ok(!ready.inventory.some((i) => i.id === `catalogue:${arme.id}`));
  const done = transact(ready, { type: "collect-craft", route: "forge" }).state;
  const delivered = done.inventory.find((i) => i.id === `catalogue:${arme.id}`);
  assert.equal(delivered.quantity, 1);
  assert.equal(delivered.categorie, "Armes");
  assert.equal(done.craftingQueue.forge, null);
  // La Duree d'instance de l'atelier est videe (repart sur la valeur par
  // defaut), pas laissee a 0.
  assert.ok(!("forge" in done.durations));
  // Une fois recupere, plus rien a recuperer dans cet atelier.
  assert.match(
    transact(done, { type: "collect-craft", route: "forge" }).error,
    /Aucune fabrication à récupérer/,
  );
});
test("un seul compteur par matériau : un objet du catalogue nommé Fer/Cuir/Bois remplace la démo locale, la fabrication le débite directement (pas de second compteur)", () => {
  const s = initialGame();
  // Simule la fusion au démarrage (App.jsx) : la ligne de démo locale
  // "material:metal" est remplacée par l'objet réel du catalogue admin.
  s.inventory = s.inventory.filter((i) => i.id !== "material:metal");
  s.inventory.push({
    id: "catalogue:fer-uuid",
    quantity: 100,
    equipped: false,
    nom: "Fer",
    categorie: "Matériaux",
  });
  const arme = {
    id: "33333333-3333-3333-3333-333333333333",
    nom: "Dague",
    ingredientsList: [{ nom: "Fer", quantite: 10 }],
  };
  const r = transact(s, { type: "craft-catalogue", arme }).state;
  assert.equal(r.inventory.find((i) => i.id === "catalogue:fer-uuid").quantity, 90);
  assert.equal(materialQuantity(r.inventory, "metal"), 90);
  assert.ok(!r.inventory.some((i) => i.id === "material:metal"));
});
test("fabrication catalogue : composant absent du stock ou insuffisant refuse sans muter l'état", () => {
  const s = initialGame();
  const snapshot = JSON.stringify(s);
  const inconnue = {
    id: "x",
    nom: "Amulette",
    ingredientsList: [{ nom: "Essence solaire", quantite: 1 }],
  };
  assert.match(
    transact(s, { type: "craft-catalogue", arme: inconnue }).error,
    /Ressources insuffisantes/,
  );
  const troploin = {
    id: "y",
    nom: "Masse gigantesque",
    ingredientsList: [{ nom: "Fer", quantite: 9999 }],
  };
  assert.match(
    transact(s, { type: "craft-catalogue", arme: troploin }).error,
    /Ressources insuffisantes/,
  );
  assert.equal(JSON.stringify(s), snapshot);
});
test("achat catalogue : le coût est décompté de la trésorerie, l'objet rejoint l'arsenal, refus sans mutation si coût absent ou solde insuffisant", () => {
  const s = initialGame();
  const gold = s.gold;
  const arme = { id: "a1", nom: "Dague test", icone: null, racine: "Armes", cout_achat_or: 40 };
  const r = transact(s, { type: "buy-catalogue", arme });
  assert.equal(r.state.gold, gold - 40);
  assert.equal(r.state.inventory.find((i) => i.id === "catalogue:a1").quantity, 1);
  assert.equal(r.state.inventory.find((i) => i.id === "catalogue:a1").categorie, "Armes");
  assert.equal(r.state.log[0].amount, -40);
  const r2 = transact(r.state, { type: "buy-catalogue", arme });
  assert.equal(r2.state.inventory.find((i) => i.id === "catalogue:a1").quantity, 2);
  assert.equal(r2.state.gold, gold - 80);
  const snapshot = JSON.stringify(s);
  assert.match(
    transact(s, { type: "buy-catalogue", arme: { ...arme, cout_achat_or: null } }).error,
    /pas encore défini/,
  );
  assert.match(
    transact(s, { type: "buy-catalogue", arme: { ...arme, cout_achat_or: gold + 1 } }).error,
    /pas assez de pièces/,
  );
  assert.equal(JSON.stringify(s), snapshot);
});
test("vente : moitié de la valeur créditée à la trésorerie, quantité retirée, refus sans valeur ou quantité invalide", () => {
  const s = initialGame();
  const gold = s.gold;
  const potions = s.inventory.find((i) => i.id === "potion");
  assert.ok(potions && potions.quantity >= 2);
  const before = potions.quantity;
  const r = transact(s, { type: "sell", id: "potion", quantity: 2 });
  assert.equal(r.state.gold, gold + 25); // 2 × 25 Po ÷ 2
  assert.equal(r.state.inventory.find((i) => i.id === "potion").quantity, before - 2);
  assert.equal(r.state.log[0].amount, 25);
  // objet du catalogue de valeur impaire : arrondi à l'entier inférieur
  s.inventory.push({ id: "catalogue:z", nom: "Bâton", quantity: 1, equipped: false, valeur: 5 });
  const r2 = transact(s, { type: "sell", id: "catalogue:z", quantity: 1 });
  assert.equal(r2.state.gold, gold + 2);
  assert.ok(!r2.state.inventory.some((i) => i.id === "catalogue:z"));
  // sans valeur, quantité invalide : refus sans muter l'état
  s.inventory.push({ id: "catalogue:n", nom: "Sans prix", quantity: 3, equipped: false, valeur: null });
  const snapshot = JSON.stringify(s);
  assert.match(transact(s, { type: "sell", id: "catalogue:n", quantity: 1 }).error, /valeur/);
  assert.match(transact(s, { type: "sell", id: "potion", quantity: before + 1 }).error, /Quantité invalide/);
  assert.match(transact(s, { type: "sell", id: "potion", quantity: 0 }).error, /Quantité invalide/);
  assert.equal(JSON.stringify(s), snapshot);
});
test("fabrication catalogue : un composant alchimique est débité par son nom dans l'inventaire", () => {
  const s = initialGame();
  s.inventory.push({ id: "catalogue:c1", nom: "Essence solaire", quantity: 3, equipped: false });
  const potion = {
    id: "p1",
    nom: "Potion de test",
    racine: "Produits Alchimiques",
    duree_fabrication_instances: 2,
    ingredientsList: [{ nom: "essence solaire", quantite: 2 }],
  };
  const r = transact(s, { type: "craft-catalogue", arme: potion, route: "alchimie" }).state;
  assert.equal(r.inventory.find((i) => i.id === "catalogue:c1").quantity, 1);
  assert.equal(r.craftingQueue.alchimie.nom, "Potion de test");
  assert.equal(r.durations.alchimie, 2);
  assert.match(
    transact(r, { type: "craft-catalogue", arme: potion, route: "alchimie" }).error,
    /déjà en cours/,
  );
});
test("fabrication en attente : ressources debitees tout de suite, objet livre seulement quand la duree d'instance atteint 0", () => {
  const s = initialGame();
  const queued = transact(s, {
    type: "craft-queue",
    id: "maille",
    route: "armurerie",
  }).state;
  assert.equal(materialQuantity(queued.inventory, "metal"), 15);
  assert.equal(materialQuantity(queued.inventory, "leather"), 10);
  assert.equal(materialQuantity(queued.inventory, "wood"), 10);
  assert.equal(queued.craftingQueue.armurerie, "maille");
  assert.ok(!queued.inventory.some((i) => i.id === "maille"));
  assert.match(
    transact(queued, {
      type: "craft-queue",
      id: "maille",
      route: "armurerie",
    }).error,
    /déjà en cours/,
  );
  // Duree encore a 3 (valeur par defaut de la demo) : la recuperation
  // manuelle est refusee tant que ce n'est pas termine.
  const tooEarly = { ...queued, durations: { armurerie: 3 } };
  assert.match(
    transact(tooEarly, { type: "collect-craft", route: "armurerie" }).error,
    /n’est pas encore terminée/,
  );
  // Duree tombee a 0 : reste en attente tant qu'on ne clique pas
  // "Envoyer à l'Arsenal" (pas de livraison automatique).
  const ready = { ...queued, durations: { armurerie: 0 } };
  assert.ok(!ready.inventory.some((i) => i.id === "maille"));
  const done = transact(ready, {
    type: "collect-craft",
    route: "armurerie",
  }).state;
  assert.equal(done.inventory.find((i) => i.id === "maille").quantity, 1);
  assert.equal(done.craftingQueue.armurerie, null);
  assert.ok(!("armurerie" in done.durations));
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
  assert.equal(stepTraining(INITIAL_TRAINING, 1).instructor.remaining, 3);
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
