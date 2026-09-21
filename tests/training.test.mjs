import test from "node:test";
import assert from "node:assert/strict";
import {
  INITIAL_TRAINING,
  VETERANCE_ECART,
  buildTraining,
  eligibleStudents,
  studentBlocker,
  trainingIds,
} from "../src/training-data.js";
const W = (id, role, veterancy) => ({ id, name: id, role, veterancy });
const maitre = W("maitre", "Guerrier", 6);
const mine = [
  W("novice", "Guerrier", 2),
  W("presque", "Guerrier", 4),
  W("egal", "Guerrier", 3),
  W("voleur", "Roublard", 1),
  W("autre", "Guerrier", 0),
];
const vide = () => structuredClone(INITIAL_TRAINING);
test("l'écart minimal de vétérance entre instructeur et élève est de 3", () => {
  assert.equal(VETERANCE_ECART, 3);
});
test("aucun élève sans instructeur", () => {
  assert.match(studentBlocker(null, mine[0]), /instructeur/);
  assert.deepEqual(eligibleStudents(mine, null, vide()), []);
});
test("élève : même classe et au moins 3 points de vétérance de moins", () => {
  assert.equal(studentBlocker(maitre, mine[0]), null); // 6 - 2 = 4
  assert.equal(studentBlocker(maitre, mine[2]), null); // 6 - 3 = 3, limite
  assert.match(studentBlocker(maitre, mine[1]), /3 points/); // 6 - 4 = 2
  assert.match(studentBlocker(maitre, mine[3]), /même classe/);
  assert.match(studentBlocker(maitre, maitre), /propre élève/);
  assert.deepEqual(
    eligibleStudents(mine, maitre, vide()).map((w) => w.id),
    ["novice", "egal", "autre"],
  );
});
test("un mercenaire déjà occupé ailleurs ou à l'entraînement n'est pas proposé", () => {
  assert.deepEqual(
    eligibleStudents(mine, maitre, vide(), ["novice"]).map((w) => w.id),
    ["egal", "autre"],
  );
  const state = buildTraining(
    [{ role: "eleve", position: 0, mercenaire_id: "egal" }],
    1,
  );
  assert.deepEqual(
    eligibleStudents(mine, maitre, state).map((w) => w.id),
    ["novice", "autre"],
  );
});
test("état d'affichage construit depuis les lignes de la base", () => {
  const state = buildTraining(
    [
      { role: "instructeur", position: 0, mercenaire_id: "maitre" },
      { role: "eleve", position: 1, mercenaire_id: "novice" },
    ],
    2,
  );
  assert.equal(state.instructor.heroId, "maitre");
  assert.equal(state.capacity, 2);
  assert.equal(state.students[0], null);
  assert.equal(state.students[1].heroId, "novice");
  assert.deepEqual(trainingIds(state), ["maitre", "novice"]);
});
test("état vide et places bornées entre 1 et 3", () => {
  assert.deepEqual(buildTraining([], 1), INITIAL_TRAINING);
  assert.equal(buildTraining([], 9).capacity, 3);
  assert.equal(buildTraining([], 0).capacity, 1);
  assert.equal(buildTraining([], undefined).capacity, 1);
});
test("une ligne hors des places connues est ignorée", () => {
  const state = buildTraining(
    [{ role: "eleve", position: 7, mercenaire_id: "x" }],
    3,
  );
  assert.deepEqual(trainingIds(state), []);
});
import {
  INITIAL_DORMITORY,
  INITIAL_INFIRMARY,
  SOINS_INSTANCES,
  buildDorm,
  buildInfirmary,
} from "../src/dormitory.js";
test("infirmerie : les soins durent 5 instances", () => {
  assert.equal(SOINS_INSTANCES, 5);
});
test("infirmerie : état d'affichage construit depuis les lignes de la base", () => {
  const state = buildInfirmary(
    [
      { position: 0, mercenaire_id: "a", restant: 5 },
      { position: 2, mercenaire_id: "b", restant: 1 },
    ],
    3,
  );
  assert.equal(state.capacity, 3);
  assert.deepEqual(state.beds[0], { heroId: "a", remaining: 5 });
  assert.equal(state.beds[1], null);
  assert.deepEqual(state.beds[2], { heroId: "b", remaining: 1 });
  assert.equal(state.beds.length, INITIAL_INFIRMARY.beds.length);
});
test("infirmerie : vide par défaut, lits bornés entre 2 et 3, ligne inconnue ignorée", () => {
  assert.deepEqual(buildInfirmary([], 2), INITIAL_INFIRMARY);
  assert.equal(buildInfirmary([], 9).capacity, 3);
  assert.equal(buildInfirmary([], 0).capacity, 2);
  assert.equal(buildInfirmary([], undefined).capacity, 2);
  const s = buildInfirmary([{ position: 9, mercenaire_id: "x", restant: 5 }], 3);
  assert.ok(s.beds.every((b) => b === null));
});
test("dortoir : les lits viennent de la base, un lit par recrutement, capacité partagée", () => {
  const rows = [
    { mercenaire_id: "a", lit: 0 },
    { mercenaire_id: "b", lit: 3 },
  ];
  const d = buildDorm(rows, 6);
  assert.equal(d.capacity, 6);
  assert.deepEqual(
    d.beds.slice(0, 5).map((b) => b?.heroId ?? null),
    ["a", null, null, "b", null],
  );
  assert.equal(d.beds.length, INITIAL_DORMITORY.beds.length);
  // Le 7e lit débloqué est compté dans la capacité (partagée par tous).
  assert.equal(buildDorm(rows, 7).capacity, 7);
});
test("dortoir : capacité bornée (6 au minimum), lit hors limites ignoré", () => {
  assert.equal(buildDorm([], undefined).capacity, 6);
  assert.equal(buildDorm([], 2).capacity, 6);
  assert.equal(buildDorm([], 99).capacity, 18);
  const d = buildDorm([{ mercenaire_id: "x", lit: 40 }], 6);
  assert.ok(d.beds.every((b) => b === null));
});
