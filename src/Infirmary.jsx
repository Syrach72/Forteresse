import { AlertePoint } from "./PointsCarac.jsx";
import { useRef, useState } from "react";
import { ReferenceCrop } from "./Characters.jsx";
import { CoeurBlesse } from "./CoeurBlesse.jsx";
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
        <button
          type="button"
          className="infirmerie-aide"
          aria-label="Explication du fonctionnement de l’infirmerie"
          title="Comment fonctionne l’infirmerie ?"
          onClick={() => setPopup({ type: "aide" })}
        >
          ?
        </button>
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
                    {w?.pointCarac && <AlertePoint />}
                    {w?.blesse && <CoeurBlesse className="coeur-lit" mort={w.pvZero} />}
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
          verre={popup.type === "aide"}
          title={
            popup.type === "aide"
              ? "L’infirmerie : mode d’emploi"
              : popup.type === "unlock"
              ? "Débloquer un lit"
              : popup.type === "locked"
                ? "Lit verrouillé"
                : popup.type === "bed"
                  ? bedHero?.name || "En soin"
                  : "Lit libre"
          }
          onClose={close}
        >
          {popup.type === "aide" ? (
            <div className="aide-defense">
              <section className="aide-defense-rubrique">
                <h3>À quoi ça sert</h3>
                <p>
                  L’infirmerie rend leurs points de vie aux mercenaires blessés. Elle est partagée par tous les
                  joueurs de la compagnie.
                </p>
              </section>
              <section className="aide-defense-rubrique">
                <h3>Envoyer un mercenaire se faire soigner</h3>
                <p>
                  Ouvrez sa fiche depuis la Caserne et cliquez sur « Soigner » : seul son recruteur peut le faire. Il
                  prend alors un lit libre de l’infirmerie, tandis que son lit de la Caserne lui est conservé. Il faut
                  qu’il soit blessé (de 1 PV jusqu’à moins que sa santé max), qu’il ne soit pas déjà en soin ni à
                  l’entraînement, et qu’un lit soit libre. Un mercenaire à 0 PV ne peut pas être admis : il lui faut
                  d’abord au moins 1 PV, par exemple avec une potion de vie.
                </p>
              </section>
              <section className="aide-defense-rubrique">
                <h3>Les soins</h3>
                <p>
                  Chaque « +1 Instance » du maître du jeu rend au mercenaire un tiers de sa santé max (arrondi au
                  supérieur). Le chiffre sur le lit indique le nombre
                  d’instances de soin encore nécessaires (1 à 3, selon les points de vie perdus). Quand il a retrouvé
                  toute sa santé, le mercenaire retourne tout seul à sa place à la Caserne.
                </p>
              </section>
              <section className="aide-defense-rubrique">
                <h3>Le rappeler avant la fin</h3>
                <p>
                  En cliquant sur son lit, son recruteur (ou le maître du jeu) peut le rappeler à la Caserne avant la
                  fin des soins. Il garde les points de vie déjà regagnés.
                </p>
              </section>
              <section className="aide-defense-rubrique">
                <h3>Attention</h3>
                <p>
                  Un mercenaire encore à 0 PV à la fin d’une instance repose au cimetière : son équipement retourne à
                  l’arsenal et il n’est plus disponible.
                </p>
              </section>
            </div>
          ) : popup.type === "unlock" ? (
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
                retrouve sa place à la caserne.
              </p>
              {peutRappeler(bedPopup.heroId) ? (
                <button
                  className="primary"
                  disabled={enCours}
                  onClick={() => agir(() => onRecall(bedPopup.heroId))}
                >
                  Retour à la caserne maintenant
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
              depuis la Caserne et cliquez sur « Soigner ».
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
