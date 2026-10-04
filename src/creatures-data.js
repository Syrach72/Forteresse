// Créatures (MJ seul) : listes de valeurs des menus de la fiche, reprises du vocabulaire officiel de
// D&D 5e en français (AideDD n'était pas joignable au moment de l'écriture : à corriger avec Bruno si
// un libellé diffère). Ces listes sont dans le code, pas en base : ce sont des choix fermés.

export const TYPES_CREATURE = [
  "aberration",
  "bête",
  "céleste",
  "créature artificielle",
  "dragon",
  "élémentaire",
  "fée",
  "fiélon",
  "géant",
  "humanoïde",
  "monstruosité",
  "mort-vivant",
  "plante",
  "vase",
];

// Sous-type : suggestions (saisie libre possible).
export const SOUS_TYPES_CREATURE = [
  "changeforme",
  "démon",
  "diable",
  "elfe",
  "gnoll",
  "gnome",
  "gobelinoïde",
  "humain",
  "kobold",
  "nain",
  "orc",
  "titan",
  "yuan-ti",
];

export const TAILLES_CREATURE = [
  ["TP", "Très petite"],
  ["P", "Petite"],
  ["M", "Moyenne"],
  ["G", "Grande"],
  ["TG", "Très grande"],
  ["Gig", "Gigantesque"],
];

export const TYPES_DEGATS = [
  "acide",
  "contondant",
  "feu",
  "force",
  "foudre",
  "froid",
  "nécrotique",
  "perforant",
  "poison",
  "psychique",
  "radiant",
  "tonnerre",
  "tranchant",
  "contondant, perforant et tranchant des armes non magiques",
  "contondant, perforant et tranchant des armes non magiques non argentées",
  "contondant, perforant et tranchant des armes non magiques non adamantines",
];

export const SENS_CREATURE = [
  "perception des vibrations",
  "vision aveugle",
  "vision dans le noir",
  "vision véritable",
];

// États du jeu (ordre alphabétique) : un seul à la fois par créature ou mercenaire. « Épuisé » a trois
// niveaux. La valeur enregistrée en base est `id`.
export const ETATS_JEU = [
  { id: "agrippe", nom: "Agrippé" },
  { id: "assourdi", nom: "Assourdi" },
  { id: "aveugle", nom: "Aveuglé" },
  { id: "charme", nom: "Charmé" },
  { id: "desoriente", nom: "Désorienté" },
  { id: "effraye", nom: "Effrayé" },
  { id: "empoisonne", nom: "Empoisonné" },
  { id: "endormi", nom: "Endormi" },
  { id: "entrave", nom: "Entravé" },
  { id: "epuise", nom: "Épuisé", niveaux: 3 },
  { id: "etourdi", nom: "Étourdi" },
  { id: "fascine", nom: "Fasciné" },
  { id: "inconscient", nom: "Inconscient" },
  { id: "paralyse", nom: "Paralysé" },
  { id: "petrifie", nom: "Pétrifié" },
];
export const nomEtat = (id) => ETATS_JEU.find((e) => e.id === id)?.nom || id;

// Les cinq listes extensibles d'une fiche, dans l'ordre d'affichage.
export const CATEGORIES_CAPACITES = [
  { id: "capacite", label: "Capacités", singulier: "capacité" },
  { id: "action", label: "Actions", singulier: "action" },
  { id: "action_bonus", label: "Actions bonus", singulier: "action bonus" },
  { id: "reaction", label: "Réactions", singulier: "réaction" },
  { id: "legendaire", label: "Actions légendaires", singulier: "action légendaire" },
];

export const EMPLACEMENTS_ICONES = 12;

export function creatureVide() {
  return {
    nom: "",
    type: "",
    sous_type: "",
    taille: "",
    sante_max: "1",
    energie_max: "0",
    vitesse: "0",
    fp: "0",
    puissance: "0",
    velocite: "0",
    mental: "0",
    esquive: "",
    parade: "",
    armure: "",
    vulnerabilites: [],
    resistances: [],
    immunites_degats: [],
    immunites_etats: [],
    sens: [],
    description: "",
  };
}

// Entier borné, texte vide -> min.
export function entier(v, min, max) {
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n)) return min;
  return Math.min(max, Math.max(min, n));
}
