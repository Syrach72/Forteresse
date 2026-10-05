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
//   "radie"       le joueur est radié de la session choisie (temporairement ou définitivement)
//   "attente"     session choisie mais pas encore lancée par le MJ
//   null          la partie est jouable
export function useSessions(userId, estAdmin) {
  const [etat, setEtat] = useState({ pret: false, sessions: [], active: null, membres: [], erreur: "" });
  const charger = useCallback(async () => {
    const [s, a, mb] = await Promise.all([
      supabase.from("session").select("id, nom, lancee_le").order("nom"),
      supabase.from("session_active").select("session_id, contexte_base").maybeSingle(),
      // Mon appartenance à chaque session : pseudo de session et radiation éventuelle.
      supabase.from("session_membre").select("session_id, pseudo, radie_jusqua, radie_definitive").eq("user_id", userId),
    ]);
    if (s.error) {
      setEtat((e) => ({ ...e, pret: true, erreur: s.error.message }));
      return;
    }
    setEtat({ pret: true, sessions: s.data || [], active: a.data || null, membres: mb.data || [], erreur: "" });
  }, [userId]);
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
  // Radiation en cours dans la session choisie (la fin d'une radiation de 24 h est comparée à l'heure).
  const radieEnCours = (m) => !!m && (m.radie_definitive || (!!m.radie_jusqua && new Date(m.radie_jusqua).getTime() > Date.now()));
  const membreActif = etat.membres.find((m) => m.session_id === etat.active?.session_id);
  const radiation = !base && radieEnCours(membreActif) ? membreActif : null;
  // Mon appartenance à la session en cours (absente pour le MJ, qui n'a pas de pseudo de session).
  const membreCourante = courante ? etat.membres.find((m) => m.session_id === courante.id) || null : null;
  let ecran = null;
  if (!etat.pret) ecran = "chargement";
  else if (base) ecran = "base";
  else if (radiation) ecran = "radie";
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

  // Radiation temporaire : la page se recharge toute seule à la fin du délai.
  const finRadiation = radiation && !radiation.radie_definitive ? new Date(radiation.radie_jusqua).getTime() : null;
  useEffect(() => {
    if (!finRadiation) return undefined;
    const t = setTimeout(() => location.reload(), Math.min(Math.max(finRadiation - Date.now(), 0) + 1500, 2147000000));
    return () => clearTimeout(t);
  }, [finRadiation]);

  return {
    pret: etat.pret,
    radiation,
    membreCourante,
    monPseudo: membreCourante?.pseudo ?? null,
    // Pseudo utilisé pour cette session (2 à 24 caractères, unique dans la session).
    async definirPseudo(pseudo) {
      const { error } = await supabase.rpc("session_pseudo_definir", { p_pseudo: pseudo });
      if (error) return { error: error.message };
      await charger();
      return {};
    },
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

// Pseudo utilisé pour cette session : saisi à l'entrée dans la session, modifiable ensuite.
function FormPseudo({ initial, onEnregistrer }) {
  const [pseudo, setPseudo] = useState(initial || "");
  const [erreur, setErreur] = useState("");
  const [busy, setBusy] = useState(false);
  return (
    <form
      className="session-rejoindre"
      onSubmit={async (e) => {
        e.preventDefault();
        if (pseudo.trim().length < 2 || busy) return;
        setBusy(true);
        setErreur("");
        const r = await onEnregistrer(pseudo.trim());
        setBusy(false);
        if (r?.error) setErreur(r.error);
      }}
    >
      <label htmlFor="session-pseudo">Pseudo utilisé pour cette session</label>
      <input
        id="session-pseudo"
        value={pseudo}
        maxLength={24}
        autoComplete="off"
        placeholder="Votre nom dans cette partie"
        onChange={(e) => setPseudo(e.target.value)}
      />
      <button className="wood-button" type="submit" disabled={pseudo.trim().length < 2 || busy}>
        {busy ? "Enregistrement…" : "Enregistrer le pseudo"}
      </button>
      {erreur && (
        <p className="error" role="alert">
          {erreur}
        </p>
      )}
    </form>
  );
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
export function SessionBar({ sess, estAdmin, pseudoCompte = "" }) {
  const [rejoindre, setRejoindre] = useState(false);
  const [pseudoOuvert, setPseudoOuvert] = useState(false);
  // Un joueur qui entre dans la session sans pseudo doit d'abord en choisir un.
  const pseudoRequis = !estAdmin && !!sess.membreCourante && !sess.monPseudo && !!sess.courante?.lancee_le;
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
      {sess.membreCourante && sess.monPseudo && (
        <span className="session-bar-pseudo">
          <small>Pseudo utilisé pour cette session :</small> <strong>{sess.monPseudo}</strong>{" "}
          <button type="button" className="text-button" onClick={() => setPseudoOuvert(true)}>
            Modifier
          </button>
        </span>
      )}
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
      {(pseudoRequis || pseudoOuvert) && (
        <Modal title="Pseudo utilisé pour cette session" onClose={() => setPseudoOuvert(false)}>
          <p>
            Ce pseudo est le nom inscrit sur les mercenaires que vous recrutez dans cette session. Il est propre à
            cette session et chaque joueur a le sien.
          </p>
          <FormPseudo
            initial={sess.monPseudo || pseudoCompte}
            onEnregistrer={async (p) => {
              const r = await sess.definirPseudo(p);
              if (!r.error) setPseudoOuvert(false);
              return r;
            }}
          />
        </Modal>
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
        {ecran === "radie" && sess.radiation && (
          <>
            <h1>Vous êtes radié de cette session</h1>
            {sess.radiation.radie_definitive ? (
              <>
                <p>
                  Le MJ vous a radié définitivement de cette session. Si vous devez y revenir, demandez-lui une
                  nouvelle invitation et saisissez-la ci-dessous : votre compte n’est pas bloqué.
                </p>
                <FormRejoindre onRejoindre={sess.rejoindre} />
              </>
            ) : (
              <p>
                Le MJ vous a radié de cette session jusqu’au{" "}
                <strong>{new Date(sess.radiation.radie_jusqua).toLocaleString("fr-FR", { dateStyle: "long", timeStyle: "short" })}</strong>.
                Vos mercenaires restent à la Caserne : d’autres joueurs peuvent les utiliser en attendant. Cette page
                se rouvrira toute seule à la fin du délai.
              </p>
            )}
            {sessions.length > 0 && (
              <>
                <p className="muted">Vous pouvez jouer dans une autre de vos sessions :</p>
                <div className="session-liste">
                  {sessions.map((x) => (
                    <button key={x.id} className="wood-button" type="button" onClick={() => sess.choisir(x.id)}>
                      {x.nom}
                    </button>
                  ))}
                </div>
              </>
            )}
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
