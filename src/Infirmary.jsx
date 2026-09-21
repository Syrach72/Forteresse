import { useState } from "react";
import { ReferenceCrop } from "./Characters.jsx";
// Infirmerie PARTAGÉE : visible par tous les joueurs. Un joueur y envoie son
// mercenaire depuis sa fiche (bouton « Soigner ») ; il y reste SOINS_INSTANCES
// instances (le compteur baisse à chaque +1 Instance de l'administrateur), puis
// retrouve sa place au dortoir. Le lit du dortoir ne bouge jamais.
// - infirmary : { capacity, beds: [{ heroId, remaining } | null, ...] } ;
// - people : tous les mercenaires de la compagnie ;
// - warriors : ceux du joueur connecté (les seuls qu'il peut rappeler avant la
//   fin des soins, l'administrateur pouvant tout rappeler).
const INITIAL_CAPACITY = 2;
const UNLOCK_PRICE = 1000;
export function Infirmary({
  infirmary,
  people,
  warriors,
  estAdmin = false,
  gold,
  onRecall,
  onUnlock,
  Modal,
}) {
  const [popup, setPopup] = useState(null);
  const [error, setError] = useState("");
  const [enCours, setEnCours] = useState(false);
  const hero = (id) => people.find((w) => w.id === id);
  const enSoin = infirmary.beds.filter(Boolean).length;
  const close = () => {
    setPopup(null);
    setError("");
  };
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
  const peutRappeler = (id) => estAdmin || warriors.some((w) => w.id === id);
  const bedPopup = popup?.type === "bed" ? infirmary.beds[popup.slot] : null;
  const bedHero = bedPopup ? hero(bedPopup.heroId) : null;
  return (
    <>
      <section
        className="dorm-board infirmary-board"
        aria-label="Lits de l'infirmerie"
      >
        <div className="dorm-title">
          <h2>Infirmerie de la compagnie</h2>
          <span>
            {enSoin} en soin · {infirmary.capacity} places débloquées
          </span>
        </div>
        <div className="bed-grid">
          {infirmary.beds.map((bed, slot) => {
            const w = bed ? hero(bed.heroId) : null;
            const locked = slot >= infirmary.capacity;
            const purchasable =
              slot === INITIAL_CAPACITY && infirmary.capacity === INITIAL_CAPACITY;
            return (
              <button
                className={`bed-slot ${locked ? "bed-locked" : ""}`}
                key={slot}
                onClick={() => {
                  setError("");
                  if (locked)
                    setPopup({ type: purchasable ? "unlock" : "locked", slot });
                  else if (bed) setPopup({ type: "bed", slot });
                  else setPopup({ type: "free", slot });
                }}
                aria-label={
                  locked
                    ? purchasable
                      ? `Débloquer le lit ${slot + 1} pour ${UNLOCK_PRICE} pièces d’or`
                      : `Lit ${slot + 1} verrouillé`
                    : bed
                      ? `${w?.name || "Mercenaire"}, en soin, encore ${bed.remaining} instance${bed.remaining > 1 ? "s" : ""}`
                      : `Lit ${slot + 1} libre`
                }
              >
                <span className="bed-frame" aria-hidden="true">
                  <img src="/assets/references/dormitory.png" alt="" />
                </span>
                {bed ? (
                  <>
                    {w && (
                      <ReferenceCrop className="bed-portrait" crop={w.portrait} />
                    )}
                    <span className="rest-counter" title="Instances de soin restantes">
                      {bed.remaining}
                    </span>
                    <span className="bed-name">{w?.name || "Mercenaire"}</span>
                    <span className="bed-care-label">En soin</span>
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
                : popup.type === "bed"
                  ? bedHero?.name || "En soin"
                  : "Lit libre"
          }
          onClose={close}
        >
          {popup.type === "unlock" ? (
            <>
              <p>
                Débloquez un lit supplémentaire pour soigner un mercenaire de
                plus. La trésorerie de la compagnie sera débitée de{" "}
                <strong>{UNLOCK_PRICE} Po</strong>.
              </p>
              <p>
                Solde actuel : {gold} Po · Après déblocage :{" "}
                {Math.max(0, gold - UNLOCK_PRICE)} Po
              </p>
              <button
                className="primary"
                disabled={gold < UNLOCK_PRICE || enCours}
                onClick={() => agir(() => onUnlock())}
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
          ) : popup.type === "bed" && bedPopup ? (
            <>
              <p>
                {bedHero?.name} est en soin : encore{" "}
                <strong>{bedPopup.remaining}</strong> instance
                {bedPopup.remaining > 1 ? "s" : ""}. À 0, il retrouve sa place
                au dortoir.
              </p>
              {peutRappeler(bedPopup.heroId) ? (
                <button
                  className="primary"
                  disabled={enCours}
                  onClick={() => agir(() => onRecall(bedPopup.heroId))}
                >
                  Retour au dortoir maintenant
                </button>
              ) : (
                <p className="muted">
                  Ce mercenaire appartient à un autre joueur : seul son
                  recruteur peut le rappeler avant la fin des soins.
                </p>
              )}
            </>
          ) : (
            <p>
              Ce lit est libre. Pour soigner un mercenaire, ouvrez sa fiche
              depuis le Dortoir et cliquez sur « Soigner ».
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
