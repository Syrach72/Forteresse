import test from "node:test";
import assert from "node:assert/strict";
import {
  instancesParNiveau,
  instancesRestantesFormation,
  xpFormationParInstance,
  xpGainEchec,
  xpGainQuete,
  xpPalier,
} from "../src/xp.js";

test("paliers : 20, 20, 30, 30, 40, 40, 50, 60, 70, puis plus rien au niveau 10", () => {
  assert.deepEqual([1, 2, 3, 4, 5, 6, 7, 8, 9].map(xpPalier), [20, 20, 30, 30, 40, 40, 50, 60, 70]);
  assert.equal(xpPalier(10), null);
  let total = 0;
  for (let n = 1; n < 10; n++) total += xpPalier(n);
  assert.equal(total, 360);
});

test("gain de quête selon l'écart FP − vétérance", () => {
  assert.deepEqual([5, 4, 3, 2, 1, 0].map((fp) => xpGainQuete(fp, 3)), [15, 12, 10, 6, 3, 0]);
  assert.equal(xpGainQuete(10, 1), 15);
  assert.equal(xpGainQuete(1, 9), 0);
});

test("quête échouée : un quart du gain, arrondi à l'inférieur", () => {
  assert.deepEqual([15, 12, 10, 6, 3, 0].map((g, i) => xpGainEchec(5 - i + 0, 3) - Math.floor(g / 4)), [0, 0, 0, 0, 0, 0]);
  assert.equal(xpGainEchec(3, 3), 2);
  assert.equal(xpGainEchec(5, 3), 3);
  assert.equal(xpGainEchec(2, 3), 1);
  assert.equal(xpGainEchec(0, 3), 0);
});

test("formation : 1 instance par niveau à 3 niveaux d'écart, 2 à 2, 3 à 1", () => {
  assert.deepEqual([5, 4, 3, 2, 1].map(instancesParNiveau), [1, 1, 1, 2, 3]);
  assert.equal(xpFormationParInstance(5, 8), 40);
  assert.equal(xpFormationParInstance(5, 7), 20);
  assert.equal(xpFormationParInstance(5, 6), 14);
});

test("formation : exemple niveau 2 sous un instructeur niveau 7 = 8 instances", () => {
  assert.equal(instancesRestantesFormation(2, 0, 7), 8);
  assert.equal(instancesRestantesFormation(6, 0, 7), 3);
  assert.equal(instancesRestantesFormation(6, 14, 7), 2);
  assert.equal(instancesRestantesFormation(7, 0, 7), 0);
});
