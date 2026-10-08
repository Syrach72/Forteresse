// Effets temporaires des missions (cadeaux individuels) : bonus qui s'appliquent tant que le mercenaire est
// engagé dans une quête, pour 1 à 3 quêtes. Le serveur applique les caractéristiques et les maxima
// (fonctions _effet_temp, _puissance, _sante_max…) ; ce fichier sert à l'affichage.
export const STATS_EFFET = [
  ["puissance", "Puissance"],
  ["velocite", "Vélocité"],
  ["mental", "Mental"],
  ["mouvement", "Mouvement"],
  ["sante_max", "Santé max"],
  ["energie_max", "Énergie max"],
  ["pv_temp", "PV temporaires"],
];

export function libelleEffet(stat, valeur, quetes = 1) {
  if (stat === "pv_temp") return `${valeur} PV temporaires (jusqu’à la fin de la prochaine quête)`;
  const nom = STATS_EFFET.find(([k]) => k === stat)?.[1] || stat;
  return `+${valeur} ${nom} pendant ${quetes} quête${quetes > 1 ? "s" : ""}`;
}

// Sommes des effets actifs (mercenaire en quête) par caractéristique ; {} si rien d'actif.
export function effetsTemp(effets, actif) {
  const t = { puissance: 0, velocite: 0, mental: 0, mouvement: 0, santeMax: 0, energieMax: 0, pvTemp: 0 };
  if (!actif) return t;
  for (const e of effets) {
    const cle = { sante_max: "santeMax", energie_max: "energieMax", pv_temp: "pvTemp" }[e.stat] || e.stat;
    t[cle] = (t[cle] || 0) + e.valeur;
  }
  return t;
}
