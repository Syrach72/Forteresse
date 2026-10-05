export const INITIAL_DORMITORY = {
  capacity: 6,
  beds: [
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
  ],
};
// Lits du Dortoir : 6 débloqués au départ, les 12 autres se débloquent DANS
// L'ORDRE contre des pièces d'or de la trésorerie commune (règle de Bruno) :
// 100 Po les 3 premiers (lits 7 à 9), 150 Po les 3 suivants, 200 Po les 3 d'après
// et 300 Po les 3 derniers. `slot` = indice du lit (0 à 17). Renvoie null pour
// un lit déjà débloqué au départ ou hors du dortoir. Le serveur applique la même
// grille (fonction dortoir_debloquer_place).
export const LITS_DORTOIR_DEPART = 6;
export const LITS_DORTOIR_MAX = 18;
export const PRIX_LITS_DORTOIR = [100, 150, 200, 300];
export function prixLitDortoir(slot) {
  if (!Number.isInteger(slot) || slot < LITS_DORTOIR_DEPART || slot >= LITS_DORTOIR_MAX)
    return null;
  return PRIX_LITS_DORTOIR[Math.floor((slot - LITS_DORTOIR_DEPART) / 3)];
}
// Premier lit débloqué et libre du dortoir (indice), ou -1 s'il n'y en a pas :
// les lits occupés et les lits verrouillés (au-delà de la capacité) ne comptent pas.
export function firstFreeBed(dorm) {
  return dorm.beds.slice(0, dorm.capacity).findIndex((b) => !b);
}

// Dortoir PARTAGÉ : le lit d'un mercenaire est attribué par la base à son
// recrutement (premier lit libre) et lui reste jusqu'à son renvoi de la
// compagnie. `rows` = lignes de recrutement { mercenaire_id, lit }, `places` =
// nombre de lits débloqués (6, ou 7 après déblocage).
export function buildDorm(rows = [], places = 6) {
  const state = structuredClone(INITIAL_DORMITORY);
  state.capacity = Math.max(6, Math.min(state.beds.length, Number(places) || 6));
  for (const r of rows)
    if (r.lit >= 0 && r.lit < state.beds.length)
      state.beds[r.lit] = { heroId: r.mercenaire_id, remaining: 0 };
  return state;
}

// Lits de l'infirmerie : 2 libres au départ, les 4 autres se débloquent DANS
// L'ORDRE (administrateur seul) pour 300, 500, 800 puis 1200 Po (règle de Bruno).
// `slot` = indice du lit (0 à 5) ; null pour un lit déjà libre ou hors infirmerie.
// Le serveur applique la même grille (fonction infirmerie_debloquer_place).
export const PRIX_LITS_INFIRMERIE = [300, 500, 800, 1200];
export function prixLitInfirmerie(slot) {
  if (!Number.isInteger(slot)) return null;
  return PRIX_LITS_INFIRMERIE[slot - 2] ?? null;
}
export const INITIAL_INFIRMARY = {
  capacity: 2,
  beds: [null, null, null, null, null, null],
};
// Soins (règle de Bruno) : chaque instance rend un tiers de la santé max (arrondi au-dessus) ; le
// mercenaire quitte l'infirmerie à sa santé max. Instances nécessaires = santé perdue / tiers,
// minimum 1 à l'arrivée. Santé max = 3 + 2 × Puissance (règle de Bruno, 2026-09-28). Le serveur
// applique la même règle (fonctions _sante_max, _soins_instances et infirmerie_soigner) : ce
// calcul ne sert qu'à l'affichage.
// Santé max d'un mercenaire et blessure : santé actuelle renseignée et inférieure au maximum
// (vide = maximum).
export function santeMaxMerc(merc) {
  return 3 + 2 * ((merc?.puissance ?? 0) + (merc?.bonusPuissance ?? 0)) + (merc?.bonusSante ?? 0);
}
export function estBlesse(merc) {
  return merc?.santeActuelle != null && merc.santeActuelle < santeMaxMerc(merc);
}
// À 0 PV : la tête de mort remplace le cœur.
export function estAZero(merc) {
  return merc?.santeActuelle != null && merc.santeActuelle <= 0;
}
// Effets de sang sur la fiche : 1 dès que le mercenaire est blessé, 2 à partir d'un tiers de la santé max
// perdu, 3 au-delà des deux tiers.
export function niveauSang(merc) {
  const max = santeMaxMerc(merc);
  if (merc?.santeActuelle == null || max <= 0) return 0;
  const perdu = max - Math.max(0, merc.santeActuelle);
  if (perdu <= 0) return 0;
  if (perdu * 3 > 2 * max) return 3;
  return perdu * 3 >= max ? 2 : 1;
}
export function instancesDeSoins(merc) {
  if (!merc) return 1;
  const max = santeMaxMerc(merc);
  const actuelle = Math.max(0, Math.min(merc.santeActuelle ?? max, max));
  return Math.max(1, Math.ceil((max - actuelle) / Math.ceil(max / 3)));
}
// Infirmerie PARTAGÉE (tables infirmerie_place / infirmerie_reglage) : état
// d'affichage à partir des lignes de la base. `places` = lignes
// { position, mercenaire_id, restant }, `capacity` = lits débloqués (2 ou 3).
export function buildInfirmary(places = [], capacity = 2) {
  const state = structuredClone(INITIAL_INFIRMARY);
  state.capacity = Math.max(2, Math.min(6, Number(capacity) || 2));
  for (const p of places)
    if (p.position >= 0 && p.position < state.beds.length)
      state.beds[p.position] = { heroId: p.mercenaire_id, remaining: p.restant };
  return state;
}
