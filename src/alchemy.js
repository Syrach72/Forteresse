// Recettes et quantités de démonstration : à remplacer par les règles de Bruno.
export const INGREDIENTS = [
  { id: 'mushroom', name: 'Champignon', image: '/assets/icons/mushroom.webp' },
  { id: 'worm', name: 'Ver mystique' },
  { id: 'scorpion', name: 'Scorpion' },
  { id: 'spider', name: 'Araignée' },
  { id: 'eye', name: 'Œil' },
  { id: 'slime', name: 'Gelée verte' },
  { id: 'wing', name: 'Aile de chauve-souris' },
  { id: 'root', name: 'Mandragore' },
  { id: 'sun', name: 'Essence solaire' },
  { id: 'claw', name: 'Griffe' },
  { id: 'blood', name: 'Sang' },
  { id: 'tentacle', name: 'Tentacules' },
  { id: 'sulfur', name: 'Soufre' },
  { id: 'salt', name: 'Sel blanc' },
  { id: 'silver', name: 'Poudre d’argent' },
  { id: 'coal', name: 'Charbon' },
].map((item, index) => ({ ...item, crop: [736 + (index % 4) * 80, 165 + Math.floor(index / 4) * 82, 51, 52] }));
export const ALCHEMY_RECIPES = [
  { id: 'healing', name: 'Potion de soin', output: 'potion', ingredients: ['mushroom', 'slime', 'salt'], color: '#a7e777' },
  { id: 'energy', name: 'Potion d’énergie', output: 'potion-energy', ingredients: ['mushroom', 'root', 'sun', 'sulfur'], color: '#f8cb68' },
  { id: 'clarity', name: 'Potion de clairvoyance', output: 'potion-clarity', ingredients: ['eye', 'worm', 'silver', 'salt', 'coal'], color: '#b5a3ff' },
];
export function initialAlchemy() {
  return { stock: Object.fromEntries(INGREDIENTS.map(i => [i.id, 6])), slots: Array(5).fill(null) };
}
export function availableIngredient(alchemy, id) {
  return (alchemy.stock[id] || 0) - alchemy.slots.filter(x => x === id).length;
}
export function findAlchemyRecipe(slots) {
  const key = slots.filter(Boolean).sort().join('|');
  return ALCHEMY_RECIPES.find(r => [...r.ingredients].sort().join('|') === key);
}
const validSlot = index => Number.isInteger(index) && index >= 0 && index < 5;
export function changeAlchemy(game, action) {
  const next = structuredClone(game);
  next.alchemy ||= initialAlchemy();
  const a = next.alchemy;
  let recipe;
  if (action.type === 'place') {
    if (!validSlot(action.slot) || !INGREDIENTS.some(i => i.id === action.id)) return { error: 'Cet ingrédient ou cette branche est inconnu.' };
    if (a.slots[action.slot] === action.id) return { state: next };
    if (availableIngredient(a, action.id) < 1) return { error: 'Tous les exemplaires de cet ingrédient sont déjà déposés.' };
    a.slots[action.slot] = action.id;
  } else if (action.type === 'move') {
    if (!validSlot(action.from) || !validSlot(action.to) || !a.slots[action.from]) return { error: 'Choisissez une branche contenant un ingrédient.' };
    [a.slots[action.from], a.slots[action.to]] = [a.slots[action.to], a.slots[action.from]];
  } else if (action.type === 'remove') {
    if (!validSlot(action.slot)) return { error: 'Cette branche est inconnue.' };
    a.slots[action.slot] = null;
  } else if (action.type === 'clear') {
    a.slots = Array(5).fill(null);
  } else if (action.type === 'fill') {
    const target = ALCHEMY_RECIPES.find(r => r.id === action.recipeId);
    if (!target) return { error: 'Cette recette est inconnue.' };
    const required = {};
    for (const id of target.ingredients) required[id] = (required[id] || 0) + 1;
    const missing = Object.entries(required)
      .filter(([id, count]) => !Number.isInteger(a.stock[id]) || a.stock[id] < count)
      .map(([id, count]) => `${INGREDIENTS.find(i => i.id === id)?.name || id} (${a.stock[id] || 0}/${count})`);
    if (missing.length) return { error: `Composants manquants pour ${target.name} : ${missing.join(', ')}.` };
    a.slots = Array(5).fill(null);
    target.ingredients.forEach((id, index) => { a.slots[index] = id; });
  } else if (action.type === 'brew') {
    recipe = findAlchemyRecipe(a.slots);
    if (!recipe) return { error: 'Aucune recette connue pour cette combinaison. Les ingrédients sont conservés.' };
    const required = {};
    for (const id of recipe.ingredients) required[id] = (required[id] || 0) + 1;
    if (Object.entries(required).some(([id, count]) => !Number.isInteger(a.stock[id]) || a.stock[id] < count)) return { error: 'Il manque un ingrédient. La fabrication est annulée.' };
    for (const [id, count] of Object.entries(required)) a.stock[id] -= count;
    a.slots = Array(5).fill(null);
    const existing = next.inventory.find(i => i.id === recipe.output);
    if (existing) existing.quantity++;
    else next.inventory.push({ id: recipe.output, quantity: 1, equipped: false });
    next.log.unshift({ id: crypto.randomUUID(), date: new Date().toISOString(), amount: 0, message: `${recipe.name} fabriquée au laboratoire et ajoutée à l’arsenal.` });
    next.log = next.log.slice(0, 50);
  } else return { error: 'Action inconnue.' };
  return { state: next, recipe };
}
