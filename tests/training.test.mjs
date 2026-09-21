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
