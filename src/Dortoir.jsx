import { useRef, useState } from "react";
import { ReferenceCrop, classeRoute } from "./Characters.jsx";
import { VetBadge } from "./VetBadge.jsx";
import { useGlassWindows } from "./glassWindows.js";
import { prixLitDortoir } from "./dormitory.js";
// Dortoir de la compagnie : un lit = un mercenaire embauché (aucun rapport avec
// le repos). Le mercenaire y prend place dès qu'il est recruté et le quitte
// quand il est renvoyé. Le lit affiche sa vétérance et le nom du joueur qui l'a
// recruté (saisi sur sa fiche).
// `absences` : identifiant -> où se trouve le mercenaire quand il n'est pas au
// dortoir (Instructeur, À l'entraînement, À l'infirmerie). Il garde son lit,
// affiché grisé ; seul un renvoi de la compagnie libère le lit.
// Les lits verrouillés ne peuvent être débloqués que par l'administrateur
// (`estAdmin`, vérifié aussi par le serveur) ; les joueurs voient leur prix.
export function Dortoir({
  dorm,
  warriors,
  absences = {},
  estAdmin = false,
  gold,
  onUnlock,
  retourQuetes = false,
  Modal,
}) {
  const [popup, setPopup] = useState(null);
  const [error, setError] = useState("");
  // Verre dépoli sur le cadre seulement : les lits sont des fenêtres
  // entièrement transparentes découpées dans ce verre.
  const boardRef = useRef(null);
  const layerRef = useRef(null);
  const windows = useGlassWindows(boardRef, layerRef, ".bed-cell");
  const hero = (id) => warriors.find((w) => w.id === id);
  // Prix du lit visé par la fenêtre ouverte (déblocage ou lit verrouillé).
  const prixPopup = prixLitDortoir(popup?.slot);
  const hired = dorm.beds.filter((b) => b && hero(b.heroId)).length;
  return (
    <>
      <section
        ref={boardRef}
        className="dorm-board dorm-named parchment glass-board"
        aria-label="Lits des mercenaires embauchés"
      >
        <div
          ref={layerRef}
          className="glass-layer"
          style={windows ? { clipPath: `path(evenodd, "${windows}")` } : undefined}
          aria-hidden="true"
        />
        <div className="dorm-title">
          {retourQuetes && (
            <a className="wood-button dorm-retour" href="#quetes">
              ‹ Retour aux quêtes
            </a>
          )}
          {retourQuetes && (
            <span className="dorm-consigne">
              Cliquez sur un mercenaire, puis sur « Quête » dans sa fiche.
            </span>
          )}
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
            // Les lits se débloquent dans l'ordre : seul le premier lit verrouillé
            // peut être acheté (par l'administrateur) ; les autres affichent leur prix.
            const purchasable = estAdmin && slot === dorm.capacity;
            const prix = prixLitDortoir(slot);
            return (
              <div className="bed-cell" key={slot}>
                <button
                  className={`bed-slot ${locked ? "bed-locked" : ""} ${away ? "bed-away" : ""}`}
                  onClick={() => {
                    setError("");
                    if (locked)
                      setPopup({ type: purchasable ? "unlock" : "locked", slot });
                    else if (merc)
                      // Même fiche que pour le recrutement (bouton « Renvoyer »).
                      location.hash = `personnages/${classeRoute(merc.role)}/${merc.id}`;
                    else setPopup({ type: "free" });
                  }}
                  aria-label={
                    locked
                      ? purchasable
                        ? `Débloquer le lit ${slot + 1} pour ${prix} pièces d’or`
                        : `Lit ${slot + 1} verrouillé`
                      : merc
                        ? `${merc.name}, vétérance ${merc.veterancy}${merc.player ? `, joueur ${merc.player}` : ""}${away ? `, ${away.toLowerCase()}` : ""}`
                        : `Lit ${slot + 1} libre`
                  }
                >
                  <span className="bed-frame" aria-hidden="true">
                    <img src="/assets/references/dormitory.webp" alt="" />
                  </span>
                  {merc ? (
                    <>
                      <ReferenceCrop
                        className="bed-portrait"
                        crop={merc.portrait}
                      />
                      <VetBadge className="bed-veterance" value={merc.veterancy} />
                      <span className="bed-name">{merc.name}</span>
                      {away && <span className="bed-away-label">{away}</span>}
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
                {!locked && (
                  <div
                    className={`bed-player${away ? " bed-player-away" : ""}`}
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
                <strong>{prixPopup} Po</strong>.
              </p>
              <p>
                Solde actuel : {gold} Po · Après déblocage :{" "}
                {Math.max(0, gold - prixPopup)} Po
              </p>
              <button
                className="primary"
                disabled={gold < prixPopup}
                onClick={async () => {
                  const result = await onUnlock();
                  if (result?.error) setError(result.error);
                  else setPopup(null);
                }}
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
