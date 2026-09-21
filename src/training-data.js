// Terrain d'entraînement PARTAGÉ (tables entrainement_place et
// entrainement_reglage, visibles par tous les joueurs). Règles confirmées par
// Bruno, appliquées par les fonctions serveur (voir la migration
// 20260921100000_entrainement.sql) ; ce fichier ne sert qu'à afficher l'état et
// à ne proposer que des choix valides :
// - pas d'élève sans instructeur ;
// - l'élève est de la même classe que l'instructeur, qui a au moins 3 points de
//   vétérance de plus que lui ;
// - à chaque +1 Instance (administrateur), l'élève gagne 1 point de vétérance ;
//   arrivé à celle de l'instructeur, il retourne au dortoir ;
// - un joueur peut renvoyer son élève avant (il garde son niveau) ;
// - l'instructeur reste en place jusqu'à ce qu'on le renvoie.
// Un participant est { heroId } : la vétérance vit sur le mercenaire (base).
export const VETERANCE_ECART = 3;
export const INITIAL_TRAINING = {
  instructor: null,
  students: [null, null, null],
  capacity: 1,
  secondGroup: false,
};
export function trainingIds(state) {
  return [state.instructor, ...state.students]
    .filter(Boolean)
    .map((x) => x.heroId);
}
// État d'affichage à partir des lignes de la base : `places` = lignes
// { role: "instructeur" | "eleve", position, mercenaire_id }, `placesEleves` =
// nombre de places élèves débloquées (1 à 3).
export function buildTraining(places = [], placesEleves = 1) {
  const state = structuredClone(INITIAL_TRAINING);
  state.capacity = Math.max(1, Math.min(3, Number(placesEleves) || 1));
  for (const p of places) {
    if (p.role === "instructeur") state.instructor = { heroId: p.mercenaire_id };
    else if (p.position >= 0 && p.position < state.students.length)
      state.students[p.position] = { heroId: p.mercenaire_id };
  }
  return state;
}
const classe = (w) => (w?.role || "").trim().toLowerCase();
// Raison pour laquelle `candidat` ne peut pas être l'élève de `instructeur`
// (objets { id, role, veterancy }), ou null s'il peut l'être.
export function studentBlocker(instructeur, candidat) {
  if (!instructeur) return "Choisissez d’abord un instructeur.";
  if (!candidat) return "Mercenaire inconnu.";
  if (candidat.id === instructeur.id)
    return "Un instructeur ne peut pas être son propre élève.";
  if (!classe(candidat) || classe(candidat) !== classe(instructeur))
    return "L’élève doit être de la même classe que l’instructeur.";
  if (instructeur.veterancy - candidat.veterancy < VETERANCE_ECART)
    return `L’instructeur doit avoir au moins ${VETERANCE_ECART} points de vétérance de plus que l’élève.`;
  return null;
}
// Parmi `candidats` (les mercenaires du joueur), ceux qui peuvent être élèves
// de `instructeur` : libres (ni à l'entraînement ni ailleurs, `absents` =
// identifiants) et conformes aux règles de classe et de vétérance.
export function eligibleStudents(candidats, instructeur, state, absents = []) {
  if (!instructeur) return [];
  const pris = new Set([...trainingIds(state), ...absents]);
  return candidats.filter(
    (w) => !pris.has(w.id) && studentBlocker(instructeur, w) === null,
  );
}
