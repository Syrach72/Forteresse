import { useState } from "react";
import { Modal } from "./Modal.jsx";

// Compétence passive « Ennemi Juré » du Rôdeur : un type d'ennemi au recrutement, un deuxième à la vétérance 4 et un
// troisième à la vétérance 8. Un type ne se choisit qu'une fois par mercenaire ; les choix restent valables si le
// mercenaire est renvoyé (tant qu'il a la vétérance requise).
export const TYPES_ENNEMI = [
  "aberrations",
  "artificiels",
  "bêtes",
  "célestes",
  "dragons",
  "élémentaires",
  "fées",
  "fiélons",
  "géants",
  "monstruosités",
  "morts-vivants",
  "plantes",
  "vases",
];
export const VETERANCE_RANG = [1, 4, 8];
const majuscule = (t) => t.charAt(0).toUpperCase() + t.slice(1);

export function EnnemiJure({ merc, onChoisir, onClose }) {
  const [busy, setBusy] = useState(false);
  const [erreur, setErreur] = useState("");
  const choisis = (merc.ennemisJures || []).map((e) => e.type);
  const total = (merc.ennemisJures || []).length + (merc.ennemiJureAChoisir || 0);
  const numero = (merc.ennemisJures || []).length + 1;
  async function choisir(type) {
    if (busy) return;
    setBusy(true);
    const r = await onChoisir(merc.id, type);
    setBusy(false);
    setErreur(r?.error || "");
  }
  return (
    <Modal title={`${merc.nom} : ennemi juré`} onClose={onClose}>
      <p>
        Choisissez le type d’ennemi juré de <strong>{merc.nom}</strong> (choix {numero} sur {total}). Un type ne se
        choisit qu’une fois, et ce choix est définitif : il reste valable même si {merc.nom} est renvoyé.
      </p>
      {choisis.length > 0 && (
        <p className="muted">Déjà choisi : {choisis.map(majuscule).join(", ")}.</p>
      )}
      <div className="humain-choix ennemi-jure-choix">
        {TYPES_ENNEMI.map((type) => (
          <button
            type="button"
            key={type}
            className="wood-button"
            disabled={busy || choisis.includes(type)}
            onClick={() => choisir(type)}
            title={choisis.includes(type) ? "Déjà choisi pour ce mercenaire" : undefined}
          >
            {majuscule(type)}
          </button>
        ))}
      </div>
      {erreur && (
        <p className="error" role="alert">
          {erreur}
        </p>
      )}
    </Modal>
  );
}
