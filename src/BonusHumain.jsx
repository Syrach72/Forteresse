import { useState } from "react";
import { Modal } from "./Modal.jsx";

// Compétence passive « Humain » : à son recrutement, le joueur ajoute 1 point à la Puissance, à la Vélocité
// ou au Mental du mercenaire (plafond 9). Fenêtre affichée tant que le choix n'est pas fait ; « Plus tard »
// la masque jusqu'au prochain chargement.
const CARACS = [
  ["puissance", "Puissance", "/assets/icons/puissance.webp"],
  ["velocite", "Vélocité", "/assets/icons/velocite.webp"],
  ["mental", "Mental", "/assets/icons/mental.webp"],
];

export function BonusHumain({ merc, onChoisir, onClose }) {
  const [busy, setBusy] = useState(false);
  const [erreur, setErreur] = useState("");
  async function choisir(cle) {
    if (busy) return;
    setBusy(true);
    const r = await onChoisir(merc.id, cle);
    setBusy(false);
    setErreur(r?.error || "");
  }
  return (
    <Modal title={`${merc.nom} : bonus Humain`} onClose={onClose}>
      <p>
        {merc.nom} est Humain : choisissez la caractéristique qui gagne <strong>+1 point</strong>. Ce bonus ne se
        choisit qu’une fois.
      </p>
      <div className="humain-choix">
        {CARACS.map(([cle, libelle, icone]) => {
          const valeur = merc[cle] ?? 0;
          return (
            <button
              type="button"
              key={cle}
              className="wood-button humain-carac"
              disabled={busy || valeur >= 9}
              onClick={() => choisir(cle)}
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
      {erreur && (
        <p className="error" role="alert">
          {erreur}
        </p>
      )}
    </Modal>
  );
}
