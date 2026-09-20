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
// Annulation d'un achat ou d'une fabrication lancée depuis une fiche du
// catalogue, tant que la fiche est restée ouverte. `stack` = pile des
// opérations faites sur cette fiche : { kind, before, after, message }, où
// `before`/`after` sont l'état de jeu avant et après (transact renvoie
// toujours un nouvel objet). On annule la dernière en restaurant `before`
// tel quel : c'est exact (or, stocks, ressources, atelier, journal), sans
// rejouer d'opération inverse. Refusée si l'état courant n'est plus celui
// produit par cette opération (autre changement entre-temps) : on ne
// restaure jamais un vieil état par-dessus une situation qui a évolué.
export function undoLast(stack, current) {
  const last = stack[stack.length - 1];
  if (!last) return { error: "Aucune opération à annuler." };
  if (current !== last.after)
    return { error: "Annulation impossible : la situation a changé depuis." };
  return { state: last.before, stack: stack.slice(0, -1), kind: last.kind };
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
  } else if (action.type === "buy-catalogue") {
    // Achat d'un objet du catalogue Supabase depuis le Marché : le coût
    // d'achat (cout_achat_or, défini par l'admin) est débité de la
    // trésorerie (game.gold) et l'objet rejoint l'arsenal. Sans coût défini,
    // l'achat est refusé plutôt que d'offrir l'objet.
    const arme = action.arme;
    const cout = arme?.cout_achat_or;
    if (!arme?.id) return { error: "Objet inconnu." };
    if (cout === null || cout === undefined || !Number.isFinite(Number(cout)) || Number(cout) < 0)
      return { error: "Le coût d’achat de cet objet n’est pas encore défini." };
    if (next.gold < Number(cout))
      return { error: "Vous n’avez pas assez de pièces d’or." };
    const spent = Number(cout);
    next.gold -= spent;
    delta = -spent || 0;
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
        categorie: arme.racine || null,
        valeur: spent,
      });
    message = `${arme.nom} acheté : −${spent} Po.`;
  } else if (action.type === "sell") {
    // Vente au Marché : l'objet est cédé pour la moitié de sa valeur (coût
    // d'achat du catalogue, ou prix de la démo locale), créditée à la
    // trésorerie. Sans valeur définie, la vente est refusée.
    const own = next.inventory.find((i) => i.id === action.id);
    const qty = Math.floor(Number(action.quantity));
    if (!own) return { error: "Cet objet n’est plus dans l’arsenal." };
    if (!(qty >= 1) || qty > own.quantity) return { error: "Quantité invalide." };
    if (own.equipped) return { error: "Rangez d’abord cet objet équipé avant de le vendre." };
    const unit = sellableValue(own);
    if (unit === null)
      return { error: "La valeur de cet objet n’est pas définie : vente impossible." };
    const gain = Math.floor((unit * qty) / 2);
    own.quantity -= qty;
    if (own.quantity <= 0) next.inventory = next.inventory.filter((i) => i.id !== own.id);
    next.gold += gain;
    delta = gain;
    message = `Vente de ${item?.name || own.nom || "l’objet"} ×${qty} : +${gain} Po.`;
  } else if (action.type === "destroy") {
    // Destruction définitive d'une quantité d'un objet de l'arsenal (aucun
    // gain). La confirmation Oui/Non est demandée par l'interface.
    const own = next.inventory.find((i) => i.id === action.id);
    const qty = Math.floor(Number(action.quantity));
    if (!own) return { error: "Cet objet n’est plus dans l’arsenal." };
    if (!(qty >= 1) || qty > own.quantity) return { error: "Quantité invalide." };
    if (own.equipped) return { error: "Rangez d’abord cet objet équipé avant de le détruire." };
    own.quantity -= qty;
    if (own.quantity <= 0) next.inventory = next.inventory.filter((i) => i.id !== own.id);
    message = `Destruction de ${item?.name || own.nom || "l’objet"} ×${qty}.`;
  } else if (action.type === "craft") {
    if (!item?.metal) return { error: "Cette recette n’existe pas." };
    if (["metal", "leather", "wood"].some((k) => materialQuantity(next.inventory, k) < item[k]))
      return { error: "Ressources insuffisantes pour cette fabrication." };
    for (const k of ["metal", "leather", "wood"]) spendMaterial(next, k, item[k]);
    add();
    message = `${item.name} fabriqué et ajouté au stock.`;
  } else if (action.type === "craft-queue") {
    // Meme recette que "craft" (ITEMS.metal/leather/wood), mais l'objet ne
    // rejoint pas l'inventaire tout de suite : il attend que la Duree
    // d'instance de cet atelier retombe a 0 (bouton +1 Instance), PUIS que
    // le joueur clique "Envoyer à l'Arsenal" (action "collect-craft").
    if (!item?.metal) return { error: "Cette recette n’existe pas." };
    if (next.craftingQueue?.[action.route])
      return { error: "Une fabrication est déjà en cours dans cet atelier." };
    if (["metal", "leather", "wood"].some((k) => materialQuantity(next.inventory, k) < item[k]))
      return { error: "Ressources insuffisantes pour cette fabrication." };
    for (const k of ["metal", "leather", "wood"]) spendMaterial(next, k, item[k]);
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
    // libres), pas des trois champs metal/leather/wood fixes. Chaque
    // ingrédient/composant est débité de l'inventaire (Arsenal) par son nom ;
    // un composant absent du stock compte comme insuffisant.
    const arme = action.arme;
    const route = action.route;
    if (!arme?.ingredientsList?.length)
      return { error: "Cette recette n’a pas encore d’ingrédients définis." };
    if (route && next.craftingQueue?.[route])
      return { error: "Une fabrication est déjà en cours dans cet atelier." };
    const needs = arme.ingredientsList.map((ing) => [ing.nom, ing.quantite]);
    if (needs.some(([nom, q]) => ingredientQuantity(next.inventory, nom) < q))
      return { error: "Ressources insuffisantes pour cette fabrication." };
    for (const [nom, q] of needs) findIngredientLine(next.inventory, nom).quantity -= q;
    // Categorie racine (Armes/Armures/Produits Alchimiques/Gemmes) telle
    // que chargee par loadCatalogue (App.jsx) pour l'atelier concerne : sert
    // aux onglets de l'Arsenal, sans dependre d'un second appel a Supabase
    // depuis la page Arsenal.
    const categorie = arme.racine || null;
    const duree = Number(arme.duree_fabrication_instances) || 0;
    if (route && duree > 0) {
      // Duree de fabrication definie par l'admin : mise en attente, comme
      // "craft-queue", jusqu'a ce que la Duree d'instance de cet atelier
      // retombe a 0 (bouton +1 Instance) PUIS "collect-craft".
      next.durations = { ...next.durations, [route]: duree };
      next.craftingQueue = {
        ...next.craftingQueue,
        [route]: {
          id: arme.id,
          nom: arme.nom,
          icone: arme.icone,
          categorie,
          cout: arme.cout_achat_or ?? null,
        },
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
          valeur: arme.cout_achat_or ?? null,
        });
      message = `${arme.nom} fabriqué et ajouté au stock.`;
    }
  } else if (action.type === "collect-craft") {
    // Recuperation manuelle d'une fabrication (locale ou catalogue) une fois
    // sa Duree d'instance a 0 : contrairement a une livraison automatique,
    // le joueur doit cliquer "Envoyer à l’Arsenal" pour liberer l'atelier et
    // permettre une nouvelle fabrication.
    const route = action.route;
    const value = next.craftingQueue?.[route];
    if (!value)
      return { error: "Aucune fabrication à récupérer dans cet atelier." };
    if ((next.durations?.[route] ?? 0) > 0)
      return { error: "La fabrication n’est pas encore terminée." };
    if (typeof value === "string") {
      const it = ITEMS.find((i) => i.id === value);
      const own = next.inventory.find((i) => i.id === value);
      if (own) own.quantity++;
      else next.inventory.push({ id: value, quantity: 1, equipped: false });
      message = `${it?.name || "Objet"} rejoint l’arsenal.`;
    } else {
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
          valeur: value.cout ?? null,
        });
      message = `${value.nom} rejoint l’arsenal.`;
    }
    next.craftingQueue = { ...next.craftingQueue, [route]: null };
    // Vide aussi la Duree d'instance de cet atelier (retombee a 0) : sans
    // ca, la fiche rouverte affiche encore "0" au lieu de repartir sur la
    // valeur par defaut, et une nouvelle fabrication se livrerait donc
    // instantanement au lieu d'attendre.
    if (next.durations) {
      const { [route]: _cleared, ...rest } = next.durations;
      next.durations = rest;
    }
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
