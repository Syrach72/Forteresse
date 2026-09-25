import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "./supabaseClient";
import { Modal } from "./Modal.jsx";

// Sessions de jeu (voir docs/SESSIONS.md) : chaque équipe joue dans sa propre
// session, indépendante des autres. La session active de l'utilisateur est
// enregistrée en base (session_active) ; la changer recharge toute l'application.
//
// `ecran` (ce que la page affiche à la place du jeu) :
//   "chargement"  sessions pas encore lues
//   "aucune"      aucun accès à une session : saisir un code d'invitation
//   "choix"       plusieurs sessions et aucune choisie
//   "base"        le MJ édite la base de départ (pas de partie affichée)
//   "attente"     session choisie mais pas encore lancée par le MJ
//   null          la partie est jouable
export function useSessions(userId, estAdmin) {
  const [etat, setEtat] = useState({ pret: false, sessions: [], active: null, erreur: "" });
  const charger = useCallback(async () => {
    const [s, a] = await Promise.all([
      supabase.from("session").select("id, nom, lancee_le").order("nom"),
      supabase.from("session_active").select("session_id, contexte_base").maybeSingle(),
    ]);
    if (s.error) {
      setEtat((e) => ({ ...e, pret: true, erreur: s.error.message }));
      return;
    }
    setEtat({ pret: true, sessions: s.data || [], active: a.data || null, erreur: "" });
  }, []);
  useEffect(() => {
    if (userId) charger();
  }, [userId, charger]);

  const base = !!(estAdmin && etat.active?.contexte_base);
  const courante = useMemo(
    () =>
      base || !etat.active?.session_id
        ? null
        : etat.sessions.find((x) => x.id === etat.active.session_id) || null,
    [base, etat],
  );
  let ecran = null;
  if (!etat.pret) ecran = "chargement";
  else if (base) ecran = "base";
  else if (!etat.sessions.length) ecran = "aucune";
  else if (!courante) ecran = "choix";
  else if (!courante.lancee_le) ecran = "attente";

  // En attente du MJ : on relit la session toutes les 8 s ; dès qu'elle est lancée
  // on recharge la page pour charger la partie.
  const enAttente = ecran === "attente";
  useEffect(() => {
    if (!enAttente) return undefined;
    const id = setInterval(async () => {
      const { data } = await supabase.from("session").select("id, lancee_le").eq("id", courante.id).maybeSingle();
      if (data?.lancee_le) location.reload();
    }, 8000);
    return () => clearInterval(id);
  }, [enAttente, courante?.id]);

  return {
    pret: etat.pret,
    erreur: etat.erreur,
    sessions: etat.sessions,
    courante,
    base,
    ecran,
    recharger: charger,
    // Choisir une session (null = base de départ, MJ seulement), puis tout recharger.
    async choisir(id) {
      const { error } = await supabase.rpc("session_choisir", { p_session: id });
      if (error) return { error: error.message };
      location.reload();
      return {};
    },
    // Compte existant : rejoindre une session avec un code d'invitation.
    async rejoindre(code) {
      const { error } = await supabase.rpc("session_rejoindre", { p_code: code });
      if (error) return { error: error.message };
      location.reload();
      return {};
    },
    // Premier « +1 Instance » du MJ : lance la session (sans faire avancer de compteur).
    async lancer(id) {
      const { error } = await supabase.rpc("session_lancer", { p_session: id });
      if (error) return { error: error.message };
      return {};
    },
  };
}

function FormRejoindre({ onRejoindre }) {
  const [code, setCode] = useState("");
  const [erreur, setErreur] = useState("");
  const [busy, setBusy] = useState(false);
  return (
    <form
      className="session-rejoindre"
      onSubmit={async (e) => {
        e.preventDefault();
        if (!code.trim() || busy) return;
        setBusy(true);
        setErreur("");
        const r = await onRejoindre(code.trim());
        if (r?.error) {
          setErreur(r.error);
          setBusy(false);
        }
      }}
    >
      <label htmlFor="session-code">Code d’invitation</label>
      <input
        id="session-code"
        value={code}
        maxLength={12}
        autoComplete="off"
        placeholder="XXXX-XXXX"
        style={{ textTransform: "uppercase" }}
        onChange={(e) => setCode(e.target.value)}
      />
      <button className="wood-button" type="submit" disabled={!code.trim() || busy}>
        {busy ? "Vérification…" : "Rejoindre la session"}
      </button>
      {erreur && (
        <p className="error" role="alert">
          {erreur}
        </p>
      )}
    </form>
  );
}

// Bandeau en haut de la partie : nom de la session en cours et changement de session.
export function SessionBar({ sess, estAdmin }) {
  const [rejoindre, setRejoindre] = useState(false);
  const [erreur, setErreur] = useState("");
  const valeur = sess.base ? "__base" : sess.courante?.id || "";
  return (
    <div className="session-bar">
      <span className="session-bar-nom">
        <small>Session</small>{" "}
        <strong>
          {sess.base ? "Base de départ (édition)" : sess.courante?.nom || "aucune"}
        </strong>
        {sess.courante && !sess.courante.lancee_le && (
          <em className="session-bar-attente"> · en attente du lancement</em>
        )}
      </span>
      <label className="session-bar-choix">
        <span className="sr-only">Changer de session</span>
        <select
          value={valeur}
          onChange={async (e) => {
            const v = e.target.value;
            setErreur("");
            if (v === "__rejoindre") {
              setRejoindre(true);
              return;
            }
            const r = await sess.choisir(v === "__base" ? null : v);
            if (r.error) setErreur(r.error);
          }}
        >
          {!valeur && <option value="">Choisir une session…</option>}
          {sess.sessions.map((x) => (
            <option key={x.id} value={x.id}>
              {x.nom}
              {x.lancee_le ? "" : " (en attente)"}
            </option>
          ))}
          {estAdmin && <option value="__base">Base de départ (édition)</option>}
          <option value="__rejoindre">+ Rejoindre une session…</option>
        </select>
      </label>
      {erreur && (
        <span className="session-bar-erreur" role="alert">
          {erreur}
        </span>
      )}
      {rejoindre && (
        <Modal title="Rejoindre une session" onClose={() => setRejoindre(false)}>
          <p>Entrez le code d’invitation que le MJ vous a envoyé pour cette session.</p>
          <FormRejoindre onRejoindre={sess.rejoindre} />
        </Modal>
      )}
    </div>
  );
}

// Écran affiché à la place du jeu tant qu'aucune partie n'est jouable.
export function EcranSession({ sess, estAdmin }) {
  const { ecran, courante, sessions } = sess;
  return (
    <main id="main" className="interior session-ecran">
      <div className="interior-backdrop" style={{ backgroundImage: "url(/assets/castle-original.webp)" }} />
      <section className="parchment session-carte">
        {ecran === "chargement" && <p>Chargement de vos sessions…</p>}
        {ecran === "aucune" && (
          <>
            <h1>Aucune session pour le moment</h1>
            <p>
              Vous ne faites partie d’aucune session de jeu. Entrez le code d’invitation envoyé
              par le MJ pour rejoindre la vôtre.
            </p>
            <FormRejoindre onRejoindre={sess.rejoindre} />
          </>
        )}
        {(ecran === "choix" || ecran === "base") && (
          <>
            <h1>{ecran === "base" ? "Base de départ" : "Choisissez votre session"}</h1>
            {ecran === "base" && (
              <p>
                Vous éditez la base de départ (contenu copié dans chaque nouvelle session). Pour
                jouer ou diriger une partie, choisissez une session.
              </p>
            )}
            <div className="session-liste">
              {sessions.map((x) => (
                <button key={x.id} className="wood-button" type="button" onClick={() => sess.choisir(x.id)}>
                  {x.nom}
                  <small>{x.lancee_le ? "En cours" : "En attente du lancement"}</small>
                </button>
              ))}
            </div>
            {!sessions.length && <p className="muted">Aucune session créée pour le moment.</p>}
          </>
        )}
        {ecran === "attente" && (
          <>
            <h1>{courante.nom}</h1>
            <p className="session-attente">La partie n’a pas encore commencé.</p>
            {estAdmin ? (
              <p>
                Vous êtes le MJ : cliquez sur <strong>« +1 Instance »</strong> en haut de l’écran
                pour lancer la partie. Ce premier clic fixe le contenu de la session (catalogue,
                recettes, mercenaires, quêtes) et ne peut pas être annulé.
              </p>
            ) : (
              <p>
                En attente du MJ. Cette page se mettra à jour toute seule dès que la partie sera
                lancée : vous pourrez alors recruter et jouer.
              </p>
            )}
          </>
        )}
        {sess.erreur && (
          <p className="error" role="alert">
            {sess.erreur}
          </p>
        )}
      </section>
    </main>
  );
}
