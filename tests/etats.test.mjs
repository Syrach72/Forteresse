import test from "node:test";
import assert from "node:assert/strict";
import { basculerEtat, decouper, definirNiveau, definirRounds, listeEtats } from "../src/etats.js";

test("liste : état principal puis supplémentaires dans l'ordre, trois au plus", () => {
  const l = listeEtats({ etat: "fascine", niveau: 1, rounds: 2 }, [
    { position: 2, etat: "epuise", niveau: 2, rounds: 0 },
    { position: 1, etat: "muet", niveau: 1, rounds: 4 },
    { position: 3, etat: "flou" },
  ]);
  assert.deepEqual(l.map((e) => e.etat), ["fascine", "muet", "epuise"]);
  assert.equal(listeEtats({ etat: null }, []).length, 0);
});

test("cliquer ajoute un état, recliquer le retire, sans effacer les autres", () => {
  let l = basculerEtat([], "fascine").liste;
  l = basculerEtat(l, "epuise").liste;
  assert.deepEqual(l.map((e) => e.etat), ["fascine", "epuise"]);
  l = basculerEtat(l, "fascine").liste;
  assert.deepEqual(l.map((e) => e.etat), ["epuise"]);
});

test("trois états au maximum", () => {
  let l = [];
  for (const id of ["fascine", "epuise", "muet"]) l = basculerEtat(l, id).liste;
  const r = basculerEtat(l, "flou");
  assert.match(r.erreur, /Trois états/);
  assert.equal(r.liste, undefined);
});

test("l'Inconscient devient l'état principal", () => {
  let l = basculerEtat([], "fascine").liste;
  l = basculerEtat(l, "inconscient").liste;
  assert.deepEqual(l.map((e) => e.etat), ["inconscient", "fascine"]);
  assert.deepEqual(decouper(l).principal.etat, "inconscient");
  assert.equal(decouper(l).supplementaires.length, 1);
});

test("niveau et rounds se règlent état par état", () => {
  let l = basculerEtat(basculerEtat([], "epuise").liste, "muet").liste;
  l = definirNiveau(definirRounds(l, "muet", 3), "epuise", 2);
  assert.deepEqual(l, [
    { etat: "epuise", niveau: 2, rounds: 0 },
    { etat: "muet", niveau: 1, rounds: 3 },
  ]);
});
