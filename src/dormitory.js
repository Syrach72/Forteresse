export const INITIAL_DORMITORY = {
  capacity: 6,
  beds: [
    { heroId: "tavoul", remaining: 3 },
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

export const INITIAL_INFIRMARY = {
  capacity: 2,
  beds: [{ heroId: "orik", remaining: 3 }, null, null, null, null, null],
};
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
