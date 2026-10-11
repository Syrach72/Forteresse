// Expérience et vétérance (Bruno, 2026-10-11). Règles pures, miroir des fonctions SQL `_xp_palier`,
// `_xp_gain_quete` et `_xp_formation_instances` (migration 20261011100000) : le serveur fait foi, ce module sert
// à l'affichage (barres d'XP, instances restantes d'une formation).

export const VETERANCE_MAX = 10;

// XP à gagner pour passer du niveau n au suivant (le niveau 10 n'a plus de palier).
const PALIERS = { 1: 20, 2: 20, 3: 30, 4: 30, 5: 40, 6: 40, 7: 50, 8: 60, 9: 70 };

export function xpPalier(vet) {
  return PALIERS[vet] ?? null;
}

// XP d'une quête réussie selon l'écart FP − vétérance ; seul le FP compte, pas la durée de la quête.
export function xpGainQuete(fp, vet) {
  const ecart = fp - vet;
  if (ecart >= 2) return 15;
  if (ecart === 1) return 12;
  if (ecart === 0) return 10;
  if (ecart === -1) return 6;
  if (ecart === -2) return 3;
  return 0;
}

// Quête échouée : le quart du gain normal, arrondi à l'inférieur.
export function xpGainEchec(fp, vet) {
  return Math.floor(xpGainQuete(fp, vet) / 4);
}

// Instances d'entraînement nécessaires pour gagner un niveau, selon l'écart instructeur − élève.
export function instancesParNiveau(ecart) {
  if (ecart >= 3) return 1;
  if (ecart === 2) return 2;
  return 3;
}

// XP reçu par instance d'entraînement (part du palier, arrondie au supérieur).
export function xpFormationParInstance(vetEleve, vetInstructeur) {
  const palier = xpPalier(vetEleve);
  if (palier == null || vetInstructeur <= vetEleve) return 0;
  return Math.ceil(palier / instancesParNiveau(vetInstructeur - vetEleve));
}

// Nombre d'instances qu'il reste à un élève (niveau `vet`, `xp` déjà acquis dans ce niveau) pour atteindre le
// niveau de son instructeur. L'écart diminue à mesure qu'il monte : les derniers niveaux sont les plus lents.
export function instancesRestantesFormation(vet, xp, vetInstructeur) {
  let niveau = vet;
  let acquis = xp || 0;
  let instances = 0;
  // Simulation instance par instance, comme le serveur : l'excédent d'XP est reporté au niveau suivant.
  while (niveau < vetInstructeur && xpPalier(niveau) != null && instances < 200) {
    acquis += xpFormationParInstance(niveau, vetInstructeur);
    instances += 1;
    while (xpPalier(niveau) != null && acquis >= xpPalier(niveau)) {
      acquis -= xpPalier(niveau);
      niveau += 1;
    }
  }
  return instances;
}
