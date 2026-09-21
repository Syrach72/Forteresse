import { useState } from "react";
import { ReferenceCrop } from "./Characters.jsx";
import { VetBadge } from "./VetBadge.jsx";
import { VETERANCE_ECART, eligibleStudents } from "./training-data.js";
// Terrain d'entraînement PARTAGÉ : visible par tous les joueurs. Un instructeur
// (choisi depuis la fiche du mercenaire, au Dortoir) et des élèves (choisis
// ici, dans « Choisir un élève »).
// - people : tous les mercenaires de la compagnie (pour afficher les
//   participants de chacun) ;
// - warriors : ceux du joueur connecté, les seuls qu'il peut placer ou renvoyer
//   (l'administrateur peut tout renvoyer).
// Les règles sont vérifiées par le serveur (migration
// 20260921100000_entrainement.sql) ; ici on ne propose que des choix valides.
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
  Modal,
}) {
  const [popup, setPopup] = useState(null);
  const [error, setError] = useState("");
  // Une action serveur est en cours : évite les doubles clics.
  const [enCours, setEnCours] = useState(false);
  const hero = (person) => people.find((w) => w.id === person?.heroId);
  const instructor = hero(training.instructor);
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
  function portrait(person, role, index) {
    const w = hero(person);
    const isInstructor = role === "instructor";
    // Pas d'élève tant qu'aucun instructeur n'est en place.
    const blocked = !isInstructor && !w && !instructor;
    const noun = isInstructor ? "instructeur" : "élève";
    return (
      <button
        className={`training-place parchment ${isInstructor ? "instructor-place" : ""} ${blocked ? "training-blocked" : ""}`}
        disabled={blocked}
        aria-label={
          w
            ? `${isInstructor ? "Instructeur" : "Élève"} ${w.name}, vétérance ${w.veterancy}`
            : blocked
              ? "Élève : choisissez d’abord un instructeur"
              : `Choisir un ${noun}`
        }
        onClick={() => {
          setError("");
          setPopup({ role, index });
        }}
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
            : w && instructor
              ? `Élève · objectif ${instructor.veterancy}`
              : "Élève"}
        </small>
      </button>
    );
  }
  const close = () => {
    setPopup(null);
    setError("");
  };
  // Bouton « Renvoyer au dortoir » (recruteur ou administrateur), sinon
  // l'explication.
  function renvoi(w, role, index) {
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
        onClick={() => agir(() => onSendBack(role, index))}
      >
        Renvoyer au dortoir
      </button>
    );
  }
  // Contenu de la fenêtre selon la cellule cliquée.
  function content() {
    if (popup.role === "unlock")
      return (
        <>
          <p>
            Ajouter une place d’élève débite 100 Po de la trésorerie de la
            compagnie.
          </p>
          <button
            className="primary"
            disabled={gold < 100 || enCours}
            onClick={() => agir(() => onUnlock())}
          >
            Débloquer pour 100 Po
          </button>
          {gold < 100 && <p className="error">Trésorerie insuffisante.</p>}
        </>
      );
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
      const eleves = training.students.filter(Boolean).length;
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
          {renvoi(instructor, "instructor", 0)}
        </>
      );
    }
    // Élève
    const w = hero(training.students[popup.index]);
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
          {renvoi(w, "student", popup.index)}
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
            onClick={() => agir(() => onChoose(popup.index, c.id))}
          >
            {c.name} · vétérance {c.veterancy}
          </button>
        ))}
      </div>
    );
  }
  return (
    <section className="training-workspace">
      <div className="training-caption">
        <h2>La cour d’entraînement</h2>
      </div>
      <div className="training-cohort">
        {portrait(training.instructor, "instructor", 0)}
        {training.students.map((person, index) =>
          index < training.capacity ? (
            <div key={index}>{portrait(person, "student", index)}</div>
          ) : (
            <button
              key={index}
              className="training-place parchment training-locked"
              onClick={() => {
                setError("");
                setPopup({ role: "unlock", index });
              }}
            >
              <span>Emplacement élève</span>
              <strong>100 Po</strong>
              <small>Débloquer</small>
            </button>
          ),
        )}
      </div>
      {/* Second groupe d'instruction : mêmes cellules que le premier, entièrement
          bloquées pour le moment (instructeur, puis 3 places d'élève ; la
          première serait libre mais reste inutilisable sans instructeur). */}
      <div
        className="training-cohort training-cohort-second"
        role="group"
        aria-label="Second groupe d’instruction, bloqué pour le moment"
      >
        <button
          className="training-place parchment instructor-place training-blocked"
          disabled
          aria-label="Second instructeur : bloqué pour le moment"
        >
          <span className="training-padlock" aria-hidden="true">
            <img src="/assets/icons/lock.png" alt="" />
          </span>
          <span>Choisir un instructeur</span>
          <small>Instructeur</small>
        </button>
        <div>
          <button
            className="training-place parchment training-blocked"
            disabled
            aria-label="Élève : choisissez d’abord un instructeur"
          >
            <span>Choisissez d’abord un instructeur</span>
            <small>Élève</small>
          </button>
        </div>
        {[0, 1].map((i) => (
          <button
            key={i}
            className="training-place parchment training-locked training-blocked"
            disabled
            aria-label="Emplacement élève : bloqué pour le moment"
          >
            <span className="training-padlock" aria-hidden="true">
              <img src="/assets/icons/lock.png" alt="" />
            </span>
            <span>Emplacement élève</span>
            <small>Bloqué</small>
          </button>
        ))}
      </div>
      {popup && (
        <Modal
          title={
            popup.role === "unlock"
              ? "Ajouter une place élève"
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
