import { ITEMS, INITIAL } from "./data.js";
import { initialAlchemy } from "./alchemy.js";
import { initialMage } from "./mage.js";
// Noms d'ingrédients du catalogue Supabase (ingredient_recette) reconnus
// comme correspondant aux trois matériaux de fabrication (Métal, Cuir,
// Bois). Utilisée à la fois par transact() (craft/craft-queue/craft-
// catalogue) et par l'UI (App.jsx) pour afficher le stock et activer/
// désactiver le bouton de fabrication : une seule source pour éviter que
// les deux se contredisent.
export const RESOURCE_ALIASES = {
  fer: "metal",
  métal: "metal",
  metal: "metal",
  cuir: "leather",
  bois: "wood",
};
// Métal/Cuir/Bois ne sont plus un compteur séparé (ex game.resources) :
// ce sont des lignes ordinaires de game.inventory, comme n'importe quel
// autre objet (démo locale au démarrage, remplacées par l'objet réel du
// catalogue admin dès qu'il existe — voir App.jsx). Un seul compteur par
// matériau, qu'il vienne de la démo ou de l'Arsenal admin : le trouver par
// son id de secours local `material:<clé>`, ou par son nom (Fer/Métal/
// Cuir/Bois) via RESOURCE_ALIASES si c'est une ligne venue du catalogue.
export function findMaterialLine(inventory, key) {
  return inventory.find((i) => {
    if (i.id === `material:${key}`) return true;
    return RESOURCE_ALIASES[(i.nom || "").trim().toLowerCase()] === key;
  });
}
export function materialQuantity(inventory, key) {
  return findMaterialLine(inventory, key)?.quantity ?? 0;
}
function spendMaterial(next, key, amount) {
  const line = findMaterialLine(next.inventory, key);
  if (line) line.quantity -= amount;
}
// Ingrédient d'une recette du catalogue (Forge, Armurerie, Laboratoire, Tour
// du Mage) : Fer/Métal/Cuir/Bois passent par les alias ci-dessus, tout autre
// composant (alchimie, gemmes...) est cherché par son nom dans l'inventaire.
const normalizeName = (s) => (s || "").trim().toLowerCase();
export function findIngredientLine(inventory, nom) {
  const key = RESOURCE_ALIASES[normalizeName(nom)];
  if (key) return findMaterialLine(inventory, key);
  return inventory.find((i) => normalizeName(i.nom) === normalizeName(nom));
}
export function ingredientQuantity(inventory, nom) {
  return findIngredientLine(inventory, nom)?.quantity ?? 0;
}
// Valeur d'une ligne d'inventaire : coût d'achat du catalogue (champ valeur)
// ou prix de la démo locale (ITEMS) ; null si aucune valeur n'est définie.
export function sellableValue(own) {
  const legacy = ITEMS.find((i) => i.id === own.id);
  const raw = own.valeur ?? legacy?.price;
  if (raw === null || raw === undefined) return null;
  const n = Number(raw);
  return Number.isFinite(n) && n >= 0 ? n : null;
}
export function initialGame() {
  return {
    ...structuredClone(INITIAL),
    alchemy: initialAlchemy(),
    mage: initialMage(),
    // Fabrications locales (forge/armurerie) ou du catalogue lancees mais
    // pas encore recuperees : { [route]: idObjetITEMS | {id,nom,icone,
    // categorie} | null }. Voir "craft-queue"/"craft-catalogue" (mise en
    // attente) et "collect-craft" (recuperation manuelle) ci-dessous.
    craftingQueue: {},
  };
}
export function transact(state, action) {
  const item = ITEMS.find((i) => i.id === action.id);
  const next = structuredClone(state);
  let message = "";
  let delta = 0;
  const add = () => {
    const own = next.inventory.find((i) => i.id === item.id);
    if (own) own.quantity++;
    else next.inventory.push({ id: item.id, quantity: 1, equipped: false });
  };
  if (action.type === "buy") {
    if (!item || !next.stock[item.id])
      return { error: "Cet objet est épuisé." };
    if (next.gold < item.price)
      return { error: "Vous n’avez pas assez de pièces d’or." };
    next.gold -= item.price;
    next.stock[item.id]--;
    add();
    message = `${item.name} acheté : −${item.price} Po.`;
  } else if (action.type === "craft") {
    if (!item?.metal) return { error: "Cette recette n’existe pas." };
    if (["metal", "leather", "wood"].some((k) => materialQuantity(next.inventory, k) < item[k]))
      return { error: "Ressources insuffisantes pour cette fabrication." };
    for (const k of ["metal", "leather", "wood"]) spendMaterial(next, k, item[k]);
    add();
    message = `${item.name} fabriqué et ajouté au stock.`;
  } else if (action.type === "equip") {
    const own = next.inventory.find((i) => i.id === action.id);
    if (!own || !item || item.type === "Potions") return { error: "Cet objet ne peut pas être équipé." };
    own.equipped = !own.equipped;
    message = `${item.name} ${own.equipped ? "équipé" : "rangé"}.`;
  } else if (action.type === "use") {
    const own = next.inventory.find((i) => i.id === action.id);
    if (!own || own.quantity < 1 || item?.type !== "Potions") return { error: "Aucune potion disponible." };
    own.quantity--;
    next.inventory = next.inventory.filter((i) => i.quantity > 0);
    message =
      "Potion utilisée. Appliquez ses effets manuellement sur la fiche.";
  } else if (action.type === "quest") {
    next.quest = true;
    message = "Quête acceptée : Les ombres du col.";
  } else return { error: "Action inconnue." };
  next.log.unshift({
    id: crypto.randomUUID(),
    message,
    date: new Date().toISOString(),
    amount: action.type === "buy" ? -item.price : delta,
  });
  next.log = next.log.slice(0, 50);
  return { state: next, message };
}
