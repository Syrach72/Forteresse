import { useState } from "react";
import { ReferenceCrop } from "./Characters.jsx";
import { VetBadge } from "./VetBadge.jsx";
import {
  PRIX_INSTRUCTEUR_GROUPE_2,
  PRIX_PLACE_ELEVE,
  VETERANCE_ECART,
  eligibleStudents,
} from "./training-data.js";
// Terrain d'entraînement PARTAGÉ : visible par tous les joueurs. Un instructeur
// (choisi depuis la fiche du mercenaire, au Dortoir) et des élèves (choisis
// ici, dans « Choisir un élève »).
// - people : tous les mercenaires de la compagnie (pour afficher les
//   participants de chacun) ;
// - warriors : ceux du joueur connecté, les seuls qu'il peut placer ou renvoyer
//   (l'administrateur peut tout renvoyer).
// Deux groupes d'instruction (1 = ligne du haut, 2 = ligne du bas, bloquée au
// départ). Tous les déblocages (place d'élève : 100 Po au premier groupe, 300 Po
// au second ; instructeur du second groupe : 1000 Po) sont réservés à
// l'administrateur (`estAdmin`, vérifié aussi par le serveur) ; les joueurs
// voient les cellules verrouillées et leur prix.
// Les règles sont vérifiées par le serveur (migrations 20260921100000 et
// 20260921160000) ; ici on ne propose que des choix valides.
export function Training({
  training,
  people,
  warriors,
  absents = [],
  estAdmin = false,
  gold,
  onChoose,
  onSendBack,
  onUnlock,
  onUnlockGroup,
  Modal,
}) {
  // popup : { role: "instructor" | "student" | "unlock" | "unlock-group", index, group }
  const [popup, setPopup] = useState(null);
  const [error, setError] = useState("");
  // Une action serveur est en cours : évite les doubles clics.
  const [enCours, setEnCours] = useState(false);
  const hero = (person) => people.find((w) => w.id === person?.heroId);
  const groupe = (g) => (g === 2 ? training.second : training);
  const peutRenvoyer = (w) => estAdmin || warriors.some((x) => x.id === w?.id);
  // Lance une action serveur ; ferme la fenêtre si elle réussit, sinon affiche
  // l'erreur renvoyée.
  async function agir(action) {
    setEnCours(true);
    setError("");
    const result = await action();
    setEnCours(false);
    if (result?.error) setError(result.error);
    else close();
  }
  const close = () => {
    setPopup(null);
    setError("");
  };
  const ouvrir = (next) => {
    setError("");
    setPopup(next);
  };
  // Cellule d'instructeur ou d'élève du groupe `g`. `cellKey` seulement pour
  // les élèves (l'instructeur est déjà seul dans la grille, sans .map()).
  function portrait(person, role, index, g, cellKey) {
    const w = hero(person);
    const isInstructor = role === "instructor";
    const instr = hero(groupe(g).instructor);
    // Pas d'élève tant qu'aucun instructeur n'est en place.
    const blocked = !isInstructor && !w && !instr;
    const noun = isInstructor ? "instructeur" : "élève";
    return (
      <button
        key={cellKey}
        className={`training-place parchment ${isInstructor ? "instructor-place" : ""} ${blocked ? "training-blocked" : ""} ${w ? "training-occupied" : ""}`}
        disabled={blocked}
        aria-label={
          w
            ? `${isInstructor ? "Instructeur" : "Élève"} ${w.name}, vétérance ${w.veterancy}`
            : blocked
              ? "Élève : choisissez d’abord un instructeur"
              : `Choisir un ${noun}`
        }
        onClick={() => ouvrir({ role, index, group: g })}
      >
        {w ? (
          <>
            <VetBadge className="training-duration" value={w.veterancy} />
            <ReferenceCrop crop={w.portrait} />
            <strong>{w.name}</strong>
          </>
        ) : (
          <span>
            {blocked ? "Choisissez d’abord un instructeur" : `Choisir un ${noun}`}
          </span>
        )}
        <small>
          {isInstructor
            ? "Instructeur"
            : w && instr
              ? `Élève · objectif ${instr.veterancy}`
              : "Élève"}
        </small>
      </button>
    );
  }
  // Cellule verrouillée : cadenas et prix ; cliquable (déblocage pour
  // l'administrateur, explication pour les joueurs).
  function verrouillee({ key, aria, libelle, prix, popup: cible, instructeur = false }) {
    return (
      <button
        key={key}
        className={`training-place parchment training-locked ${instructeur ? "instructor-place" : ""}`}
        aria-label={aria}
        onClick={() => ouvrir(cible)}
      >
        <span className="training-padlock" aria-hidden="true">
          <img src="/assets/icons/lock.png" alt="" />
        </span>
        <span>{libelle}</span>
        <strong>{prix} Po</strong>
        <small>{estAdmin ? "Débloquer" : "Verrouillé"}</small>
      </button>
    );
  }
  // Bouton « Renvoyer au dortoir » (recruteur ou administrateur), sinon
  // l'explication.
  function renvoi(w, role, index, g) {
    if (!peutRenvoyer(w))
      return (
        <p className="muted">
          Ce mercenaire appartient à un autre joueur : seul son recruteur peut
          le renvoyer au dortoir.
        </p>
      );
    return (
      <button
        className="primary"
        disabled={enCours}
        onClick={() => agir(() => onSendBack(role, index, g))}
      >
        Renvoyer au dortoir
      </button>
    );
  }
  // Fenêtre d'un déblocage : administrateur seul, sinon simple explication.
  function deblocage({ texte, prix, action }) {
    if (!estAdmin)
      return (
        <p>
          {texte} Seul le maître du jeu peut débloquer cet emplacement
          ({prix} Po).
        </p>
      );
    return (
      <>
        <p>{texte}</p>
        <p>
          Solde actuel : {gold} Po · Après déblocage : {Math.max(0, gold - prix)} Po
        </p>
        <button
          className="primary"
          disabled={gold < prix || enCours}
          onClick={() => agir(action)}
        >
          Débloquer pour {prix} Po
        </button>
        {gold < prix && <p className="error">Trésorerie insuffisante.</p>}
      </>
    );
  }
  // Contenu de la fenêtre selon la cellule cliquée.
  function content() {
    const g = popup.group || 1;
    const G = groupe(g);
    const instructor = hero(G.instructor);
    if (popup.role === "unlock")
      return deblocage({
        texte: `Ajouter une place d’élève débite ${PRIX_PLACE_ELEVE[g]} Po de la trésorerie de la compagnie.${popup.index !== G.capacity ? " Les places se débloquent dans l’ordre." : ""}`,
        prix: PRIX_PLACE_ELEVE[g],
        action: () => onUnlock(g),
      });
    if (popup.role === "unlock-group")
      return deblocage({
        texte: `Débloquer le second groupe d’instruction (son instructeur) débite ${PRIX_INSTRUCTEUR_GROUPE_2} Po de la trésorerie de la compagnie.`,
        prix: PRIX_INSTRUCTEUR_GROUPE_2,
        action: () => onUnlockGroup(),
      });
    if (popup.role === "instructor") {
      if (!instructor)
        return (
          <>
            <p>
              L’instructeur se choisit depuis la fiche d’un mercenaire du
              Dortoir : ouvrez sa fiche et cliquez sur « Instructeur ».
            </p>
            <a className="primary" href="#dortoirs" onClick={close}>
              Aller au Dortoir
            </a>
          </>
        );
      const eleves = G.students.filter(Boolean).length;
      return (
        <>
          <p>
            {instructor.name} · {instructor.role || "classe non renseignée"} ·
            vétérance {instructor.veterancy}. Il reste en place jusqu’à ce que
            son recruteur le renvoie.
          </p>
          {eleves > 0 && (
            <p>
              Le renvoyer ramène aussi ses {eleves} élève{eleves > 1 ? "s" : ""}{" "}
              au dortoir, avec leur niveau actuel.
            </p>
          )}
          {renvoi(instructor, "instructor", 0, g)}
        </>
      );
    }
    // Élève
    const w = hero(G.students[popup.index]);
    if (w)
      return (
        <>
          <p>
            {w.name} · vétérance {w.veterancy}
            {instructor ? ` sur ${instructor.veterancy}` : ""}. Il gagne 1
            niveau à chaque instance et retourne au dortoir dès qu’il atteint la
            vétérance de son instructeur.
          </p>
          <p>Il peut être renvoyé avant : il garde le niveau déjà acquis.</p>
          {renvoi(w, "student", popup.index, g)}
        </>
      );
    const candidats = eligibleStudents(warriors, instructor, training, absents);
    if (!candidats.length)
      return (
        <p>
          Aucun de vos mercenaires ne peut être l’élève de {instructor?.name}.
          Il doit être de la classe {instructor?.role || "de l’instructeur"},
          avoir au moins {VETERANCE_ECART} points de vétérance de moins que lui
          (l’instructeur en a {instructor?.veterancy}) et être disponible au
          dortoir.
        </p>
      );
    return (
      <div className="rest-form">
        <p>
          Vos mercenaires de classe {instructor?.role || "de l’instructeur"} et
          de vétérance {(instructor?.veterancy ?? 0) - VETERANCE_ECART} ou moins :
        </p>
        {candidats.map((c) => (
          <button
            className="wood-button"
            key={c.id}
            disabled={enCours}
            onClick={() => agir(() => onChoose(popup.index, c.id, g))}
          >
            {c.name} · vétérance {c.veterancy}
          </button>
        ))}
      </div>
    );
  }
  // Une ligne d'instruction : l'instructeur puis ses trois places d'élèves.
  function cohorte(g) {
    const G = groupe(g);
    const instructeurBloque = g === 2 && !G.unlocked;
    return (
      <div
        className={`training-cohort ${g === 2 ? "training-cohort-second" : ""}`}
        role="group"
        aria-label={`Groupe d’instruction ${g}`}
      >
        {instructeurBloque
          ? verrouillee({
              key: "instructeur",
              aria: `Second instructeur verrouillé : débloquer pour ${PRIX_INSTRUCTEUR_GROUPE_2} pièces d’or`,
              libelle: "Instructeur",
              prix: PRIX_INSTRUCTEUR_GROUPE_2,
              popup: { role: "unlock-group", group: 2 },
              instructeur: true,
            })
          : portrait(G.instructor, "instructor", 0, g)}
        {G.students.map((person, index) =>
          index < G.capacity ? (
            portrait(person, "student", index, g, index)
          ) : (
            verrouillee({
              key: index,
              aria: `Emplacement élève verrouillé : débloquer pour ${PRIX_PLACE_ELEVE[g]} pièces d’or`,
              libelle: "Emplacement élève",
              prix: PRIX_PLACE_ELEVE[g],
              popup: { role: "unlock", index, group: g },
            })
          ),
        )}
      </div>
    );
  }
  return (
    <section className="training-workspace">
      {cohorte(1)}
      {cohorte(2)}
      {popup && (
        <Modal
          title={
            popup.role === "unlock"
              ? "Ajouter une place élève"
              : popup.role === "unlock-group"
                ? "Second instructeur"
                : popup.role === "instructor"
                  ? "Instructeur"
                  : "Élève"
          }
          onClose={close}
        >
          {content()}
          {error && (
            <p id="training-error" role="alert" className="error">
              {error}
            </p>
          )}
        </Modal>
      )}
    </section>
  );
}
