import { useState } from "react";
import { Modal } from "./Modal.jsx";

// Points de caractéristique : à chaque niveau de vétérance gagné, le joueur qui contrôle le mercenaire ajoute
// 1 point à la Puissance, à la Vélocité ou au Mental (plafond 9). Le choix est définitif ; seul le MJ peut
// modifier autrement les caractéristiques.
const CARACS = [
  ["puissance", "Puissance", "/assets/icons/puissance.webp"],
  ["velocite", "Vélocité", "/assets/icons/velocite.webp"],
  ["mental", "Mental", "/assets/icons/mental.webp"],
];

// Pastille clignotante posée sur le portrait d'un mercenaire qui a un point à dépenser.
export function AlertePoint({ className = "" }) {
  return (
    <span
      className={`alerte-point ${className}`.trim()}
      role="img"
      aria-label="Un point de caractéristique est à dépenser"
      title="Un point de caractéristique est à dépenser"
    >
      +1
    </span>
  );
}

export function PointCaracModal({ merc, onDepenser, onClose }) {
  const [busy, setBusy] = useState(false);
  const [erreur, setErreur] = useState("");
  const [choix, setChoix] = useState(null);
  const points = merc.pointsCarac ?? 0;
  async function confirmer() {
    if (busy || !choix) return;
    setBusy(true);
    const r = await onDepenser(merc.id, choix);
    setBusy(false);
    if (r?.error) {
      setErreur(r.error);
      setChoix(null);
      return;
    }
    setErreur("");
    setChoix(null);
    // Plus aucun point à dépenser : la fenêtre se ferme d'elle-même (le compte se met à jour après la lecture).
    if (points <= 1) onClose();
  }
  const cible = choix ? CARACS.find(([cle]) => cle === choix) : null;
  return (
    <Modal title={`${merc.nom} : point de caractéristique`} onClose={onClose}>
      <p>
        {merc.nom} a gagné de la vétérance : {points > 1 ? `${points} points sont à dépenser` : "1 point est à dépenser"}.
        Choisissez la caractéristique qui gagne <strong>+1 point</strong> (9 au maximum).
      </p>
      {!cible ? (
        <div className="humain-choix">
          {CARACS.map(([cle, libelle, icone]) => {
            const valeur = merc[cle] ?? 0;
            return (
              <button
                type="button"
                key={cle}
                className="wood-button humain-carac"
                disabled={busy || valeur >= 9}
                onClick={() => setChoix(cle)}
                title={valeur >= 9 ? "Déjà au maximum (9)" : `${libelle} ${valeur} → ${valeur + 1}`}
              >
                <img src={icone} alt="" />
                <span>{libelle}</span>
                <strong>
                  {valeur} → {Math.min(9, valeur + 1)}
                </strong>
              </button>
            );
          })}
        </div>
      ) : (
        <div role="alertdialog" aria-label="Confirmer le choix">
          <p className="point-carac-confirm">
            Ajouter 1 point à la <strong>{cible[1]}</strong> ({merc[cible[0]] ?? 0} → {Math.min(9, (merc[cible[0]] ?? 0) + 1)}
            ) ? <strong>Ce choix est définitif.</strong>
          </p>
          <div className="humain-choix">
            <button type="button" className="wood-button" disabled={busy} onClick={confirmer}>
              Confirmer
            </button>
            <button type="button" className="wood-button" disabled={busy} onClick={() => setChoix(null)}>
              Retour
            </button>
          </div>
        </div>
      )}
      {erreur && (
        <p className="error" role="alert">
          {erreur}
        </p>
      )}
    </Modal>
  );
}
