import test from "node:test";
import assert from "node:assert/strict";
import { protectionsMercenaire } from "../src/protections.js";

const passive = (nom, description, veterance = 1) => ({ type: "passive", veterance, competence: { nom, description } });

// Textes réels du catalogue (relevés le 2026-10-05).
const HALFLIN = passive(
  "Halflin Robuste",
  "- Ajoute +1🎲aux tests contre la Peur.\n- RD Poison et +1🎲pour résister aux Empoisonnements.\n- A partir du niveau 3 : +1 Puissance tous les 3 niveaux de Vétérance (automatisé)",
);
const DROW = passive(
  "Drow",
  "- Vision dans le noir supérieure (24c)\n- Immunité aux sorts, potions et effets de Sommeil\n- Ajoute +1🎲aux tests de Discrétion dans le noir et les zones d'ombre\n- A partir du niveau 3 : +1 Mental tous les 3 niveaux de Vétérance (automatisé)",
);
const NAIN = passive(
  "Nain des Collines",
  "- Vitesse 5c, pas réduite par le port d'une Armure Lourde.\n- Vision dans le noir 12c\n- RD Poisons\n- +1PV à chaque montée de niveau de Vétérance au-delà du premier (automatisé).",
);
const TIEFFELIN = passive(
  "Tieffelin",
  "- Résistance au Feu\n- Vision dans le noir 12c et Vision dans les Ténèbres 6c\n- Ajoute +1🎲lorsqu'il utilise sa Carac. Mentale pour résister à un effet ou sort de l'Adv.",
);
const NECRO = passive(
  "Ecole Arcanique Nécromancien",
  "[b]Vétérance 3[/b] - [i][b]Sinistre Moisson[/b][/i] : Une fois par tour, lorsque vous tuez une créature, vous Régénérez autant de PV. [b]Vétérance 5[/b] - [i][b]Serviteurs MV[/b][/i] : quand vous lancez [i]Animation des Morts,[/i] vous pouvez créer 2 zombies. [b]Vétérance 7 [/b]- [i][b]Insensibilité à la Non-Vie[/b][/i] : Vous obtenez un RD [c=#7b3fa0][b]Nécrotique[/b][/c], vous ne pouvez pas être [i]Effrayé[/i] par les MV. [b]Vétérance 9 [/b]- [i][b]Contrôle des MV[/b][/i] : vous pouvez le contrôler pendant 1h.",
  3,
);
const EVOCATEUR = passive(
  "Ecole Arcanique Evocateur",
  "[b]Vétérance 3[/b] - [i][b]Façonneur de sorts[/b][/i] : le Mage peut choisir jusqu'à 2 créatures qui seront Immunisées à l'effet de son sort (lui y compris).",
  3,
);
const PALADIN = passive("Santé Divine", "Le Paladin est Immunisé aux Maladies.");

test("RD : Halflin Robuste, Nain des Collines (pluriel normalisé), Tieffelin (Résistance)", () => {
  assert.deepEqual(protectionsMercenaire([HALFLIN], 1), ["RD Poison"]);
  assert.deepEqual(protectionsMercenaire([NAIN], 1), ["RD Poison"]);
  assert.deepEqual(protectionsMercenaire([TIEFFELIN], 1), ["RD Feu"]);
});

test("immunités : Drow (Sommeil) et Paladin (Maladies) ; l'immunité conditionnelle est ignorée", () => {
  assert.deepEqual(protectionsMercenaire([DROW], 1), ["Immunité aux sorts, potions et effets de Sommeil"]);
  assert.deepEqual(protectionsMercenaire([PALADIN], 1), ["Immunité aux Maladies"]);
  assert.deepEqual(protectionsMercenaire([EVOCATEUR], 5), []);
});

test("paliers de vétérance : le RD Nécrotique n'arrive qu'à la vétérance 7", () => {
  assert.deepEqual(protectionsMercenaire([NECRO], 5), []);
  assert.deepEqual(protectionsMercenaire([NECRO], 7), ["RD Nécrotique"]);
});

test("cumul : RD fusionnés sur une ligne, puis immunités, puis vulnérabilités ; rien si rien", () => {
  const vuln = passive("Vulnérable", "- Vulnérabilité au Froid\n- Vulnérable aux sorts de Glace.");
  const foudre = passive("Foudre", "RD Foudre, Tonnerre");
  assert.deepEqual(protectionsMercenaire([TIEFFELIN, foudre, DROW, vuln], 1), [
    "RD Feu, Foudre, Tonnerre",
    "Immunité aux sorts, potions et effets de Sommeil",
    "Vulnérabilité au Froid",
    "Vulnérabilité aux sorts de Glace",
  ]);
  assert.deepEqual(protectionsMercenaire([], 1), []);
});

test("une compétence dont la vétérance n'est pas atteinte, ou active, ne compte pas", () => {
  assert.deepEqual(protectionsMercenaire([{ ...NAIN, veterance: 4 }], 2), []);
  assert.deepEqual(protectionsMercenaire([{ ...NAIN, type: "active" }], 2), []);
});

// Relevés du 2026-10-12.
const DISCIPLINE_FEU = passive(
  "Discipline Elémentaire (Feu)",
  "Vous avez appris à maîtriser l'Elément Feu. De nouvelles compétences actives vont s'ouvrir à vous avec vos progrès de Vétérance. Vous obtenez une RD au [c=#7b3fa0][b]Feu[/b][/c].",
  3,
);
const MAITRE_BETES = passive(
  "Maître des Bêtes",
  "[b]Entraînement exceptionnel[/b]\nÀ partir du niveau 5, l'attaque du compagnon compte dorénavant comme étant magique pour ce qui est des RD ou Immunité aux attaques et aux dégâts non magiques.\n\n[b]Fureur bestiale[/b]\nÀ partir du niveau 8, ...",
  3,
);
const SANTE_DIVINE = passive("Santé Divine", "Le Paladin est Immunisé aux Maladies.", 2);

test("« une RD au Feu » est reconnue (article ignoré)", () => {
  assert.deepEqual(protectionsMercenaire([DISCIPLINE_FEU], 3), ["RD Feu"]);
  assert.deepEqual(protectionsMercenaire([DISCIPLINE_FEU], 2), []);
});

test("« des RD ou Immunité aux attaques non magiques » (cibles du compagnon) n'est pas une immunité du mercenaire", () => {
  assert.deepEqual(protectionsMercenaire([MAITRE_BETES], 10), []);
});

test("Santé Divine : immunité aux Maladies seulement à partir de la vétérance 2", () => {
  assert.deepEqual(protectionsMercenaire([SANTE_DIVINE], 1), []);
  assert.deepEqual(protectionsMercenaire([SANTE_DIVINE], 2), ["Immunité aux Maladies"]);
});
