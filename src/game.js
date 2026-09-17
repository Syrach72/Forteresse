import { ITEMS, INITIAL } from "./data.js";
import { initialAlchemy } from "./alchemy.js";
import { initialMage } from "./mage.js";
// Noms d'ingrédients du catalogue Supabase (ingredient_recette) reconnus
// comme correspondant aux ressources locales suivies dans game.resources.
// Utilisée à la fois par transact() (craft-catalogue) et par l'UI (App.jsx)
// pour afficher le stock et activer/désactiver le bouton de fabrication :
// une seule source pour éviter que les deux se contredisent.
export const RESOURCE_ALIASES = {
  fer: "metal",
  métal: "metal",
  metal: "metal",
  cuir: "leather",
  bois: "wood",
};
export function initialGame() {
  return {
    ...structuredClone(INITIAL),
    alchemy: initialAlchemy(),
    mage: initialMage(),
    // Fabrications locales (forge/armurerie) lancees mais pas encore
    // livrees : { [route]: idObjetITEMS | null }. Voir "craft-queue" et
    // resolveCraftingQueue ci-dessous.
    craftingQueue: {},
  };
}
export function transact(state, action) {
  const item = ITEMS.find((i) => i.id === action.id);
  const next = structuredClone(state);
  let message = "";
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
    if (["metal", "leather", "wood"].some((k) => next.resources[k] < item[k]))
      return { error: "Ressources insuffisantes pour cette fabrication." };
    for (const k of ["metal", "leather", "wood"]) next.resources[k] -= item[k];
    add();
    message = `${item.name} fabriqué et ajouté au stock.`;
  } else if (action.type === "craft-queue") {
    // Meme recette que "craft" (ITEMS.metal/leather/wood), mais l'objet ne
    // rejoint pas l'inventaire tout de suite : il attend que la Duree
    // d'instance de cet atelier retombe a 0 (bouton +1 Instance), livre par
    // resolveCraftingQueue ci-dessous plutot que par cette action.
    if (!item?.metal) return { error: "Cette recette n’existe pas." };
    if (next.craftingQueue?.[action.route])
      return { error: "Une fabrication est déjà en cours dans cet atelier." };
    if (["metal", "leather", "wood"].some((k) => next.resources[k] < item[k]))
      return { error: "Ressources insuffisantes pour cette fabrication." };
    for (const k of ["metal", "leather", "wood"]) next.resources[k] -= item[k];
    next.craftingQueue = { ...next.craftingQueue, [action.route]: item.id };
    message = `${item.name} : fabrication lancée. Elle rejoindra l’arsenal une fois la durée d’instance à 0.`;
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
  } else if (action.type === "craft-catalogue") {
    // Fabrication d'un objet du catalogue Supabase (Forge), distinct du
    // catalogue local ITEMS : la recette vient de ingredient_recette (noms
    // libres), pas des trois champs metal/leather/wood fixes. On ne sait
    // consommer que les ressources déjà suivies localement (Fer/Métal, Cuir,
    // Bois) ; toute autre ingrédient bloque la fabrication avec un message
    // clair plutôt que de l'ignorer silencieusement.
    const arme = action.arme;
    const route = action.route;
    if (!arme?.ingredientsList?.length)
      return { error: "Cette recette n’a pas encore d’ingrédients définis." };
    if (route && next.craftingQueue?.[route])
      return { error: "Une fabrication est déjà en cours dans cet atelier." };
    const needs = [];
    for (const ing of arme.ingredientsList) {
      const key = RESOURCE_ALIASES[ing.nom.trim().toLowerCase()];
      if (!key)
        return {
          error: `« ${ing.nom} » n’est pas encore une ressource suivie par le jeu.`,
        };
      needs.push([key, ing.quantite]);
    }
    if (needs.some(([k, q]) => next.resources[k] < q))
      return { error: "Ressources insuffisantes pour cette fabrication." };
    for (const [k, q] of needs) next.resources[k] -= q;
    // Categorie racine (Armes/Armures/Produits Alchimiques/Gemmes) telle
    // que chargee par loadCatalogue (App.jsx) pour l'atelier concerne : sert
    // aux onglets de l'Arsenal, sans dependre d'un second appel a Supabase
    // depuis la page Arsenal.
    const categorie = arme.racine || null;
    const duree = Number(arme.duree_fabrication_instances) || 0;
    if (route && duree > 0) {
      // Duree de fabrication definie par l'admin : mise en attente, comme
      // "craft-queue", jusqu'a ce que la Duree d'instance de cet atelier
      // retombe a 0 (bouton +1 Instance). Voir resolveCraftingQueue.
      next.durations = { ...next.durations, [route]: duree };
      next.craftingQueue = {
        ...next.craftingQueue,
        [route]: { id: arme.id, nom: arme.nom, icone: arme.icone, categorie },
      };
      message = `${arme.nom} : fabrication lancée. Elle rejoindra l’arsenal une fois la durée d’instance à 0.`;
    } else {
      const invId = `catalogue:${arme.id}`;
      const own = next.inventory.find((i) => i.id === invId);
      if (own) own.quantity++;
      else
        next.inventory.push({
          id: invId,
          quantity: 1,
          equipped: false,
          nom: arme.nom,
          icone: arme.icone,
          categorie,
        });
      message = `${arme.nom} fabriqué et ajouté au stock.`;
    }
  } else if (action.type === "quest") {
    next.quest = true;
    message = "Quête acceptée : Les ombres du col.";
  } else return { error: "Action inconnue." };
  next.log.unshift({
    id: crypto.randomUUID(),
    message,
    date: new Date().toISOString(),
    amount: action.type === "buy" ? -item.price : 0,
  });
  next.log = next.log.slice(0, 50);
  return { state: next, message };
}
// Livre dans l'inventaire tout objet en attente (game.craftingQueue) dont
// l'atelier vient d'atteindre une Duree d'instance de 0. Appelee par
// App.jsx juste apres avoir decremente ces durees (+1 Instance), jamais
// directement par un bouton du joueur.
export function resolveCraftingQueue(state) {
  const queue = state.craftingQueue || {};
  const pending = Object.entries(queue).filter(([, v]) => v);
  if (!pending.length) return { state, delivered: [] };
  const next = structuredClone(state);
  const delivered = [];
  for (const [route, value] of pending) {
    if ((next.durations?.[route] ?? 0) > 0) continue;
    if (typeof value === "string") {
      // Objet du catalogue local de demonstration (ITEMS).
      const item = ITEMS.find((i) => i.id === value);
      const own = next.inventory.find((i) => i.id === value);
      if (own) own.quantity++;
      else next.inventory.push({ id: value, quantity: 1, equipped: false });
      delivered.push(item?.name || "Objet");
    } else {
      // Objet reel du catalogue Supabase (craft-catalogue en attente).
      const invId = `catalogue:${value.id}`;
      const own = next.inventory.find((i) => i.id === invId);
      if (own) own.quantity++;
      else
        next.inventory.push({
          id: invId,
          quantity: 1,
          equipped: false,
          nom: value.nom,
          icone: value.icone,
          categorie: value.categorie || null,
        });
      delivered.push(value.nom);
    }
    next.craftingQueue[route] = null;
  }
  return { state: next, delivered };
}
