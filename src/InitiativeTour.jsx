import { createContext, useContext, useLayoutEffect, useRef } from "react";

// Barre d'initiative (Bruno, 2026-10-21) : l'ordre des tours, fixe en haut de l'écran, de la meilleure initiative à la
// moins bonne. Chacun clique « Fin de tour » : son icône passe à droite de la barre et se grise jusqu'au Rd suivant.
// `rows` : lignes de initiative_tour { id, kind, mercenaire_id, creature_quete_id, label, rang, joue_ordre }.

export const TourContext = createContext({ rows: [], finTour: async () => {} });
export const useTour = () => useContext(TourContext);

// Ordre d'affichage : ceux qui n'ont pas joué (par rang), puis ceux qui ont fini leur tour (dans l'ordre de fin).
export function trierTour(rows) {
  return [...rows].sort((a, b) => {
    const ja = a.joue_ordre != null;
    const jb = b.joue_ordre != null;
    if (ja !== jb) return ja ? 1 : -1;
    if (ja) return a.joue_ordre - b.joue_ordre;
    return a.rang - b.rang;
  });
}

// Entrée de la barre d'un mercenaire ou d'une créature (undefined si elle n'est pas dans l'ordre d'initiative).
export const entreeTour = (rows, kind, id) =>
  rows.find((r) => (kind === "mercenaire" ? r.mercenaire_id === id : r.creature_quete_id === id));

// Bouton « Fin de tour » d'une fiche (mercenaire ou créature) ; grisé une fois le tour terminé, jusqu'au prochain Rd.
export function BoutonFinTour({ kind, id, disabled = false }) {
  const { rows, finTour } = useTour();
  const e = entreeTour(rows, kind, id);
  if (!e) return null;
  const joue = e.joue_ordre != null;
  return (
    <button
      type="button"
      className={`fin-tour${joue ? " fait" : ""}`}
      disabled={joue || disabled}
      onClick={() => finTour(kind, id)}
      title={joue ? "Tour terminé : le MJ clique sur Rd pour le tour suivant." : "Termine votre tour : votre icône passe à droite de la barre d'initiative."}
    >
      {joue ? "Tour terminé" : "Fin de tour"}
    </button>
  );
}

export function BarreInitiative({ rows, mercenaires }) {
  const ordre = trierTour(rows);
  const racine = useRef(null);
  const positions = useRef(new Map());
  // Animation de déplacement (FLIP) quand l'ordre change : les icônes glissent vers leur nouvelle place.
  useLayoutEffect(() => {
    const el = racine.current;
    if (!el) return;
    const reduit = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
    const maintenant = new Map();
    for (const t of el.querySelectorAll("[data-tour-id]")) {
      const x = t.getBoundingClientRect().left;
      maintenant.set(t.dataset.tourId, x);
      const avant = positions.current.get(t.dataset.tourId);
      if (!reduit && avant != null && Math.abs(avant - x) > 1 && t.animate) {
        t.animate([{ transform: `translateX(${avant - x}px)` }, { transform: "translateX(0)" }], {
          duration: 380,
          easing: "cubic-bezier(.2,.8,.2,1)",
        });
      }
    }
    positions.current = maintenant;
  });
  if (!rows.length) return null;
  const premierActif = ordre.findIndex((r) => r.joue_ordre == null);
  const tousFinis = premierActif === -1;
  return (
    <nav className="barre-ini" ref={racine} aria-label="Ordre d'initiative">
      <span className="barre-ini-titre" aria-hidden="true">
        Initiative
      </span>
      <ol className="barre-ini-liste">
        {ordre.map((r, i) => {
          const merc = r.kind === "mercenaire" ? mercenaires.find((m) => m.id === r.mercenaire_id) : null;
          const nom = merc ? merc.nom : r.label || "Créature";
          const joue = r.joue_ordre != null;
          const classes = `ib-tuile ${r.kind}${joue ? " joue" : ""}${i === premierActif ? " actif" : ""}`;
          return (
            <li key={r.id} data-tour-id={r.id} className={classes} title={`${nom}${joue ? " — tour terminé" : i === premierActif ? " — à jouer" : ""}`}>
              {merc ? (
                <img src={merc.portrait || "/assets/icons/lock.webp"} alt={nom} draggable="false" />
              ) : (
                <span className="ib-titre">{nom}</span>
              )}
            </li>
          );
        })}
      </ol>
      {tousFinis && <span className="barre-ini-fin">Tour terminé : en attente du Rd</span>}
    </nav>
  );
}
