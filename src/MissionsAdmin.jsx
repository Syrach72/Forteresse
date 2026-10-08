import { useState } from "react";

// Missions : rédigées ici par l'administrateur. L'événement choisi décide du déclenchement ; « À brancher »
// signifie que la mission existe mais ne se déclenche pas encore (le déclencheur se branche ensuite, sur demande) :
// la note décrit alors, en mots, ce qui doit la déclencher.
const EVENEMENTS_MISSION = [
  ["recrutement_paye", "Mercenaire embauché contre de l’or (le premier, gratuit, ne compte pas)"],
  ["quete_reussie", "Quête réussie"],
  ["a_brancher", "À brancher (décrivez-le dans la note)"],
];

function missionVide() {
  return {
    id: null,
    rubrique: "individuelle",
    nom: "",
    description: "",
    evenement: "a_brancher",
    seuil: "1",
    or: "0",
    objetId: "",
    quantite: "1",
    cachee: false,
    actif: true,
    ordre: "0",
    note: "",
  };
}

// `kit` : { useTable, DeleteButton, SearchableSelect } fournis par Admin.jsx (évite un import circulaire).
export function MissionsSection({ kit }) {
  const { useTable, DeleteButton, SearchableSelect } = kit;
  const missions = useTable("mission", { order: "ordre" });
  const catalogue = useTable("objet_catalogue", { order: "nom" });
  const [f, setF] = useState(missionVide());
  const [msg, setMsg] = useState("");
  const [confirmingId, setConfirmingId] = useState(null);
  if (missions.error || catalogue.error) return <p className="admin-error">{missions.error || catalogue.error}</p>;
  if (!missions.rows || !catalogue.rows) return <p>Chargement…</p>;
  const nomObjet = (id) => catalogue.rows.find((o) => o.id === id)?.nom || "—";
  const set = (k, v) => setF((x) => ({ ...x, [k]: v }));
  function charger(m) {
    setMsg("");
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
    if (!f.nom.trim()) return setMsg("Donnez un nom à la mission.");
    const entier = (v, min) => Math.max(min, Math.round(Number(v) || 0));
    const values = {
      rubrique: f.rubrique,
      nom: f.nom.trim(),
      description: f.description.trim(),
      evenement: f.evenement,
      seuil: entier(f.seuil, 1),
      recompense_or: entier(f.or, 0),
      recompense_objet_id: f.objetId || null,
      recompense_quantite: entier(f.quantite, 1),
      recompense_cachee: f.cachee,
      actif: f.actif,
      ordre: entier(f.ordre, 0),
      declencheur_note: f.note.trim(),
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
    setF(missionVide());
    setMsg("Mission enregistrée.");
  }
  async function supprimer(id) {
    const erreur = await missions.remove(id);
    setMsg(erreur || "Mission supprimée.");
    if (f.id === id) setF(missionVide());
  }
  const recompense = (m) =>
    [
      m.recompense_or > 0 ? `${m.recompense_or} Po` : "",
      m.recompense_objet_id ? `${nomObjet(m.recompense_objet_id)} ×${m.recompense_quantite}` : "",
    ]
      .filter(Boolean)
      .join(" + ") || "—";
  return (
    <div className="admin-section">
      <h2>Missions</h2>
      <p className="muted">
        Une mission donne une récompense automatique (or et/ou objet du catalogue) quand son événement se produit.
        Choisissez « À brancher » si l’événement n’existe pas encore : décrivez-le dans la note, il sera branché sur
        demande.
      </p>
      <form className="admin-form" onSubmit={enregistrer}>
        <h3>{f.id ? "Modifier la mission" : "Nouvelle mission"}</h3>
        <label>
          Rubrique
          <select value={f.rubrique} onChange={(e) => set("rubrique", e.target.value)}>
            <option value="individuelle">Individuelle (cadeau pour le joueur : objet à donner à un de ses mercenaires)</option>
            <option value="collective">Collective (cadeau pour la compagnie)</option>
          </select>
        </label>
        <label>
          Nom
          <input value={f.nom} onChange={(e) => set("nom", e.target.value)} placeholder="Première recrue" />
        </label>
        <label>
          Description (visible des joueurs)
          <textarea rows={2} value={f.description} onChange={(e) => set("description", e.target.value)} />
        </label>
        <label>
          Événement déclencheur
          <select value={f.evenement} onChange={(e) => set("evenement", e.target.value)}>
            {EVENEMENTS_MISSION.map(([v, l]) => (
              <option key={v} value={v}>
                {l}
              </option>
            ))}
          </select>
        </label>
        <label>
          Note pour le branchement (ce qui doit déclencher la mission)
          <textarea rows={2} value={f.note} onChange={(e) => set("note", e.target.value)} />
        </label>
        <label>
          Nombre de fois requis (seuil)
          <input type="number" min="1" step="1" value={f.seuil} onChange={(e) => set("seuil", e.target.value)} />
        </label>
        <label>
          Récompense : or (Po)
          <input type="number" min="0" step="1" value={f.or} onChange={(e) => set("or", e.target.value)} />
        </label>
        <label>
          Récompense : objet du catalogue
          <SearchableSelect
            value={f.objetId}
            onChange={(v) => set("objetId", v)}
            options={catalogue.rows.map((o) => ({ value: o.id, label: o.nom }))}
            emptyLabel="Aucun objet"
            ariaLabel="Objet de récompense"
          />
        </label>
        <label>
          Quantité de l’objet
          <input type="number" min="1" step="1" value={f.quantite} onChange={(e) => set("quantite", e.target.value)} />
        </label>
        <label>
          Ordre d’affichage
          <input type="number" min="0" step="1" value={f.ordre} onChange={(e) => set("ordre", e.target.value)} />
        </label>
        <label className="admin-check">
          <input type="checkbox" checked={f.cachee} onChange={(e) => set("cachee", e.target.checked)} />
          Récompense cachée (« ? » tant que la mission n’est pas accomplie)
        </label>
        <label className="admin-check">
          <input type="checkbox" checked={f.actif} onChange={(e) => set("actif", e.target.checked)} />
          Mission active
        </label>
        <div className="admin-row-actions">
          <button className="text-button" type="submit">
            {f.id ? "Enregistrer les modifications" : "Ajouter la mission"}
          </button>
          {f.id && (
            <button className="text-button" type="button" onClick={() => setF(missionVide())}>
              Annuler la modification
            </button>
          )}
        </div>
        {msg && <p className="admin-error">{msg}</p>}
      </form>
      <table className="admin-table">
        <thead>
          <tr>
            <th>Mission</th>
            <th>Rubrique</th>
            <th>Déclencheur</th>
            <th>Récompense</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          {missions.rows.map((m) => (
            <tr key={m.id} className={m.actif ? "" : "admin-row-inactive"}>
              <td>
                <strong>{m.nom}</strong>
                {!m.actif && " (inactive)"}
                <br />
                <small>{m.description}</small>
              </td>
              <td>{m.rubrique === "collective" ? "Collective" : "Individuelle"}</td>
              <td>
                {EVENEMENTS_MISSION.find(([v]) => v === m.evenement)?.[1] || m.evenement}
                {m.seuil > 1 ? ` ×${m.seuil}` : ""}
                {m.declencheur_note && (
                  <>
                    <br />
                    <small>{m.declencheur_note}</small>
                  </>
                )}
              </td>
              <td>
                {recompense(m)}
                {m.recompense_cachee && " (cachée)"}
              </td>
              <td className="admin-row-actions">
                <button type="button" className="text-button" onClick={() => charger(m)}>
                  Modifier
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
