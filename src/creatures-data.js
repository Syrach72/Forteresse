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
// `positif` : effet favorable (vert quand actif) ; `bleu` : bleu quand actif ; sinon rouge.
export const ETATS_JEU = [
  { id: "a_terre", nom: "À Terre" },
  { id: "abri_partiel", nom: "Abri Partiel", positif: true },
  { id: "abri_total", nom: "Abri Total", positif: true },
  { id: "affaibli", nom: "Affaibli" },
  { id: "agrippe", nom: "Agrippé" },
  { id: "assourdi", nom: "Assourdi" },
  { id: "aveugle", nom: "Aveuglé" },
  { id: "charme", nom: "Charmé" },
  { id: "concentration", nom: "Concentration", bleu: true },
  { id: "confus", nom: "Confus" },
  { id: "desoriente", nom: "Désorienté" },
  { id: "effraye", nom: "Effrayé" },
  { id: "empoisonne", nom: "Empoisonné" },
  { id: "endormi", nom: "Endormi" },
  { id: "enrage", nom: "Enragé" },
  { id: "entrave", nom: "Entravé" },
  { id: "epuise", nom: "Épuisé", niveaux: 3 },
  { id: "etourdi", nom: "Étourdi" },
  { id: "fascine", nom: "Fasciné" },
  { id: "fatigue", nom: "Fatigué" },
  { id: "flou", nom: "Flou" },
  { id: "immobilise", nom: "Immobilisé" },
  { id: "inconscient", nom: "Inconscient" },
  { id: "lenteur", nom: "Lenteur" },
  { id: "muet", nom: "Muet" },
  { id: "nauseeux", nom: "Nauséeux" },
  { id: "paralyse", nom: "Paralysé" },
  { id: "petrifie", nom: "Pétrifié" },
  { id: "possede", nom: "Possédé" },
  { id: "suffocation", nom: "Suffocation" },
];
// Détail de chaque état, ouvert par le badge « ? » au-dessus du bouton actif (à rédiger : id -> texte).
export const DETAIL_ETATS = {
  abri_partiel: "Abri Partiel (1/2 du corps protégé) : Attaquant Désavantagé,",
  abri_total: "Abri Total : ciblage direct impossible, mais certains effets de zone contournent l’abri.",
  affaibli: "Affaibli : Vitesse 1/2, de base, course impossible, Désavantage Sauv. et actions utilisant Puissance.",
  agrippe:
    "Agrippé : La vitesse de la créature passe à 0 (elle se déplace automatiquement avec celle qui l'a Agrippée). Elle peut se libérer en dépensant une Action Bonus et en réussissant un jet de Puissance en opposition. Une créature Agrippée se bat normalement contre celle qui la maintient, mais avec Désavantage contre les autres créatures à sa portée.",
  assourdi: "Assourdi : les jets nécessitant l’Ouïe échouent. Lancer des sorts à composante Vocale est Désavantagé.",
  a_terre:
    "A Terre : La créature ne peut que ramper (1c en coûte 2 ; 3 si Terrain difficile) ; se relever coûte la moitié du déplacement de base ou une Action Bonus. Les attaques au CàC contre une créature au sol Avantagées, celles à plus d’une case sont Désavantagées. Attaquer depuis le sol est possible, avec un Désavantage (y compris les sorts nécessitant une composante Somatique).",
  aveugle:
    "Aveuglé : Tout test ou Sauvegarde nécessitant la vue échoue. Les attaques contre une créature Aveuglée sont Avantagées. Les attaques de la créature Aveuglée sont Désavantagées contre une cible ne s'étant pas déplacée, sinon, elles échouent automatiquement. Cela n'affecte pas la Perception des Vibrations, la Vision aveugle ou d’autres formes de repérage. Repérer une cible par l’Ouïe ou l’Odorat nécessite un jet de Perception vs Discrétion.",
  charme:
    "Charmé : Ne peut ni attaquer, ni cibler la source avec des effets nuisibles. La source est Avantagée à ses jets pour contraindre la victime à obéir. Le Charme est rompu par des dégâts provenant de la source ou ses alliés.",
  concentration:
    "Concentration : La Concentration doit être testée à chaque fois que la créature subit des dégâts. Elle est perdue si la créature effectue un jet de Puissance inférieur aux dégâts reçus. La Concentration est automatiquement perdue sous les états Désorienté, Paralysé, Pétrifié, Inconscient, Confus, Etourdi, Effrayé, Enragé.",
  confus:
    "Confus (D10) : 1 : Direction aléatoire à vitesse de base complète. Pas autre Action. 2-6 : ni Déplacement ni Action. 7-8 : prend son action pour faire une attaque au CàC contre une créature aléatoire la plus proche à sa portée, sinon ne fait rien. 9-10 : pas affecté.",
  desoriente:
    "Désorienté : Si elle décide de se déplacer, la créature effectue un mouvement aléatoire (direction et distance). Perte de toute Réaction et Concentration.",
  effraye:
    "Effrayé : Désavantage aux jets d’attaque et tests de capacité tant que la source de la Peur est dans le champ de vision de la créature Effrayée. Impossibilité de se déplacer volontairement vers la cible.",
  empoisonne: "Empoisonné (poison générique) : Désavantage jets de Puissance.",
  endormi:
    "Endormi : La créature tombe Inconsciente mais ne perd aucun PV. Elle dort jusqu'à ce qu'une créature la bouscule ou lui inflige un ou plusieurs Pts de dégâts.",
  enrage:
    "Enragé : Une créature Enragée Fonce vers la cible des dégâts ou du critique qu’elle a subi (au premier Rd), puis se dirige et attaque la créature la plus proche (ennemi ou allié) au mépris de sa propre sécurité. Les attaques contre elle sont Avantagées, ses Sauvegardes Mental sont Désavantagées. Elle ne peut ni se Concentrer, ni lancer de Sorts. Elle ne peut utiliser que ses attaques de base au CàC et perd toute Action Bonus. Ses attaques effectuées avec la Carac. Puissance obtiennent un Avantage et +1 🎲. A la fin de l’état, la créature est Epuisée niv.1 pendant 1Rd. Mettre fin à l’état Enragé se fait en réussissant au début de chacun de ses tours une Sauvegarde Mental (obligatoire) dont le résultat doit être supérieur à la valeur Carac. Puissance. En tout état de cause, l’Enragement ne peut durer plus de 3 Rds.",
  entrave:
    "Entravé : Vitesse 0 ; Désavantage jets Vélocité et tous les jets d’attaques avec Arme ou Sort nécessitant un composant Somatique. Les attaques contre une créature Entravée sont Avantagées.",
  epuise:
    "Épuisé : chaque niveau cumule ses effets avec les niveaux précédents :\n- 1 niveau d’Epuisement : Désavantage aux jets liés à Puissance et Vélocité. \n- 2 nvx : La créature perd 50% des PV actuels (PV restant arrondis supérieurs).\n- 3 nvx : La créature perd à nouveau 50% des PV restants et devient Désavantage aux jets liés à la Carac. Mental. Si la créature devait à nouveau subir un niveau d’Epuisement, elle tombe Inconsciente à 0PV.",
  etourdi:
    "Etourdi : Ne peut ni Agir, ni Réagir. Ne peut pas se déplacer et bégaye. Les Sauvegardes Puissance et Vélocité sont des échecs automatiques. Les attaques contre la créature sont Avantagées.",
  fascine:
    "Fasciné : La créature utilise son prochain tour pour se déplacer au maximum de sa vitesse vers la source de sa Fascination, afin de l'adorer et de la protéger, mais elle n'obéit à aucun de ses ordres. L’effet est rompu si la créature subit des dégâts de n’importe quelle source.",
  fatigue: "Fatigué : Désavantage incompressible aux tests Athlétisme et Acrobatie.",
  flou: "Flou : Les attaques utilisant la vue, contre une créature sous effet Flou, sont Désavantagées.",
  immobilise: "Immobilisé : Vitesse 0 ; seule Action possible : tenter de se Libérer (avec Désavantage).",
  inconscient:
    "Inconscient : La créature tombe A Terre, lâche tout ce qu'elle tient, ne peut pas bouger, ne parle pas, et ne perçoit rien. Échecs automatiques des Sauvegardes. Les attaques contre la créature sont résolues comme A Terre, mais si l’attaquant est à 1c ou moins, Critique automatique du premier 🎲 qui touche.",
  lenteur:
    "Lenteur : Vitesse 1/2, Adversaire Avantagé à ses attaques utilisant Vélocité, créature Désavantagée à sa propre Vélocité, pas de Réaction, une seule Action ou Action Bonus, une seule attaque par tour. ",
  muet: "Muet : Sorts à composante Vocale impossibles à lancer, communication limitée aux gestes, écriture, ou télépathie.",
  nauseeux: "Nauséeux, Fiévreux, Ivre, Engourdi... : Tous jets sont Désavantagés et Mouvement 1/2.",
  paralyse:
    "Paralysé : Ne peut ni bouger ni parler. Échecs automatiques aux Sauvegardes Puissance et Vélocité. Attaques contre la créature Avantagées et Critique automatique si attaquant à 1c ou moins.",
  petrifie:
    "Pétrifié : Transformé en substance inanimée, poids x10, cesse de vieillir. Incapable de bouger et parler, perception impossible. Échecs automatiques de toutes Sauvegardes.",
  possede:
    "Possédé : La créature est contrôlée par une entité dont elle devient l’incarnation. Elle répond aux ordres de son Possesseur et n’a plus aucune volonté propre. Contrairement à l’état Charmé, un Possédé peut se mettre en danger. Un Exorcisme réussi ou un sort de Délivrance des Malédictions met fin à son état. Le jet est fait en opposition avec la Carac. Mentale de celui qui contrôle le Possédé.",
  suffocation:
    "Suffocation : Une créature non « stressée » (nage sous l’eau tranquille par exemple) retient sa respiration autant de Rd que sa valeur de Carac. Puissance. Mais si elle est en condition de stress (attaque étranglement, etc.), cette valeur est réduite à 1/3 de la Carac. Puissance (avec minimum 3Rds). Au-delà de ce délai, la créature tombe Inconsciente et à 0PV.",
};
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
