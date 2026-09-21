import test from "node:test";
import assert from "node:assert/strict";
import {
  INITIAL_TRAINING,
  PRIX_INSTRUCTEUR_GROUPE_2,
  PRIX_PLACE_ELEVE,
  VETERANCE_ECART,
  buildTraining,
  eligibleStudents,
  freeInstructorGroup,
  groupOfInstructor,
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
  prixLitDortoir,
  prixLitInfirmerie,
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
test("infirmerie : vide par défaut, lits bornés entre 2 et 6, ligne inconnue ignorée", () => {
  assert.deepEqual(buildInfirmary([], 2), INITIAL_INFIRMARY);
  assert.equal(buildInfirmary([], 6).capacity, 6);
  assert.equal(buildInfirmary([], 9).capacity, 6);
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
test("dortoir : prix des lits, 100 / 150 / 200 / 300 Po par groupe de trois, dans l'ordre", () => {
  const attendu = [100, 100, 100, 150, 150, 150, 200, 200, 200, 300, 300, 300];
  assert.deepEqual(
    Array.from({ length: 12 }, (_, i) => prixLitDortoir(6 + i)),
    attendu,
  );
  // Total pour débloquer les 12 lits : 3×100 + 3×150 + 3×200 + 3×300.
  assert.equal(attendu.reduce((a, b) => a + b, 0), 2250);
});
test("dortoir : les 6 premiers lits et les lits hors dortoir n'ont pas de prix", () => {
  for (const slot of [0, 5, 18, 40, -1, 6.5, undefined, null])
    assert.equal(prixLitDortoir(slot), null);
});
test("infirmerie : les 4 lits verrouillés coûtent 300 / 500 / 800 / 1200 Po dans l'ordre", () => {
  assert.deepEqual(
    [2, 3, 4, 5].map((slot) => prixLitInfirmerie(slot)),
    [300, 500, 800, 1200],
  );
  for (const slot of [0, 1, 6, -1, 2.5, undefined, null])
    assert.equal(prixLitInfirmerie(slot), null);
});
const ligne = (groupe, role, position, mercenaire_id) => ({ groupe, role, position, mercenaire_id });
test("terrain : le second groupe est bloqué au départ, avec ses propres places", () => {
  assert.equal(INITIAL_TRAINING.second.unlocked, false);
  assert.equal(INITIAL_TRAINING.second.instructor, null);
  assert.equal(INITIAL_TRAINING.second.capacity, 1);
  assert.equal(PRIX_INSTRUCTEUR_GROUPE_2, 1000);
  assert.deepEqual(PRIX_PLACE_ELEVE, { 1: 100, 2: 300 });
});
test("terrain : les lignes de chaque groupe vont dans le bon groupe (groupe 1 par défaut)", () => {
  const state = buildTraining(
    [
      ligne(1, "instructeur", 0, "a"),
      ligne(1, "eleve", 0, "b"),
      ligne(2, "instructeur", 0, "c"),
      ligne(2, "eleve", 1, "d"),
      { role: "eleve", position: 2, mercenaire_id: "e" },
    ],
    3,
    { groupe2_debloque: true, places_eleves_2: 2 },
  );
  assert.equal(state.instructor.heroId, "a");
  assert.equal(state.students[0].heroId, "b");
  assert.equal(state.students[2].heroId, "e");
  assert.equal(state.second.unlocked, true);
  assert.equal(state.second.capacity, 2);
  assert.equal(state.second.instructor.heroId, "c");
  assert.equal(state.second.students[1].heroId, "d");
  assert.equal(state.second.students[0], null);
  assert.deepEqual(trainingIds(state).sort(), ["a", "b", "c", "d", "e"]);
});
test("terrain : places du second groupe bornées entre 1 et 3", () => {
  assert.equal(buildTraining([], 1, { places_eleves_2: 9 }).second.capacity, 3);
  assert.equal(buildTraining([], 1, { places_eleves_2: 0 }).second.capacity, 1);
  assert.equal(buildTraining([], 1, null).second.unlocked, false);
});
test("terrain : un élève du second groupe n'est proposé nulle part ailleurs", () => {
  const state = buildTraining([ligne(2, "eleve", 0, "novice")], 1, {
    groupe2_debloque: true,
  });
  assert.deepEqual(
    eligibleStudents(mine, maitre, state).map((w) => w.id),
    ["egal", "autre"],
  );
});
test("terrain : un nouvel instructeur va dans le premier groupe libre", () => {
  assert.equal(freeInstructorGroup(vide()), 1);
  const g1 = buildTraining([ligne(1, "instructeur", 0, "a")]);
  assert.equal(freeInstructorGroup(g1), null); // second groupe bloqué
  const g2 = buildTraining([ligne(1, "instructeur", 0, "a")], 1, { groupe2_debloque: true });
  assert.equal(freeInstructorGroup(g2), 2);
  const complet = buildTraining(
    [ligne(1, "instructeur", 0, "a"), ligne(2, "instructeur", 0, "c")],
    1,
    { groupe2_debloque: true },
  );
  assert.equal(freeInstructorGroup(complet), null);
  assert.equal(groupOfInstructor(complet, "a"), 1);
  assert.equal(groupOfInstructor(complet, "c"), 2);
  assert.equal(groupOfInstructor(complet, "z"), null);
});
import { ENTRETIEN_PAR_VETERANCE, entretienCompagnie } from "../src/treasury-data.js";
test("entretien : 10 Po par point de vétérance de tous les mercenaires du dortoir", () => {
  assert.equal(ENTRETIEN_PAR_VETERANCE, 10);
  assert.equal(entretienCompagnie([]), 0);
  assert.equal(entretienCompagnie(), 0);
  assert.equal(entretienCompagnie([0, 0, 0, 5]), 50);
  assert.equal(entretienCompagnie([3, 4, 1]), 80);
});
test("entretien : valeurs absentes ou invalides comptées pour 0", () => {
  assert.equal(entretienCompagnie([null, undefined, "x", -2, 2.9]), 20);
});
