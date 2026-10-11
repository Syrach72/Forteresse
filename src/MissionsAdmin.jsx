import { useState } from "react";
import { STATS_EFFET, libelleEffet } from "./effets.js";

// Missions : rédigées ici par l'administrateur, en quatre étapes (pour qui, quoi, quelle récompense, quel texte).
// Chaque événement du menu se déclenche tout seul côté serveur. « autre » (code a_brancher) ne sert qu'à noter une
// idée qui n'est pas encore automatique : la mission est enregistrée mais ne se déclenche pas.
const EVENEMENTS_MISSION = [
  {
    code: "recrutement_paye",
    label: "Embaucher un mercenaire (payant)",
    phrase: "embauche un mercenaire contre de l’or",
    detail: "Compte chaque mercenaire embauché contre de l’or. Le premier mercenaire, gratuit, ne compte pas.",
  },
  {
    code: "quete_reussie",
    label: "Réussir une quête",
    phrase: "réussit une quête",
    detail:
      "Une quête est accomplie. Pour un joueur : il avait au moins un de ses mercenaires engagés dans la quête.",
  },
  {
    code: "quete_reussie_sans_blessure",
    label: "Réussir une quête sans blessé",
    phrase: "réussit une quête sans qu’aucun mercenaire engagé soit blessé",
    detail:
      "Une quête est accomplie et aucun mercenaire engagé n’a perdu de PV. Pour un joueur : il avait au moins un de ses mercenaires engagés.",
  },
  {
    code: "quete_echouee",
    label: "Échouer une quête",
    phrase: "échoue une quête",
    detail:
      "Le MJ déclare la quête échouée. Pour un joueur : il avait au moins un de ses mercenaires engagés dans la quête.",
  },
  {
    code: "niveau_gagne",
    label: "Un mercenaire gagne un niveau de vétérance",
    phrase: "voit un mercenaire gagner un niveau de vétérance",
    detail:
      "Compte chaque niveau gagné (quête, entraînement ou correction du MJ). Pour un joueur : un de ses mercenaires.",
  },
  {
    code: "entrainement_termine",
    label: "Terminer un entraînement",
    phrase: "termine l’entraînement d’un élève (il rejoint le niveau de son instructeur)",
    detail:
      "Un élève arrive au niveau de son instructeur. Un renvoi anticipé ne compte pas. Pour un joueur : l’élève est l’un de ses mercenaires.",
  },
  {
    code: "a_brancher",
    label: "Autre chose (pas encore automatique)",
    phrase: "fait ce qui est décrit ci-dessous",
    detail:
      "La mission est enregistrée mais ne se déclenchera pas toute seule : elle ne sert qu’à noter une idée. Décrivez-la dans la case prévue.",
  },
];
const evenement = (code) => EVENEMENTS_MISSION.find((e) => e.code === code);

function missionVide(ordre = "10") {
  return {
    id: null,
    rubrique: "individuelle",
    nom: "",
    description: "",
    evenement: "quete_reussie",
    seuil: "1",
    or: "0",
    objetId: "",
    quantite: "1",
    effetStat: "",
    effetValeur: "1",
    effetQuetes: "1",
    cachee: false,
    actif: true,
    ordre,
    note: "",
  };
}

// `kit` : { useTable, DeleteButton, SearchableSelect } fournis par Admin.jsx (évite un import circulaire).
export function MissionsSection({ kit }) {
  const { useTable, DeleteButton, SearchableSelect } = kit;
  const missions = useTable("mission", { order: "ordre" });
  const catalogue = useTable("objet_catalogue", { order: "nom" });
  const [f, setF] = useState(missionVide());
  // Nom de la mission en cours de modification (titre du formulaire, stable pendant la saisie).
  const [nomEdite, setNomEdite] = useState("");
  const [msg, setMsg] = useState("");
  const [confirmingId, setConfirmingId] = useState(null);
  if (missions.error || catalogue.error) return <p className="admin-error">{missions.error || catalogue.error}</p>;
  if (!missions.rows || !catalogue.rows) return <p>Chargement…</p>;
  const nomObjet = (id) => catalogue.rows.find((o) => o.id === id)?.nom || "—";
  const set = (k, v) => setF((x) => ({ ...x, [k]: v }));
  const ordreSuivant = () => String(Math.max(0, ...missions.rows.map((m) => Number(m.ordre) || 0)) + 10);
  const triees = [...missions.rows].sort((a, b) => (a.ordre ?? 0) - (b.ordre ?? 0) || a.nom.localeCompare(b.nom));
  function charger(m) {
    setMsg("");
    setNomEdite(m.nom);
    setF({
      id: m.id,
      rubrique: m.rubrique,
      nom: m.nom,
      description: m.description || "",
      evenement: m.evenement,
      seuil: String(m.seuil),
      or: String(m.recompense_or),
      objetId: m.recompense_objet_id || "",
      quantite: String(m.recompense_quantite),
      effetStat: m.recompense_effet_stat || "",
      effetValeur: String(m.recompense_effet_valeur ?? 1),
      effetQuetes: String(m.recompense_effet_quetes ?? 1),
      cachee: !!m.recompense_cachee,
      actif: !!m.actif,
      ordre: String(m.ordre),
      note: m.declencheur_note || "",
    });
    window.scrollTo({ top: 0, behavior: "smooth" });
  }
  async function enregistrer(e) {
    e.preventDefault();
    setMsg("");
    if (!f.nom.trim()) return setMsg("Donnez un nom à la mission (étape 4).");
    const entier = (v, min) => Math.max(min, Math.round(Number(v) || 0));
    const individuelle = f.rubrique === "individuelle";
    const values = {
      rubrique: f.rubrique,
      nom: f.nom.trim(),
      description: f.description.trim(),
      evenement: f.evenement,
      seuil: entier(f.seuil, 1),
      recompense_or: entier(f.or, 0),
      recompense_objet_id: f.objetId || null,
      recompense_quantite: entier(f.quantite, 1),
      // Effet temporaire : réservé aux missions individuelles.
      recompense_effet_stat: individuelle && f.effetStat ? f.effetStat : null,
      recompense_effet_valeur: individuelle && f.effetStat ? Math.min(99, entier(f.effetValeur, 1)) : null,
      recompense_effet_quetes: Math.min(3, entier(f.effetQuetes, 1)),
      recompense_cachee: f.cachee,
      actif: f.actif,
      ordre: entier(f.ordre, 0),
      declencheur_note: f.evenement === "a_brancher" ? f.note.trim() : "",
    };
    const slug = f.nom
      .trim()
      .toLowerCase()
      .normalize("NFD")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "");
    const erreur = f.id
      ? await missions.update(f.id, values)
      : await missions.insert({ ...values, code: `${slug}-${Math.random().toString(36).slice(2, 6)}` });
    if (erreur) return setMsg(erreur);
    setF(missionVide(String(Number(ordreSuivant()) + 10)));
    setMsg("Mission enregistrée.");
  }
  async function supprimer(id) {
    const erreur = await missions.remove(id);
    setMsg(erreur || "Mission supprimée.");
    if (f.id === id) setF(missionVide(ordreSuivant()));
  }
  // Monter ou descendre une mission dans la liste : on renumérote tout (10, 20, 30…) puis on échange.
  async function deplacer(id, delta) {
    const liste = [...triees];
    const i = liste.findIndex((m) => m.id === id);
    const j = i + delta;
    if (i < 0 || j < 0 || j >= liste.length) return;
    [liste[i], liste[j]] = [liste[j], liste[i]];
    for (let k = 0; k < liste.length; k++) {
      const ordre = (k + 1) * 10;
      if (liste[k].ordre !== ordre) {
        const erreur = await missions.update(liste[k].id, { ordre });
        if (erreur) return setMsg(erreur);
      }
    }
  }
  async function basculerActive(m) {
    const erreur = await missions.update(m.id, { actif: !m.actif });
    if (erreur) setMsg(erreur);
  }
  const recompense = (m) =>
    [
      m.recompense_or > 0 ? `${m.recompense_or} Po` : "",
      m.recompense_objet_id ? `${nomObjet(m.recompense_objet_id)} ×${m.recompense_quantite}` : "",
      m.recompense_effet_stat ? libelleEffet(m.recompense_effet_stat, m.recompense_effet_valeur, m.recompense_effet_quetes) : "",
    ]
      .filter(Boolean)
      .join(" + ") || "—";

  const ev = evenement(f.evenement);
  const individuelle = f.rubrique === "individuelle";
  const seuil = Math.max(1, Math.round(Number(f.seuil) || 1));
  const recompenseForm = [
    Number(f.or) > 0 ? `${Math.round(Number(f.or))} Po` : "",
    f.objetId ? `${nomObjet(f.objetId)} ×${Math.max(1, Math.round(Number(f.quantite) || 1))}` : "",
    individuelle && f.effetStat
      ? libelleEffet(f.effetStat, Math.max(1, Number(f.effetValeur) || 1), Math.min(3, Number(f.effetQuetes) || 1))
      : "",
  ]
    .filter(Boolean)
    .join(" + ");

  return (
    <div className="admin-section">
      <h2>Missions</h2>
      <p className="muted">
        Une mission donne une récompense automatique quand quelque chose se produit en jeu. Répondez aux quatre étapes
        ci-dessous, le résumé en bas du formulaire dit en une phrase ce que fera la mission.
      </p>
      <form className="admin-form admin-form-missions" onSubmit={enregistrer}>
        <h3>{f.id ? `Modifier la mission : ${nomEdite}` : "Nouvelle mission"}</h3>

        <fieldset className="mission-etape">
          <legend>1. Pour qui ?</legend>
          <label className={`mission-choix${individuelle ? " choisi" : ""}`}>
            <input
              type="radio"
              name="rubrique"
              checked={individuelle}
              onChange={() => set("rubrique", "individuelle")}
            />
            <span>
              <strong>Un joueur</strong>
              <small>
                Chaque joueur a sa propre mission. S’il y a un objet, il le donne à l’un de ses mercenaires.
              </small>
            </span>
          </label>
          <label className={`mission-choix${!individuelle ? " choisi" : ""}`}>
            <input
              type="radio"
              name="rubrique"
              checked={!individuelle}
              onChange={() => set("rubrique", "collective")}
            />
            <span>
              <strong>Toute la compagnie</strong>
              <small>Les joueurs comptent ensemble. L’or va à la trésorerie, l’objet à l’arsenal.</small>
            </span>
          </label>
        </fieldset>

        <fieldset className="mission-etape">
          <legend>2. Que doit-il se passer ?</legend>
          <label>
            Événement
            <select value={f.evenement} onChange={(e) => set("evenement", e.target.value)}>
              {EVENEMENTS_MISSION.map((e) => (
                <option key={e.code} value={e.code}>
                  {e.label}
                </option>
              ))}
            </select>
          </label>
          {ev && <p className="mission-aide">{ev.detail}</p>}
          {f.evenement === "a_brancher" && (
            <label>
              Décrivez ce qui doit déclencher la mission
              <textarea rows={2} value={f.note} onChange={(e) => set("note", e.target.value)} />
            </label>
          )}
          <label>
            Combien de fois ?
            <input type="number" min="1" step="1" value={f.seuil} onChange={(e) => set("seuil", e.target.value)} />
          </label>
          <p className="mission-aide">
            {individuelle
              ? "Compté séparément pour chaque joueur."
              : "Compté pour toute la compagnie, tous joueurs confondus."}
          </p>
        </fieldset>

        <fieldset className="mission-etape">
          <legend>3. Quelle récompense ?</legend>
          <label>
            Or (Po)
            <input type="number" min="0" step="1" value={f.or} onChange={(e) => set("or", e.target.value)} />
          </label>
          <label>
            Objet du catalogue
            <SearchableSelect
              value={f.objetId}
              onChange={(v) => set("objetId", v)}
              options={catalogue.rows.map((o) => ({ value: o.id, label: o.nom }))}
              emptyLabel="Aucun objet"
              ariaLabel="Objet de récompense"
            />
          </label>
          {f.objetId && (
            <label>
              Quantité
              <input type="number" min="1" step="1" value={f.quantite} onChange={(e) => set("quantite", e.target.value)} />
            </label>
          )}
          {individuelle && (
            <>
              <label>
                Effet temporaire (facultatif)
                <select value={f.effetStat} onChange={(e) => set("effetStat", e.target.value)}>
                  <option value="">Aucun effet</option>
                  {STATS_EFFET.map(([v, l]) => (
                    <option key={v} value={v}>
                      {l}
                    </option>
                  ))}
                </select>
              </label>
              {f.effetStat ? (
                <>
                  <label>
                    Valeur de l’effet (par exemple 2 pour +2)
                    <input type="number" min="1" max="99" step="1" value={f.effetValeur} onChange={(e) => set("effetValeur", e.target.value)} />
                  </label>
                  {f.effetStat !== "pv_temp" && (
                    <label>
                      Pendant combien de quêtes du bénéficiaire ?
                      <select value={f.effetQuetes} onChange={(e) => set("effetQuetes", e.target.value)}>
                        <option value="1">1 quête</option>
                        <option value="2">2 quêtes</option>
                        <option value="3">3 quêtes</option>
                      </select>
                    </label>
                  )}
                  <p className="mission-aide">
                    L’effet ne sert que pendant la prochaine quête du mercenaire choisi, qu’elle réussisse ou échoue, et ne
                    peut pas être transféré.
                  </p>
                </>
              ) : (
                <p className="mission-aide">
                  Un effet temporaire est un bonus (caractéristique, énergie, PV…) donné à un mercenaire pour sa
                  prochaine quête.
                </p>
              )}
            </>
          )}
          <label className="admin-check">
            <input type="checkbox" checked={f.cachee} onChange={(e) => set("cachee", e.target.checked)} />
            Cacher la récompense (« ? » tant que la mission n’est pas accomplie)
          </label>
        </fieldset>

        <fieldset className="mission-etape">
          <legend>4. Que lisent les joueurs ?</legend>
          <label>
            Nom de la mission
            <input value={f.nom} onChange={(e) => set("nom", e.target.value)} placeholder="Première recrue" />
          </label>
          <label>
            Description (facultative)
            <textarea rows={2} value={f.description} onChange={(e) => set("description", e.target.value)} />
          </label>
          <label className="admin-check">
            <input type="checkbox" checked={f.actif} onChange={(e) => set("actif", e.target.checked)} />
            Mission active (décochez pour la mettre de côté sans la supprimer)
          </label>
        </fieldset>

        <p className="mission-resume" role="status">
          <strong>Résumé : </strong>
          {individuelle ? "Chaque joueur qui " : "Dès que la compagnie "}
          {ev?.phrase}
          {seuil > 1 ? `, ${seuil} fois,` : ""} reçoit{" "}
          {recompenseForm || <em>(aucune récompense choisie)</em>}
          {f.evenement === "a_brancher" ? " — mais ne se déclenchera pas toute seule." : "."}
        </p>

        <div className="admin-row-actions">
          <button className="text-button" type="submit">
            {f.id ? "Enregistrer les modifications" : "Ajouter la mission"}
          </button>
          {f.id && (
            <button className="text-button" type="button" onClick={() => setF(missionVide(ordreSuivant()))}>
              Annuler la modification
            </button>
          )}
        </div>
        {msg && <p className="admin-error">{msg}</p>}
      </form>

      <h3>Missions existantes</h3>
      <table className="admin-table">
        <thead>
          <tr>
            <th>Mission</th>
            <th>Pour qui</th>
            <th>Se déclenche quand</th>
            <th>Récompense</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {triees.map((m, i) => (
            <tr key={m.id} className={m.actif ? "" : "admin-row-inactive"}>
              <td>
                <strong>{m.nom}</strong>
                {!m.actif && " (désactivée)"}
                <br />
                <small>{m.description}</small>
              </td>
              <td>{m.rubrique === "collective" ? "Toute la compagnie" : "Un joueur"}</td>
              <td>
                {evenement(m.evenement)?.label || m.evenement}
                {m.seuil > 1 ? ` ×${m.seuil}` : ""}
                {m.evenement === "a_brancher" && (
                  <>
                    <br />
                    <small>
                      <em>Pas automatique.</em> {m.declencheur_note}
                    </small>
                  </>
                )}
              </td>
              <td>
                {recompense(m)}
                {m.recompense_cachee && " (cachée)"}
              </td>
              <td className="admin-row-actions">
                <button
                  type="button"
                  className="text-button"
                  onClick={() => deplacer(m.id, -1)}
                  disabled={i === 0}
                  aria-label={`Monter ${m.nom}`}
                  title="Monter dans la liste"
                >
                  ↑
                </button>
                <button
                  type="button"
                  className="text-button"
                  onClick={() => deplacer(m.id, 1)}
                  disabled={i === triees.length - 1}
                  aria-label={`Descendre ${m.nom}`}
                  title="Descendre dans la liste"
                >
                  ↓
                </button>
                <button type="button" className="text-button" onClick={() => charger(m)}>
                  Modifier
                </button>
                <button type="button" className="text-button" onClick={() => basculerActive(m)}>
                  {m.actif ? "Désactiver" : "Activer"}
                </button>
                <DeleteButton
                  id={m.id}
                  confirmingId={confirmingId}
                  onAskConfirm={() => setConfirmingId(m.id)}
                  onCancel={() => setConfirmingId(null)}
                  onConfirm={() => {
                    setConfirmingId(null);
                    supprimer(m.id);
                  }}
                />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {!missions.rows.length && <p className="muted">Aucune mission pour le moment.</p>}
    </div>
  );
}
