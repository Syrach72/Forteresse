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
export function updateDormitory(dorm, action) {
  const next = structuredClone(dorm);
  if (
    !Number.isInteger(action.slot) ||
    action.slot < 0 ||
    action.slot >= next.capacity
  )
    return { error: "Cet emplacement n’est pas débloqué." };
  if (action.type === "place") {
    if (next.beds[action.slot])
      return { error: "Cet emplacement est déjà occupé." };
    if (!action.heroId) return { error: "Choisissez un mercenaire." };
    if (next.beds.some((b) => b?.heroId === action.heroId))
      return { error: "Ce mercenaire est déjà au dortoir." };
    if (
      !Number.isInteger(action.remaining) ||
      action.remaining < 0 ||
      action.remaining > 5
    )
      return { error: "Saisissez une durée entière de 0 à 5." };
    next.beds[action.slot] = {
      heroId: action.heroId,
      remaining: action.remaining,
    };
  } else if (action.type === "duration") {
    if (!next.beds[action.slot]) return { error: "Cet emplacement est vide." };
    if (
      !Number.isInteger(action.remaining) ||
      action.remaining < 0 ||
      action.remaining > 5
    )
      return { error: "Saisissez une durée entière de 0 à 5." };
    next.beds[action.slot].remaining = action.remaining;
  } else if (action.type === "release") {
    next.beds[action.slot] = null;
  } else return { error: "Action inconnue." };
  return { state: next };
}

// Premier lit débloqué et libre du dortoir (indice), ou -1 s'il n'y en a pas :
// les lits occupés et les lits verrouillés (au-delà de la capacité) ne comptent pas.
export function firstFreeBed(dorm) {
  return dorm.beds.slice(0, dorm.capacity).findIndex((b) => !b);
}

// Le lit représente l'embauche d'un mercenaire (rien à voir avec le repos) :
// un lit par mercenaire recruté. Libère les lits des mercenaires qui ne sont plus
// recrutés (renvoyés) et place les recrutés sans lit dans les premiers lits
// libres et débloqués, dans l'ordre de `recruitedIds` (ordre de recrutement).
export function syncRecruits(dorm, recruitedIds) {
  const wanted = new Set(recruitedIds);
  const beds = dorm.beds.map((b) => (b && wanted.has(b.heroId) ? b : null));
  const placed = new Set(beds.filter(Boolean).map((b) => b.heroId));
  for (const id of recruitedIds) {
    if (placed.has(id)) continue;
    const slot = firstFreeBed({ ...dorm, beds });
    if (slot < 0) break;
    beds[slot] = { heroId: id, remaining: 0 };
    placed.add(id);
  }
  return { ...dorm, beds };
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
export function stepDurations(area, delta) {
  return {
    ...area,
    beds: area.beds.map((b) =>
      b
        ? { ...b, remaining: Math.max(0, Math.min(5, b.remaining + delta)) }
        : null,
    ),
  };
}
