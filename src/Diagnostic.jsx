import { useEffect, useState } from "react";
import { supabase } from "./supabaseClient";

// Page de diagnostic (#diagnostic) : affiche ce que la base renvoie au compte connecté, pour comprendre
// un solde ou un inventaire faux sur un appareil précis. Lecture seule, rien n'est modifié.
export function Diagnostic({ game, estAdmin, sess }) {
  const [rapport, setRapport] = useState("");
  const [busy, setBusy] = useState(false);

  async function lancer() {
    setBusy(true);
    const r = {};
    try {
      const { data: u } = await supabase.auth.getUser();
      r.compte = { id: u?.user?.id, email: u?.user?.email, admin_dans_l_appli: estAdmin };
      r.affichage = {
        or_affiche: game.gold,
        total_inventaire_affiche: game.inventory.reduce((a, b) => a + b.quantity, 0),
        lignes_inventaire_affichees: game.inventory.length,
        session_courante: sess.courante ? { id: sess.courante.id, nom: sess.courante.nom } : null,
        ecran_session: sess.ecran,
      };
      const lire = async (nom, requete) => {
        const { data, error, count } = await requete;
        r[nom] = error ? { erreur: error.message } : { lignes: count ?? data?.length, donnees: data };
      };
      await lire("session_active", supabase.from("session_active").select("*"));
      await lire("session_membre", supabase.from("session_membre").select("session_id, user_id"));
      await lire("partie_etat", supabase.from("partie_etat").select("session_id, or_compagnie, instance_courante, round_courant"));
      await lire("inventaires", supabase.from("inventaire").select("id, type, mercenaire_id, session_id"));
      const l = await supabase.from("ligne_inventaire").select("inventaire_id, quantite, session_id");
      r.lignes_inventaire = l.error
        ? { erreur: l.error.message }
        : {
            lignes: l.data.length,
            somme_quantites: l.data.reduce((a, b) => a + b.quantite, 0),
            par_inventaire: Object.entries(
              l.data.reduce((m, x) => ({ ...m, [x.inventaire_id]: (m[x.inventaire_id] || 0) + x.quantite }), {}),
            ),
          };
    } catch (e) {
      r.exception = String(e?.message || e);
    }
    setRapport(JSON.stringify(r, null, 2));
    setBusy(false);
  }

  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 9999,
        overflow: "auto",
        background: "#f4ecd8",
        color: "#222",
        padding: 16,
        fontSize: 14,
      }}
    >
      <h2 style={{ marginTop: 0 }}>Diagnostic</h2>
      <p>
        Appuie sur le bouton, puis fais une capture d’écran du résultat. Rien n’est modifié.
      </p>
      <button type="button" className="wood-button" onClick={lancer} disabled={busy}>
        {busy ? "Lecture…" : "Lancer le diagnostic"}
      </button>{" "}
      <a href="#forteresse">Retour</a>
      <p>
        <button
          type="button"
          className="wood-button"
          onClick={() => {
            try {
              const on = localStorage.getItem("fortress-debug") === "1";
              localStorage.setItem("fortress-debug", on ? "0" : "1");
              alert(on ? "Badge de debug désactivé." : "Badge de debug activé : il s'affiche en bas de chaque page.");
            } catch {
              alert("Impossible d'enregistrer le réglage sur ce navigateur.");
            }
          }}
        >
          Activer / désactiver le badge de debug
        </button>
      </p>
      <pre style={{ whiteSpace: "pre-wrap", wordBreak: "break-all", marginTop: 12, fontSize: 12 }}>{rapport}</pre>
    </div>
  );
}

// Badge de debug (activé depuis #diagnostic, mémorisé dans ce navigateur) : affiche en bas de chaque page
// ce que l'application a en mémoire (or, inventaire) et le dernier résultat de la synchronisation.
export function DebugBadge({ game, route }) {
  const [, setT] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setT((v) => v + 1), 1000);
    return () => clearInterval(id);
  }, []);
  let actif = false;
  try {
    actif = localStorage.getItem("fortress-debug") === "1";
  } catch {
    actif = false;
  }
  if (!actif || route === "diagnostic") return null;
  const s = window.__dernierSync || {};
  return (
    <div
      style={{
        position: "fixed", left: 0, right: 0, bottom: 0, zIndex: 9998, background: "#000c", color: "#0f0",
        fontSize: 11, padding: "4px 8px", fontFamily: "monospace", lineHeight: 1.3, pointerEvents: "none",
      }}
    >
      route={route} | game.gold={String(game.gold)} ({typeof game.gold}) | inv={game.inventory.reduce((a, b) => a + b.quantity, 0)}
      <br />
      sync: {s.t ? new Date(s.t).toLocaleTimeString() : "jamais"} | etat.or={String(s.or)} | etat.err={s.err || "-"} | n={s.n || 0}
    </div>
  );
}
