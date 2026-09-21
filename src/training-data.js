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
// Deux groupes d'instruction. Le premier est à la racine de l'état ; le second
// (`second`) est bloqué au départ : son instructeur se débloque pour 1000 Po,
// ses places d'élèves 2 et 3 pour 300 Po chacune (administrateur seul, comme
// tous les déblocages).
export const PRIX_PLACE_ELEVE = { 1: 100, 2: 300 };
export const PRIX_INSTRUCTEUR_GROUPE_2 = 1000;
export const INITIAL_TRAINING = {
  instructor: null,
  students: [null, null, null],
  capacity: 1,
  second: {
    unlocked: false,
    instructor: null,
    students: [null, null, null],
    capacity: 1,
  },
};
export function trainingIds(state) {
  return [
    state.instructor,
    ...state.students,
    state.second?.instructor,
    ...(state.second?.students || []),
  ]
    .filter(Boolean)
    .map((x) => x.heroId);
}
// Numéro de groupe (1 ou 2) où se trouve ce mercenaire à titre d'instructeur,
// ou null.
export function groupOfInstructor(state, id) {
  if (state.instructor?.heroId === id) return 1;
  if (state.second?.instructor?.heroId === id) return 2;
  return null;
}
// Premier groupe capable d'accueillir un nouvel instructeur : débloqué et sans
// instructeur en place ; null s'il n'y en a pas.
export function freeInstructorGroup(state) {
  if (!state.instructor) return 1;
  if (state.second?.unlocked && !state.second.instructor) return 2;
  return null;
}
const bornePlaces = (n) => Math.max(1, Math.min(3, Number(n) || 1));
// État d'affichage à partir des lignes de la base : `places` = lignes
// { groupe, role: "instructeur" | "eleve", position, mercenaire_id } (groupe 1
// par défaut), `placesEleves` = places élèves débloquées du groupe 1 (1 à 3),
// `reglage2` = { groupe2_debloque, places_eleves_2 } pour le second groupe.
export function buildTraining(places = [], placesEleves = 1, reglage2 = {}) {
  const state = structuredClone(INITIAL_TRAINING);
  state.capacity = bornePlaces(placesEleves);
  state.second.unlocked = !!reglage2?.groupe2_debloque;
  state.second.capacity = bornePlaces(reglage2?.places_eleves_2);
  for (const p of places) {
    const g = p.groupe === 2 ? state.second : state;
    if (p.role === "instructeur") g.instructor = { heroId: p.mercenaire_id };
    else if (p.position >= 0 && p.position < g.students.length)
      g.students[p.position] = { heroId: p.mercenaire_id };
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
