import { useState } from "react";
import { Modal } from "./Modal.jsx";

// Compétences passives du Rôdeur qui demandent de choisir un type : « Ennemi Juré » (un type d'ennemi) et
// « Explorateur-né » (un type de terrain). Un choix au recrutement, un deuxième à la vétérance 4 et un troisième à la
// vétérance 8. Un type ne se choisit qu'une fois par mercenaire ; les choix restent valables si le mercenaire est
// renvoyé (tant qu'il a la vétérance requise). Informations de fiche : aucun calcul n'en dépend.
export const VETERANCE_RANG = [1, 4, 8];
export const majuscule = (t) => t.charAt(0).toUpperCase() + t.slice(1);

export const CONFIG_ENNEMI_JURE = {
  nomCompetence: "ennemi juré",
  titre: (nom) => `${nom} : ennemi juré`,
  consigne: (nom) => `le type d’ennemi juré de ${nom}`,
  libelleListe: "Ennemis jurés",
  libelleBouton: "Choisir un ennemi juré",
  champChoisis: "ennemisJures",
  champAChoisir: "ennemiJureAChoisir",
  types: [
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
  ],
};

export const CONFIG_TERRAIN_FAVORI = {
  nomCompetence: "explorateur-né",
  titre: (nom) => `${nom} : terrain favori`,
  consigne: (nom) => `le type de terrain favori de ${nom}`,
  libelleListe: "Terrains favoris",
  libelleBouton: "Choisir un terrain favori",
  champChoisis: "terrainsFavoris",
  champAChoisir: "terrainFavoriAChoisir",
  types: ["arctique", "désert", "forêt", "littoral", "marais", "montagne", "plaine", "outreterre"],
};

export function ChoixType({ merc, config, onChoisir, onClose }) {
  const [busy, setBusy] = useState(false);
  const [erreur, setErreur] = useState("");
  const faits = merc[config.champChoisis] || [];
  const choisis = faits.map((e) => e.type);
  const total = faits.length + (merc[config.champAChoisir] || 0);
  async function choisir(type) {
    if (busy) return;
    setBusy(true);
    const r = await onChoisir(merc.id, type);
    setBusy(false);
    setErreur(r?.error || "");
  }
  return (
    <Modal title={config.titre(merc.nom)} onClose={onClose}>
      <p>
        Choisissez <strong>{config.consigne(merc.nom)}</strong> (choix {faits.length + 1} sur {total}). Un type ne se
        choisit qu’une fois, et ce choix est définitif : il reste valable même si {merc.nom} est renvoyé.
      </p>
      {choisis.length > 0 && <p className="muted">Déjà choisi : {choisis.map(majuscule).join(", ")}.</p>}
      <div className="humain-choix ennemi-jure-choix">
        {config.types.map((type) => (
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
