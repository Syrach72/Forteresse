import { useRef, useState } from "react";
import { ReferenceCrop } from "./Characters.jsx";
import { useGlassWindows } from "./glassWindows.js";
import { prixLitInfirmerie } from "./dormitory.js";
// Infirmerie PARTAGÉE : visible par tous les joueurs. Un joueur y envoie son
// mercenaire depuis sa fiche (bouton « Soigner ») ; chaque +1 Instance de
// l'administrateur lui rend un tiers de sa santé max (sur sa fiche) et le compteur
// (1 à 3) indique les instances encore nécessaires ; à sa santé max il retrouve
// sa place au dortoir. Le lit du dortoir ne bouge jamais.
// - infirmary : { capacity, beds: [{ heroId, remaining } | null, ...] } ;
// - people : tous les mercenaires de la compagnie ;
// - warriors : ceux du joueur connecté (les seuls qu'il peut rappeler avant la
//   fin des soins, l'administrateur pouvant tout rappeler).
// Les lits verrouillés (dans l'ordre : 300, 500, 800 puis 1200 Po) ne peuvent
// être débloqués que par l'administrateur (`estAdmin`, vérifié aussi par le
// serveur) ; les joueurs voient leur prix.
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
  // Verre dépoli sur le cadre seulement : les lits et les cases à débloquer
  // sont des fenêtres entièrement transparentes découpées dans ce verre.
  const boardRef = useRef(null);
  const layerRef = useRef(null);
  const windows = useGlassWindows(boardRef, layerRef, ".bed-slot");
  const hero = (id) => people.find((w) => w.id === id);
  const enSoin = infirmary.beds.filter(Boolean).length;
  // Prix du lit visé par la fenêtre ouverte (déblocage ou lit verrouillé).
  const prixPopup = prixLitInfirmerie(popup?.slot) ?? 0;
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
        ref={boardRef}
        className="dorm-board infirmary-board parchment glass-board"
        aria-label="Lits de l'infirmerie"
      >
        <div
          ref={layerRef}
          className="glass-layer"
          style={windows ? { clipPath: `path(evenodd, "${windows}")` } : undefined}
          aria-hidden="true"
        />
        <div className="dorm-title">
          <span>
            {enSoin} en soin · {infirmary.capacity} places débloquées
          </span>
        </div>
        <div className="bed-grid">
          {infirmary.beds.map((bed, slot) => {
            const w = bed ? hero(bed.heroId) : null;
            const locked = slot >= infirmary.capacity;
            const prix = prixLitInfirmerie(slot);
            const purchasable = estAdmin && slot === infirmary.capacity;
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
                      ? `Débloquer le lit ${slot + 1} pour ${prix} pièces d’or`
                      : `Lit ${slot + 1} verrouillé`
                    : bed
                      ? `${w?.name || "Mercenaire"}, en soin, encore ${bed.remaining} instance${bed.remaining > 1 ? "s" : ""}`
                      : `Lit ${slot + 1} libre`
                }
              >
                <span className="bed-frame" aria-hidden="true">
                  <img src="/assets/references/dormitory.webp" alt="" />
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
                      <img src="/assets/icons/lock.webp" alt="" />
                    </span>
                    {prix != null && <strong>{prix} Po</strong>}
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
                <strong>{prixPopup} Po</strong>.
              </p>
              <p>
                Solde actuel : {gold} Po · Après déblocage :{" "}
                {Math.max(0, gold - prixPopup)} Po
              </p>
              <button
                className="primary"
                disabled={gold < prixPopup || enCours}
                onClick={() => agir(() => onUnlock())}
              >
                Débloquer pour {prixPopup} Po
              </button>
              {gold < prixPopup && (
                <p className="error">
                  La compagnie n’a pas assez de pièces d’or.
                </p>
              )}
            </>
          ) : popup.type === "locked" ? (
            <p>
              {estAdmin
                ? "Les lits se débloquent dans l’ordre."
                : "Seul le maître du jeu peut débloquer un lit, dans l’ordre."}{" "}
              Celui-ci coûte <strong>{prixPopup} Po</strong>
              {estAdmin ? " une fois les lits précédents débloqués" : ""}.
            </p>
          ) : popup.type === "bed" && bedPopup ? (
            <>
              <p>
                {bedHero?.name} est en soin : encore{" "}
                <strong>{bedPopup.remaining}</strong> instance
                {bedPopup.remaining > 1 ? "s" : ""}. Chaque instance lui
                rend un tiers de sa santé max ; dès qu’il l’a retrouvée, il
                retrouve sa place au dortoir.
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
