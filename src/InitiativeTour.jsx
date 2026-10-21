import { createContext, useContext, useLayoutEffect, useRef, useState } from "react";

// Barre d'initiative (Bruno, 2026-10-21) : l'ordre des tours, fixe en haut de l'écran, de la meilleure initiative à la
// moins bonne. Chacun clique « Fin de tour » : son icône passe à droite de la barre et se grise jusqu'au Rd suivant.
// Les créatures du MJ sont des « ? » pour les joueurs jusqu'à leur premier « Fin de tour » ; « Passer le tour » (MJ) ne
// révèle pas leur nom ; « Retarder son action » repositionne le participant N crans plus loin (une fois par Rd).
// `rows` : lignes de initiative_tour { id, kind, mercenaire_id, creature_quete_id, label, rang, ordre, joue_ordre, retarde, revele }.

export const TourContext = createContext({
  rows: [],
  estAdmin: false,
  nomsCreatures: new Map(),
  finTour: async () => {},
  passerTour: async () => {},
  retarder: async () => {},
});
export const useTour = () => useContext(TourContext);

// Ordre d'affichage : ceux qui n'ont pas joué (par position, décalée par « Retarder »), puis ceux qui ont fini leur tour
// (dans l'ordre de fin).
export function trierTour(rows) {
  return [...rows].sort((a, b) => {
    const ja = a.joue_ordre != null;
    const jb = b.joue_ordre != null;
    if (ja !== jb) return ja ? 1 : -1;
    if (ja) return a.joue_ordre - b.joue_ordre;
    return (a.ordre ?? a.rang) - (b.ordre ?? b.rang) || a.rang - b.rang;
  });
}

// Entrée de la barre d'un mercenaire ou d'une créature (undefined si elle n'est pas dans l'ordre d'initiative).
export const entreeTour = (rows, kind, id) =>
  rows.find((r) => (kind === "mercenaire" ? r.mercenaire_id === id : r.creature_quete_id === id));

// Actions de tour d'une fiche (mercenaire ou créature) : « Fin de tour », « Passer le tour » (MJ, créature),
// « Retarder son action » (à son tour, une fois par Rd).
export function ActionsTour({ kind, id, disabled = false }) {
  const { rows, estAdmin, finTour, passerTour, retarder } = useTour();
  const [ouvert, setOuvert] = useState(false);
  const [crans, setCrans] = useState(1);
  const e = entreeTour(rows, kind, id);
  if (!e) return null;
  const joue = e.joue_ordre != null;
  const restants = trierTour(rows).filter((r) => r.joue_ordre == null);
  const sonTour = restants[0]?.id === e.id;
  const derriere = restants.length - 1;
  const peutRetarder = !joue && sonTour && !e.retarde && derriere >= 1 && !disabled;
  const raisonRetard = joue
    ? "Tour terminé."
    : e.retarde
      ? "Action déjà retardée ce Rd."
      : !sonTour
        ? "Disponible quand c'est votre tour."
        : derriere < 1
          ? "Plus personne derrière vous."
          : "Repositionnez-vous plus loin dans l'ordre d'initiative (une fois par Rd).";
  return (
    <div className="actions-tour">
      <button
        type="button"
        className={`fin-tour${joue ? " fait" : ""}`}
        disabled={joue || disabled}
        onClick={() => finTour(kind, id)}
        title={joue ? "Tour terminé : le MJ clique sur Rd pour le tour suivant." : "Termine votre tour : votre icône passe à droite de la barre d'initiative."}
      >
        {joue ? "Tour terminé" : "Fin de tour"}
      </button>
      {kind === "creature" && estAdmin && (
        <button
          type="button"
          className={`fin-tour fin-tour-secondaire${joue ? " fait" : ""}`}
          disabled={joue}
          onClick={() => passerTour(id)}
          title="Passe le tour de cette créature sans révéler son nom aux joueurs."
        >
          Passer le tour
        </button>
      )}
      <button
        type="button"
        className="fin-tour fin-tour-secondaire"
        disabled={!peutRetarder}
        onClick={() => {
          setCrans(1);
          setOuvert((o) => !o);
        }}
        title={raisonRetard}
        aria-expanded={ouvert && peutRetarder}
      >
        Retarder son action
      </button>
      {ouvert && peutRetarder && (
        <div className="retarder-choix" role="group" aria-label="Retarder son action">
          <label>
            Reculer de
            <select value={crans} onChange={(ev) => setCrans(Number(ev.target.value))}>
              {Array.from({ length: derriere }, (_, i) => i + 1).map((n) => (
                <option key={n} value={n}>
                  {n} cran{n > 1 ? "s" : ""}
                </option>
              ))}
            </select>
          </label>
          <button
            type="button"
            className="fin-tour"
            onClick={async () => {
              await retarder(kind, id, crans);
              setOuvert(false);
            }}
          >
            Confirmer
          </button>
          <button type="button" className="fin-tour fin-tour-secondaire" onClick={() => setOuvert(false)}>
            Annuler
          </button>
        </div>
      )}
    </div>
  );
}

export function BarreInitiative({ rows, mercenaires, nomsCreatures = new Map(), estAdmin = false }) {
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
          // Créature : le MJ voit toujours son nom ; les joueurs un « ? » tant qu'elle n'a pas fini son premier tour.
          const nomCreature = estAdmin ? nomsCreatures.get(r.creature_quete_id) || r.label : r.revele ? r.label : null;
          const inconnue = r.kind === "creature" && !nomCreature;
          const nom = merc ? merc.nom : nomCreature || "?";
          const joue = r.joue_ordre != null;
          const classes = `ib-tuile ${r.kind}${joue ? " joue" : ""}${i === premierActif ? " actif" : ""}`;
          const titre = inconnue ? "Créature inconnue" : nom;
          return (
            <li key={r.id} data-tour-id={r.id} className={classes} title={`${titre}${joue ? " — tour terminé" : i === premierActif ? " — à jouer" : ""}`}>
              {merc ? (
                <img src={merc.portrait || "/assets/icons/lock.webp"} alt={nom} draggable="false" />
              ) : (
                <span className={`ib-titre${inconnue ? " inconnue" : ""}`}>{nom}</span>
              )}
            </li>
          );
        })}
      </ol>
      {tousFinis && <span className="barre-ini-fin">Tour terminé : en attente du Rd</span>}
    </nav>
  );
}
