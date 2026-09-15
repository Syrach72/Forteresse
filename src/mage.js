// Formules de démonstration : à remplacer par les règles de Bruno.
// Même mécanique que le laboratoire d'alchimie (alchemy.js), avec une
// roue à 8 branches au lieu d'un pentagramme à 5, pour les arcanes de
// la Tour du Mage. Pas d'illustrations dédiées fournies pour l'instant :
// chaque arcane est représentée par un orbe de couleur (dégradé CSS),
// pas une image inventée.
export const ARCANA = [
  { id: "feu", name: "Éclat de Feu", color: "#ff8a3d" },
  { id: "foudre", name: "Étincelle Foudroyante", color: "#ffe066" },
  { id: "eau", name: "Larme Abyssale", color: "#4d9de0" },
  { id: "givre", name: "Souffle de Givre", color: "#bdeeff" },
  { id: "lumiere", name: "Rayon de Lumière", color: "#ffd76a" },
  { id: "ombre", name: "Voile d’Ombre", color: "#4a4459" },
  { id: "esprit", name: "Murmure Spectral", color: "#7fd8c4" },
  { id: "vide", name: "Écho du Vide", color: "#8c5bd6" },
];
export const MAGE_FORMULAS = [
  {
    id: "bouclier",
    name: "Formule de Bouclier",
    output: "formule-bouclier",
    ingredients: ["lumiere", "givre", "esprit"],
    color: "#bdeeff",
  },
  {
    id: "foudroiement",
    name: "Formule de Foudroiement",
    output: "formule-foudroiement",
    ingredients: ["foudre", "vide", "feu"],
    color: "#ffe066",
  },
  {
    id: "vision",
    name: "Formule de Vision",
    output: "formule-vision",
    ingredients: ["esprit", "lumiere", "ombre", "vide", "eau"],
    color: "#8c5bd6",
  },
];
export function initialMage() {
  return { stock: Object.fromEntries(ARCANA.map((a) => [a.id, 6])), slots: Array(8).fill(null) };
}
export function availableArcana(mage, id) {
  return (mage.stock[id] || 0) - mage.slots.filter((x) => x === id).length;
}
export function findMageFormula(slots) {
  const key = slots.filter(Boolean).sort().join("|");
  return MAGE_FORMULAS.find((f) => [...f.ingredients].sort().join("|") === key);
}
const validSlot = (index) => Number.isInteger(index) && index >= 0 && index < 8;
export function changeMage(game, action) {
  const next = structuredClone(game);
  next.mage ||= initialMage();
  const m = next.mage;
  let formula;
  if (action.type === "place") {
    if (!validSlot(action.slot) || !ARCANA.some((a) => a.id === action.id))
      return { error: "Cette arcane ou cette branche est inconnue." };
    if (m.slots[action.slot] === action.id) return { state: next };
    if (availableArcana(m, action.id) < 1)
      return { error: "Tous les exemplaires de cette arcane sont déjà déposés." };
    m.slots[action.slot] = action.id;
  } else if (action.type === "move") {
    if (!validSlot(action.from) || !validSlot(action.to) || !m.slots[action.from])
      return { error: "Choisissez une branche contenant une arcane." };
    [m.slots[action.from], m.slots[action.to]] = [m.slots[action.to], m.slots[action.from]];
  } else if (action.type === "remove") {
    if (!validSlot(action.slot)) return { error: "Cette branche est inconnue." };
    m.slots[action.slot] = null;
  } else if (action.type === "clear") {
    m.slots = Array(8).fill(null);
  } else if (action.type === "fill") {
    const target = MAGE_FORMULAS.find((f) => f.id === action.formulaId);
    if (!target) return { error: "Cette formule est inconnue." };
    const required = {};
    for (const id of target.ingredients) required[id] = (required[id] || 0) + 1;
    const missing = Object.entries(required)
      .filter(([id, count]) => !Number.isInteger(m.stock[id]) || m.stock[id] < count)
      .map(([id, count]) => `${ARCANA.find((a) => a.id === id)?.name || id} (${m.stock[id] || 0}/${count})`);
    if (missing.length)
      return { error: `Arcanes manquantes pour ${target.name} : ${missing.join(", ")}.` };
    m.slots = Array(8).fill(null);
    target.ingredients.forEach((id, index) => {
      m.slots[index] = id;
    });
  } else if (action.type === "brew") {
    formula = findMageFormula(m.slots);
    if (!formula)
      return { error: "Aucune formule connue pour cette combinaison. Les arcanes sont conservées." };
    const required = {};
    for (const id of formula.ingredients) required[id] = (required[id] || 0) + 1;
    if (Object.entries(required).some(([id, count]) => !Number.isInteger(m.stock[id]) || m.stock[id] < count))
      return { error: "Il manque une arcane. L’invocation est annulée." };
    for (const [id, count] of Object.entries(required)) m.stock[id] -= count;
    m.slots = Array(8).fill(null);
    const existing = next.inventory.find((i) => i.id === formula.output);
    if (existing) existing.quantity++;
    else next.inventory.push({ id: formula.output, quantity: 1, equipped: false });
    next.log.unshift({
      id: crypto.randomUUID(),
      date: new Date().toISOString(),
      amount: 0,
      message: `${formula.name} invoquée à la Tour du Mage et ajoutée à l’arsenal.`,
    });
    next.log = next.log.slice(0, 50);
  } else return { error: "Action inconnue." };
  return { state: next, formula };
}
