import { useEffect, useRef, useState } from "react";
import { DeInitiative } from "./DeInitiative.jsx";

// Fenêtre du lancer d'initiative : un dé 3D pour les mercenaires du joueur (bouton « Lancer » par mercenaire, jamais
// modifiable ensuite), l'état des autres mercenaires, puis les relances automatiques de départage. Elle ne se ferme
// que lorsque tous les mercenaires et créatures de la quête ont lancé (le MJ peut la fermer à la main si un joueur
// est absent). Le nombre est tiré par le serveur ; le total = d20 + vélocité ; le rang est calculé par le serveur.
const pause = (ms) => new Promise((r) => setTimeout(r, ms));

export function FenetreInitiative({ engages, lancables, miens, rows, complete, estAdmin, onLancer, onClose }) {
  const de = useRef(null);
  const [message, setMessage] = useState("");
  const [occupe, setOccupe] = useState(false);
  const [recus, setRecus] = useState({}); // id -> résultat reçu du serveur
  const [reveles, setReveles] = useState(() => new Set()); // lancers dont l'animation est terminée
  const [erreur, setErreur] = useState("");
  const departageLance = useRef(false);
  const monte = useRef(true);
  const [fini, setFini] = useState(false); // tout le monde a lancé et mes relances de départage sont terminées

  async function lancer(m) {
    if (occupe) return;
    setOccupe(true);
    setErreur("");
    const r = await onLancer(m.id);
    if (r?.error) {
      setErreur(r.error);
      setOccupe(false);
      return;
    }
    setRecus((x) => ({ ...x, [m.id]: r }));
    setMessage(`${m.nom} lance le dé…`);
    await de.current?.lancer(r.de);
    setReveles((s) => new Set(s).add(m.id));
    setMessage(`${m.nom} : ${r.de} + ${r.velocite} (vélocité) = ${r.total}`);
    setOccupe(false);
  }

  // Quand tout le monde a lancé : relances de départage de mes mercenaires (décidées par le serveur), puis fermeture.
  useEffect(() => {
    if (!complete || occupe || departageLance.current) return;
    departageLance.current = true;
    (async () => {
      setOccupe(true);
      for (const m of engages) {
        const dep = rows.get(m.id)?.departage || [];
        if (!miens.has(m.id) || !dep.length) continue;
        for (const v of dep) {
          if (!monte.current) return;
          setMessage(`Égalité ! ${m.nom} relance le dé pour se départager…`);
          await de.current?.lancer(v);
          setMessage(`${m.nom} : départage ${v}`);
          await pause(900);
        }
      }
      if (!monte.current) return;
      setOccupe(false);
      setMessage("Tout le monde a lancé : vous pouvez fermer la fenêtre.");
      setFini(true);
    })();
  }, [complete, occupe]);
  useEffect(() => {
    monte.current = true;
    return () => {
      monte.current = false;
    };
  }, []);

  const resultat = (id) => {
    const r = recus[id];
    if (r && !reveles.has(id)) return null; // animation en cours : résultat pas encore révélé
    return rows.get(id) || r || null;
  };
  const enAttente = engages.filter((m) => !rows.get(m.id) && !recus[m.id] && !lancables.has(m.id));

  return (
    <div className="initiative-voile" role="dialog" aria-modal="true" aria-label="Lancer d’initiative">
      <div className="initiative-fenetre">
        <h2>Initiative</h2>
        <DeInitiative ref={de} />
        <p className="initiative-message" role="status">
          {message || "Lancez le dé de chacun de vos mercenaires."}
        </p>
        <ul className="initiative-liste">
          {engages.map((m) => {
            const r = resultat(m.id);
            const peutLancer = lancables.has(m.id) && !rows.get(m.id) && !recus[m.id];
            return (
              <li key={m.id}>
                <span className="initiative-nom">{m.nom}</span>
                {r ? (
                  <span className="initiative-resultat">
                    {r.de} + {r.velocite} = <strong>{r.total}</strong>
                    {complete && r.rang ? <span className="initiative-rang" title="Ordre de jeu">{r.rang}</span> : null}
                  </span>
                ) : peutLancer ? (
                  <button type="button" className="wood-button" disabled={occupe} onClick={() => lancer(m)}>
                    Lancer
                  </button>
                ) : (
                  <span className="muted">{recus[m.id] ? "…" : "En attente"}</span>
                )}
              </li>
            );
          })}
        </ul>
        {enAttente.length > 0 && !complete && (
          <p className="muted">En attente des autres joueurs ({enAttente.map((m) => m.nom).join(", ")}).</p>
        )}
        {erreur && (
          <p className="error" role="alert">
            {erreur}
          </p>
        )}
        {/* Fermer : grisé tant que tous les mercenaires engagés n’ont pas lancé (les créatures lancent seules dès le premier clic). Le MJ garde la main
            pour débloquer la situation si un joueur est absent. */}
        <p>
          <button
            type="button"
            className="wood-button initiative-fermer"
            disabled={!fini && !estAdmin}
            onClick={onClose}
            title={fini || estAdmin ? "Fermer la fenêtre" : "En attente : tous les mercenaires engagés doivent avoir lancé leur initiative"}
          >
            Fermer
          </button>
        </p>
      </div>
    </div>
  );
}
