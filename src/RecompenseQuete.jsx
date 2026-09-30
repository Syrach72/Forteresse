import { useEffect, useState } from "react";
import { Modal } from "./Modal.jsx";
import { supabase } from "./supabaseClient";

// Fenêtre de fin de quête : montre les récompenses (objets, or, et la récompense mystère « ? » qui
// se transforme en objet tiré au hasard). Les récompenses ne rejoignent la compagnie qu'à la
// fermeture de la fenêtre (onClose déclenche la récupération côté serveur).
export function RecompenseQuete({ recompense, onClose }) {
  const [objets, setObjets] = useState({});
  const [revele, setRevele] = useState(false);
  const [busy, setBusy] = useState(false);
  const items = recompense.items || [];
  const mystere = items.find((i) => i.mystere);
  const fixes = items.filter((i) => !i.mystere);

  useEffect(() => {
    let vivant = true;
    const ids = items.map((i) => i.objet_id);
    if (ids.length) {
      supabase
        .from("objet_catalogue")
        .select("id, nom, icone")
        .in("id", ids)
        .then(({ data }) => {
          if (vivant && data) setObjets(Object.fromEntries(data.map((o) => [o.id, o])));
        });
    }
    // Le « ? » tremble un instant, puis se transforme (aussitôt si les animations sont réduites).
    const reduit = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
    const t = setTimeout(() => vivant && setRevele(true), reduit ? 0 : 1500);
    return () => {
      vivant = false;
      clearTimeout(t);
    };
  }, []);

  async function fermer() {
    if (busy) return;
    setBusy(true);
    await onClose();
  }

  const objMyst = mystere && objets[mystere.objet_id];
  return (
    <Modal title={`Quête accomplie : ${recompense.nom}`} onClose={fermer} className="recompense-quete">
      <div className="recompense-grille">
        {fixes.map((i, n) => {
          const o = objets[i.objet_id];
          return (
            <div className="recompense-case" key={n}>
              <span className="recompense-vignette">
                {o?.icone && <img src={o.icone} alt="" />}
                {i.quantite > 1 && <span className="quest-reward-qty">×{i.quantite}</span>}
              </span>
              <span className="recompense-nom">{o?.nom || "…"}</span>
            </div>
          );
        })}
        {recompense.or > 0 && (
          <div className="recompense-case">
            <span className="recompense-vignette recompense-or">{recompense.or} Po</span>
            <span className="recompense-nom">Or</span>
          </div>
        )}
        {mystere && (
          <div className={`recompense-case${revele ? " recompense-revele" : ""}`}>
            <span className="recompense-vignette recompense-mystere">
              {!revele && <img className="recompense-point" src="/assets/icons/mystere.webp" alt="" />}
              {revele && objMyst?.icone && <img className="recompense-objet" src={objMyst.icone} alt="" />}
              {revele && <span className="recompense-eclat" aria-hidden="true" />}
            </span>
            <span className="recompense-nom">{revele ? objMyst?.nom || "…" : "Récompense mystère"}</span>
          </div>
        )}
      </div>
      <p className="muted">Ces récompenses rejoignent l’arsenal de la compagnie dès que vous fermez cette fenêtre.</p>
      <button type="button" className="wood-button" onClick={fermer} disabled={busy}>
        {busy ? "…" : "Récupérer les récompenses"}
      </button>
    </Modal>
  );
}
