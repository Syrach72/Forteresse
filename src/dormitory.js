export const INITIAL_DORMITORY = {
  capacity: 6,
  beds: [
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
  ],
};
// Premier lit débloqué et libre du dortoir (indice), ou -1 s'il n'y en a pas :
// les lits occupés et les lits verrouillés (au-delà de la capacité) ne comptent pas.
export function firstFreeBed(dorm) {
  return dorm.beds.slice(0, dorm.capacity).findIndex((b) => !b);
}

// Dortoir PARTAGÉ : le lit d'un mercenaire est attribué par la base à son
// recrutement (premier lit libre) et lui reste jusqu'à son renvoi de la
// compagnie. `rows` = lignes de recrutement { mercenaire_id, lit }, `places` =
// nombre de lits débloqués (6, ou 7 après déblocage).
export function buildDorm(rows = [], places = 6) {
  const state = structuredClone(INITIAL_DORMITORY);
  state.capacity = Math.max(6, Math.min(state.beds.length, Number(places) || 6));
  for (const r of rows)
    if (r.lit >= 0 && r.lit < state.beds.length)
      state.beds[r.lit] = { heroId: r.mercenaire_id, remaining: 0 };
  return state;
}

export const INITIAL_INFIRMARY = {
  capacity: 2,
  beds: [null, null, null, null, null, null],
};
// Durée des soins à l'arrivée à l'infirmerie, en instances (règle de Bruno).
export const SOINS_INSTANCES = 5;
// Infirmerie PARTAGÉE (tables infirmerie_place / infirmerie_reglage) : état
// d'affichage à partir des lignes de la base. `places` = lignes
// { position, mercenaire_id, restant }, `capacity` = lits débloqués (2 ou 3).
export function buildInfirmary(places = [], capacity = 2) {
  const state = structuredClone(INITIAL_INFIRMARY);
  state.capacity = Math.max(2, Math.min(3, Number(capacity) || 2));
  for (const p of places)
    if (p.position >= 0 && p.position < state.beds.length)
      state.beds[p.position] = { heroId: p.mercenaire_id, remaining: p.restant };
  return state;
}
