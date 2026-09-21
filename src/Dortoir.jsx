import { useState } from "react";
import { ReferenceCrop, classeRoute } from "./Characters.jsx";
// Dortoir de la compagnie : un lit = un mercenaire embauché (aucun rapport avec
// le repos). Le mercenaire y prend place dès qu'il est recruté et le quitte
// quand il est renvoyé. Le lit affiche sa vétérance et le nom du joueur qui l'a
// recruté (saisi sur sa fiche).
const UNLOCK_PRICE = 100;
const INITIAL_CAPACITY = 6;
// `absences` : identifiant -> où se trouve le mercenaire quand il n'est pas au
// dortoir (Instructeur, À l'entraînement, À l'infirmerie). Il garde son lit,
// affiché grisé ; seul un renvoi de la compagnie libère le lit.
export function Dortoir({ dorm, warriors, absences = {}, gold, onUnlock, Modal }) {
  const [popup, setPopup] = useState(null);
  const [error, setError] = useState("");
  const hero = (id) => warriors.find((w) => w.id === id);
  const hired = dorm.beds.filter((b) => b && hero(b.heroId)).length;
  return (
    <>
      <section
        className="dorm-board dorm-named parchment"
        aria-label="Lits des mercenaires embauchés"
      >
        <div className="dorm-title">
          <h2>Dortoirs de la compagnie</h2>
          <span>
            {hired} embauché{hired > 1 ? "s" : ""} · {dorm.capacity} lits
            débloqués
          </span>
        </div>
        <div className="bed-grid">
          {dorm.beds.map((bed, slot) => {
            const merc = hero(bed?.heroId);
            const away = merc ? absences[merc.id] : undefined;
            const locked = slot >= dorm.capacity;
            const purchasable =
              slot === INITIAL_CAPACITY && dorm.capacity === INITIAL_CAPACITY;
            return (
              <div className="bed-cell" key={slot}>
                <button
                  className={`bed-slot ${locked ? "bed-locked" : ""} ${away ? "bed-away" : ""}`}
                  onClick={() => {
                    setError("");
                    if (locked)
                      setPopup({ type: purchasable ? "unlock" : "locked" });
                    else if (merc)
                      // Même fiche que pour le recrutement (bouton « Renvoyer »).
                      location.hash = `personnages/${classeRoute(merc.role)}/${merc.id}`;
                    else setPopup({ type: "free" });
                  }}
                  aria-label={
                    locked
                      ? purchasable
                        ? `Débloquer le lit ${slot + 1} pour ${UNLOCK_PRICE} pièces d’or`
                        : `Lit ${slot + 1} verrouillé`
                      : merc
                        ? `${merc.name}, vétérance ${merc.veterancy}${merc.player ? `, joueur ${merc.player}` : ""}${away ? `, ${away.toLowerCase()}` : ""}`
                        : `Lit ${slot + 1} libre`
                  }
                >
                  <span className="bed-frame" aria-hidden="true">
                    <img src="/assets/references/dormitory.png" alt="" />
                  </span>
                  {merc ? (
                    <>
                      <ReferenceCrop
                        className="bed-portrait"
                        crop={merc.portrait}
                      />
                      <span className="bed-veterance" title="Vétérance">
                        {merc.veterancy}
                      </span>
                      <span className="bed-name">{merc.name}</span>
                      {away && <span className="bed-away-label">{away}</span>}
                    </>
                  ) : locked ? (
                    <>
                      <span className="bed-lock" aria-hidden="true">
                        <img src="/assets/icons/lock.png" alt="" />
                      </span>
                      {purchasable && <strong>{UNLOCK_PRICE} Po</strong>}
                    </>
                  ) : (
                    <span className="free-bed">Lit libre</span>
                  )}
                </button>
                {!locked && (
                  <div
                    className="bed-player"
                    title={merc?.player ? "Joueur" : undefined}
                  >
                    {merc?.player || " "}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </section>
      {popup && (
        <Modal
          title={
            popup.type === "unlock"
              ? "Débloquer un lit"
              : popup.type === "locked"
                ? "Lit verrouillé"
                : "Lit libre"
          }
          onClose={() => setPopup(null)}
        >
          {popup.type === "unlock" ? (
            <>
              <p>
                Débloquez un lit supplémentaire pour embaucher un mercenaire de
                plus. La trésorerie de la compagnie sera débitée de{" "}
                <strong>{UNLOCK_PRICE} Po</strong>.
              </p>
              <p>
                Solde actuel : {gold} Po · Après déblocage :{" "}
                {Math.max(0, gold - UNLOCK_PRICE)} Po
              </p>
              <button
                className="primary"
                disabled={gold < UNLOCK_PRICE}
                onClick={async () => {
                  const result = await onUnlock();
                  if (result?.error) setError(result.error);
                  else setPopup(null);
                }}
              >
                Débloquer pour {UNLOCK_PRICE} Po
              </button>
              {gold < UNLOCK_PRICE && (
                <p className="error">
                  La compagnie n’a pas assez de pièces d’or.
                </p>
              )}
            </>
          ) : popup.type === "locked" ? (
            <p>
              Le coût de ce lit n’a pas encore été renseigné par le maître du
              jeu.
            </p>
          ) : (
            <p>
              Ce lit est libre. Un mercenaire y prend place dès qu’il est
              recruté, depuis les pages Personnages.
            </p>
          )}
          {error && (
            <p className="error" role="alert">
              {error}
            </p>
          )}
        </Modal>
      )}
    </>
  );
}
