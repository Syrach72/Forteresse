// États cumulables (Bruno, 2026-10-12) : jusqu'à trois états en même temps, chacun avec ses rounds. Une liste est
// un tableau ordonné [{ etat, niveau, rounds }] : le premier élément est l'état « principal » (colonnes historiques,
// qui portent la logique Inconscient / mort sur le champ de bataille), les suivants sont les états supplémentaires
// (table etat_supplementaire). L'Inconscient est donc toujours le premier.
export const MAX_ETATS = 3;

// Liste complète d'une cible à partir de son état principal et de ses états supplémentaires.
export function listeEtats(principal, supplementaires = []) {
  const liste = [];
  if (principal?.etat) liste.push({ etat: principal.etat, niveau: principal.niveau ?? 1, rounds: principal.rounds ?? 0 });
  for (const s of [...supplementaires].sort((a, b) => (a.position ?? 0) - (b.position ?? 0))) {
    if (s?.etat) liste.push({ etat: s.etat, niveau: s.niveau ?? 1, rounds: s.rounds ?? 0 });
  }
  return liste.slice(0, MAX_ETATS);
}

// Clic sur un état : le retire s'il est présent, sinon l'ajoute (trois au maximum).
// Retourne { liste } ou { erreur }.
export function basculerEtat(liste, id) {
  if (liste.some((e) => e.etat === id)) return { liste: liste.filter((e) => e.etat !== id) };
  if (liste.length >= MAX_ETATS) {
    return { erreur: "Trois états au maximum en même temps : retirez-en un d’abord." };
  }
  const nouveau = { etat: id, niveau: 1, rounds: 0 };
  // L'Inconscient prend la place de l'état principal : le serveur y attache ses règles (3 rounds avant la mort).
  return { liste: id === "inconscient" ? [nouveau, ...liste] : [...liste, nouveau] };
}

export function definirNiveau(liste, id, niveau) {
  return liste.map((e) => (e.etat === id ? { ...e, niveau } : e));
}

export function definirRounds(liste, id, rounds) {
  return liste.map((e) => (e.etat === id ? { ...e, rounds } : e));
}

// Découpe pour l'enregistrement : état principal (ou null) et états supplémentaires.
export function decouper(liste) {
  return { principal: liste[0] ?? null, supplementaires: liste.slice(1, MAX_ETATS) };
}
