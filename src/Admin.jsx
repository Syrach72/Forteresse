import { Fragment, useEffect, useRef, useState } from "react";
import { supabase } from "./supabaseClient";
import { ASSETS } from "./data";

const ATELIERS = ["alchimie", "forge", "armurerie", "magie"];
const ATELIER_LABELS = {
  alchimie: "Recette (alchimie)",
  forge: "Forgeage d’armes",
  armurerie: "Forgeage d’armure",
  magie: "Formule (magie)",
};
// Libellé du bouton qui envoie réellement l'objet vers son atelier de jeu
// (App.jsx, prop onCraftItem) : reprend le vocabulaire déjà utilisé côté
// joueur (« Envoyer à la forge »/« … à l’armurerie ») pour rester cohérent.
const CRAFT_BUTTON_LABELS = {
  forge: "Placer dans la forge",
  armurerie: "Placer dans l’armurerie",
  alchimie: "Placer au laboratoire",
  magie: "Placer à la tour du mage",
};

function useSession() {
  const [session, setSession] = useState(undefined);
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((_event, s) =>
      setSession(s),
    );
    return () => sub.subscription.unsubscribe();
  }, []);
  return session;
}

function useTable(table, { order = "id" } = {}) {
  const [rows, setRows] = useState(null);
  const [error, setError] = useState("");
  async function reload() {
    const { data, error } = await supabase.from(table).select("*").order(order);
    if (error) setError(error.message);
    else {
      setRows(data);
      setError("");
    }
  }
  useEffect(() => {
    reload();
  }, []);
  async function insert(values) {
    const { error } = await supabase.from(table).insert(values);
    if (error) return error.message;
    await reload();
    return "";
  }
  async function update(id, values) {
    const { error } = await supabase.from(table).update(values).eq("id", id);
    if (error) return error.message;
    await reload();
    return "";
  }
  async function remove(id) {
    const { error } = await supabase.from(table).delete().eq("id", id);
    if (error) return error.message;
    await reload();
    return "";
  }
  return { rows, error, reload, insert, update, remove };
}

function LoginForm() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  // Mot de passe plutot que lien magique : le lien magique depend de
  // l'envoi d'un e-mail, plafonne par defaut a 2/heure sans fournisseur
  // SMTP externe sur Supabase, ce qui bloquait l'acces a l'admin. Le
  // compte (avec mot de passe) se cree une fois via le dashboard Supabase
  // (Authentication > Users > Add user, "Auto Confirm User" coche) : pas
  // besoin d'un flux d'inscription ici pour un admin a compte unique.
  async function submit(e) {
    e.preventDefault();
    setBusy(true);
    setError("");
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (error) setError(error.message);
  }
  return (
    <form className="parchment admin-card" onSubmit={submit} noValidate>
      <p className="eyebrow">Administration</p>
      <h1>Se connecter</h1>
      <p className="auth-intro">Saisissez votre e-mail et votre mot de passe.</p>
      <div className="field">
        <label htmlFor="admin-email">E-mail</label>
        <div className="input-wrap">
          <input
            id="admin-email"
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
        </div>
      </div>
      <div className="field">
        <label htmlFor="admin-password">Mot de passe</label>
        <div className="input-wrap">
          <input
            id="admin-password"
            type="password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </div>
      </div>
      {error && (
        <p className="admin-error" role="alert">
          {error}
        </p>
      )}
      <button className="primary" type="submit" disabled={busy}>
        {busy ? "Connexion…" : "Se connecter"}
      </button>
    </form>
  );
}

function emptyCatalogueItem(categorieId = "") {
  return {
    code_unique: "",
    nom: "",
    categorie_id: categorieId,
    description: "",
    empilable: true,
    utilisable: false,
    icone: "",
    veterance_requise: "",
    duree_fabrication_instances: "",
    cout_achat_or: "",
    portee: "",
  };
}

async function uploadImage(bucket, file, seed) {
  const ext = (file.name.split(".").pop() || "png").toLowerCase();
  const path = `${(seed || "image").replace(/[^a-z0-9-]/gi, "-")}-${Date.now()}.${ext}`;
  const { error } = await supabase.storage.from(bucket).upload(path, file, { upsert: true });
  if (error) return { error: error.message };
  const { data } = supabase.storage.from(bucket).getPublicUrl(path);
  return { url: data.publicUrl };
}

// Section générique pour une table "nom + actif" simple (categorie, classe) :
// ajouter, renommer, supprimer, avec message clair si encore référencée
// ailleurs. `hierarchical` active des sous-catégories à profondeur
// arbitraire (parent_id) : n'importe quelle catégorie peut être parente
// d'une autre, sauf d'elle-même ou de l'un de ses propres descendants
// (pour ne pas créer de cycle).
function isDescendant(rows, ancestorId, id) {
  let current = rows.find((r) => r.id === id);
  while (current?.parent_id) {
    if (current.parent_id === ancestorId) return true;
    current = rows.find((r) => r.id === current.parent_id);
  }
  return false;
}
function NamedListSection({ table, singular, blockedBy, hierarchical = false }) {
  const { rows, error, insert, update, remove } = useTable(table, {
    order: "nom",
  });
  const [editing, setEditing] = useState(null);
  const [nom, setNom] = useState("");
  const [parentId, setParentId] = useState("");
  const [msg, setMsg] = useState("");

  function startEdit(row) {
    setEditing(row.id);
    setNom(row.nom);
    setParentId(row.parent_id || "");
    setMsg("");
  }
  function cancel() {
    setEditing(null);
    setNom("");
    setParentId("");
    setMsg("");
  }
  async function submit(e) {
    e.preventDefault();
    if (!nom.trim()) {
      setMsg("Le nom est obligatoire.");
      return;
    }
    const values = { nom: nom.trim() };
    if (hierarchical) values.parent_id = parentId || null;
    const err = editing ? await update(editing, values) : await insert(values);
    if (err) setMsg(err);
    else cancel();
  }
  async function del(id) {
    if (!confirm(`Supprimer cette ${singular} ?`)) return;
    const err = await remove(id);
    if (err)
      setMsg(`Suppression impossible (${blockedBy} l’utilisent encore) : ${err}`);
  }

  if (error) return <p className="admin-error">{error}</p>;
  if (!rows) return <p>Chargement…</p>;

  const roots = hierarchical ? rows.filter((r) => !r.parent_id) : rows;
  const childrenOf = (id) => rows.filter((r) => r.parent_id === id);

  function row(r, depth) {
    return (
      <tr key={r.id} className={editing === r.id ? "editing" : ""}>
        <td
          className={depth > 0 ? "admin-table-indent" : ""}
          style={depth > 0 ? { paddingLeft: 10 + depth * 20 } : undefined}
        >
          {r.nom}
        </td>
        <td className="admin-row-actions">
          <button type="button" className="text-button" onClick={() => startEdit(r)}>
            Modifier
          </button>
          <button type="button" className="text-button" onClick={() => del(r.id)}>
            Supprimer
          </button>
        </td>
      </tr>
    );
  }
  function renderNode(r, depth) {
    return (
      <Fragment key={r.id}>
        {row(r, depth)}
        {childrenOf(r.id).map((c) => renderNode(c, depth + 1))}
      </Fragment>
    );
  }
  // Options du sélecteur "catégorie parente", dans l'ordre de
  // l'arborescence (et non l'ordre alphabétique de `rows`) : un enfant
  // doit apparaître juste après son parent, pas mélangé avec des
  // catégories sans rapport dont le nom se trouve trier pareil.
  function parentOptions() {
    const result = [];
    function walk(parentId, depth) {
      rows
        .filter((r) => (r.parent_id || null) === parentId)
        .forEach((r) => {
          if (editing && (r.id === editing || isDescendant(rows, editing, r.id))) return;
          result.push({ row: r, depth });
          walk(r.id, depth + 1);
        });
    }
    walk(null, 0);
    return result;
  }

  return (
    <div>
      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Nom</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {hierarchical ? roots.map((r) => renderNode(r, 0)) : rows.map((r) => row(r, 0))}
          </tbody>
        </table>
      </div>
      <form className="admin-form" onSubmit={submit}>
        <h3>{editing ? `Modifier la ${singular}` : `Ajouter une ${singular}`}</h3>
        <div className="field">
          <label htmlFor={`${table}-nom`}>Nom</label>
          <div className="input-wrap">
            <input
              id={`${table}-nom`}
              value={nom}
              onChange={(e) => setNom(e.target.value)}
              required
            />
          </div>
        </div>
        {hierarchical && (
          <div className="field">
            <label htmlFor={`${table}-parent`}>Catégorie parente (optionnel)</label>
            <select
              id={`${table}-parent`}
              value={parentId}
              onChange={(e) => setParentId(e.target.value)}
            >
              <option value="">Aucune (catégorie principale)</option>
              {parentOptions().map(({ row: r, depth }) => (
                <option key={r.id} value={r.id}>
                  {"— ".repeat(depth)}
                  {r.nom}
                </option>
              ))}
            </select>
          </div>
        )}
        {msg && <p className="admin-error">{msg}</p>}
        <div className="admin-form-actions">
          <button className="primary" type="submit">
            {editing ? "Enregistrer" : "Ajouter"}
          </button>
          {editing && (
            <button type="button" className="text-button" onClick={cancel}>
              Annuler
            </button>
          )}
        </div>
      </form>
    </div>
  );
}

function CatalogueSection({ onViewRecette, focusObjetId }) {
  const { rows, error, insert, update, remove } = useTable("objet_catalogue", {
    order: "nom",
  });
  const categories = useTable("categorie", { order: "nom" });
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(emptyCatalogueItem());
  const [iconFile, setIconFile] = useState(null);
  const [uploading, setUploading] = useState(false);
  const [msg, setMsg] = useState("");
  const [filterCategorie, setFilterCategorie] = useState("");
  // Rouvre automatiquement la fiche d'un objet quand on revient depuis sa
  // recette (bouton « Retour ») : appliqué une seule fois par demande, pour
  // ne pas écraser une saisie en cours si les lignes se rechargent ensuite.
  const focusAppliedRef = useRef(null);

  function nomCategorie(id) {
    return categories.rows?.find((c) => c.id === id)?.nom || "?";
  }
  // Options de catégorie dans l'ordre de l'arborescence (cf. NamedListSection),
  // réutilisées à la fois pour le formulaire et pour le filtre d'affichage.
  function categoryTreeOptions(parentId, depth) {
    return categories.rows
      .filter((c) => (c.parent_id || null) === parentId)
      .flatMap((c) => [
        <option key={c.id} value={c.id}>
          {"— ".repeat(depth)}
          {c.nom}
        </option>,
        ...categoryTreeOptions(c.id, depth + 1),
      ]);
  }
  // Un objet correspond au filtre s'il est dans la catégorie choisie ou
  // dans l'une de ses sous-catégories (récursivement).
  function categoryAndDescendantIds(id) {
    const ids = new Set([id]);
    let added = true;
    while (added) {
      added = false;
      categories.rows.forEach((c) => {
        if (c.parent_id && ids.has(c.parent_id) && !ids.has(c.id)) {
          ids.add(c.id);
          added = true;
        }
      });
    }
    return ids;
  }
  // Un objet est « dans la rubrique Armes » si lui-meme ou l'un de ses
  // ancetres porte un nom commencant par "Arme" (Armes, Armes courantes,
  // Arme a une main, ...) — couvre toute la sous-arborescence sans
  // dependre d'un id fige ni de l'orthographe exacte (singulier/pluriel).
  function isCategorieArme(categorieId) {
    let current = categories.rows?.find((c) => c.id === categorieId);
    while (current) {
      if (current.nom.trim().toLowerCase().startsWith("arme")) return true;
      current = categories.rows.find((c) => c.id === current.parent_id);
    }
    return false;
  }
  // Meme principe que isCategorieArme, mais par correspondance exacte de
  // nom (pas de prefixe) : sert a reconnaitre Produits Alchimiques / Gemmes
  // / Armures, qui doivent avoir un cout d'achat et un temps de fabrication
  // comme les Armes, sans pour autant avoir vetérance/portee (des stats de
  // combat qui n'ont pas de sens pour une potion ou une gemme).
  function isCategorieParmi(categorieId, nomsRacines) {
    let current = categories.rows?.find((c) => c.id === categorieId);
    while (current) {
      if (nomsRacines.includes(current.nom.trim().toLowerCase())) return true;
      current = categories.rows.find((c) => c.id === current.parent_id);
    }
    return false;
  }
  function startEdit(row) {
    setEditing(row.id);
    setForm({
      ...row,
      description: row.description || "",
      icone: row.icone || "",
      veterance_requise: row.veterance_requise ?? "",
      duree_fabrication_instances: row.duree_fabrication_instances ?? "",
      cout_achat_or: row.cout_achat_or ?? "",
      portee: row.portee || "",
    });
    setIconFile(null);
    setMsg("");
  }
  useEffect(() => {
    if (!focusObjetId || !rows || focusAppliedRef.current === focusObjetId) return;
    const row = rows.find((r) => r.id === focusObjetId);
    if (row) {
      startEdit(row);
      focusAppliedRef.current = focusObjetId;
    }
  }, [focusObjetId, rows]);
  function cancel() {
    setEditing(null);
    setForm(emptyCatalogueItem(categories.rows?.[0]?.id || ""));
    setIconFile(null);
    setMsg("");
  }
  async function submit(e) {
    e.preventDefault();
    if (!form.code_unique.trim() || !form.nom.trim() || !form.categorie_id) {
      setMsg("Le code, le nom et la catégorie sont obligatoires.");
      return;
    }
    let icone = form.icone || null;
    if (iconFile) {
      setUploading(true);
      const result = await uploadImage("catalogue-icones", iconFile, form.code_unique);
      setUploading(false);
      if (result.error) {
        setMsg(result.error);
        return;
      }
      icone = result.url;
    }
    const arme = isCategorieArme(form.categorie_id);
    const craftable =
      arme ||
      isCategorieParmi(form.categorie_id, [
        "produits alchimiques",
        "gemmes",
        "armures",
      ]);
    const values = {
      ...form,
      description: form.description || null,
      icone,
      // Vetérance et portee : uniquement les Armes (stats de combat sans
      // sens pour une potion ou une gemme). Cout d'achat et temps de
      // fabrication : Armes + Produits Alchimiques/Gemmes/Armures. Effaces
      // si l'objet ne fait plus partie de la rubrique concernee, pour ne
      // pas laisser trainer une valeur sur un ingredient ou un materiau.
      veterance_requise: arme ? toIntOrNull(form.veterance_requise) : null,
      duree_fabrication_instances: craftable
        ? toIntOrNull(form.duree_fabrication_instances)
        : null,
      cout_achat_or: craftable ? toIntOrNull(form.cout_achat_or) : null,
      portee: arme ? form.portee || null : null,
    };
    const err = editing ? await update(editing, values) : await insert(values);
    if (err) setMsg(err);
    else cancel();
  }
  async function del(id) {
    if (!confirm("Supprimer cet objet du catalogue ?")) return;
    const err = await remove(id);
    if (err)
      setMsg(
        "Suppression impossible (probablement utilisé par une recette ou un inventaire) : " +
          err,
      );
  }

  if (error || categories.error)
    return <p className="admin-error">{error || categories.error}</p>;
  if (!rows || !categories.rows) return <p>Chargement…</p>;
  if (!editing && !form.categorie_id && categories.rows[0]) {
    setForm({ ...form, categorie_id: categories.rows[0].id });
  }

  const formEl = (
    <form className="admin-form" onSubmit={submit}>
      <h3>{editing ? "Modifier l’objet" : "Ajouter un objet"}</h3>
      <div className="admin-form-grid">
        <div className="field">
          <label htmlFor="cat-code">Code unique</label>
          <div className="input-wrap">
            <input
              id="cat-code"
              value={form.code_unique}
              onChange={(e) => setForm({ ...form, code_unique: e.target.value })}
              required
            />
          </div>
        </div>
        <div className="field">
          <label htmlFor="cat-nom">Nom</label>
          <div className="input-wrap">
            <input
              id="cat-nom"
              value={form.nom}
              onChange={(e) => setForm({ ...form, nom: e.target.value })}
              required
            />
          </div>
        </div>
        <div className="field">
          <label htmlFor="cat-categorie">Catégorie</label>
          <select
            id="cat-categorie"
            value={form.categorie_id}
            onChange={(e) => setForm({ ...form, categorie_id: e.target.value })}
          >
            {categoryTreeOptions(null, 0)}
          </select>
        </div>
      </div>
      <div className="admin-checkbox-row">
        <label className="admin-checkbox">
          <input
            type="checkbox"
            checked={form.empilable}
            onChange={(e) => setForm({ ...form, empilable: e.target.checked })}
          />
          Empilable
        </label>
        <label className="admin-checkbox">
          <input
            type="checkbox"
            checked={form.utilisable}
            onChange={(e) => setForm({ ...form, utilisable: e.target.checked })}
          />
          Utilisable
        </label>
      </div>
      {(() => {
        const arme = isCategorieArme(form.categorie_id);
        const craftable =
          arme ||
          isCategorieParmi(form.categorie_id, [
            "produits alchimiques",
            "gemmes",
            "armures",
          ]);
        if (!craftable) return null;
        return (
          <>
          <p className="eyebrow admin-section-label">Fabrication</p>
          <div className="admin-form-grid">
            {arme && (
              <div className="field">
                <label htmlFor="cat-veterance">Vétérance requise</label>
                <div className="input-wrap">
                  <input
                    id="cat-veterance"
                    type="number"
                    min="1"
                    max="20"
                    value={form.veterance_requise}
                    onChange={(e) =>
                      setForm({ ...form, veterance_requise: e.target.value })
                    }
                  />
                </div>
              </div>
            )}
            <div className="field field-narrow">
              <label htmlFor="cat-duree-fab">Temps de fabrication (instances)</label>
              <div className="input-wrap">
                <input
                  id="cat-duree-fab"
                  type="number"
                  min="1"
                  max="5"
                  value={form.duree_fabrication_instances}
                  onChange={(e) =>
                    setForm({ ...form, duree_fabrication_instances: e.target.value })
                  }
                />
              </div>
            </div>
            <div className="field field-narrow">
              <label htmlFor="cat-cout-or">
                Coût d’achat (pièces d’or)
                <span className="field-hint">Prix au marché</span>
              </label>
              <div className="input-wrap">
                <input
                  id="cat-cout-or"
                  type="number"
                  min="0"
                  value={form.cout_achat_or}
                  onChange={(e) => setForm({ ...form, cout_achat_or: e.target.value })}
                />
              </div>
            </div>
            {arme && (
              <div className="field">
                <label htmlFor="cat-portee">Portée</label>
                <div className="input-wrap">
                  <input
                    id="cat-portee"
                    placeholder="ex. 30/90c, ou vide pour une arme de corps à corps"
                    value={form.portee}
                    onChange={(e) => setForm({ ...form, portee: e.target.value })}
                  />
                </div>
              </div>
            )}
          </div>
          </>
        );
      })()}
      <div className="field">
        <label htmlFor="cat-desc">Description</label>
        <div className="input-wrap">
          <textarea
            id="cat-desc"
            rows={2}
            value={form.description}
            onChange={(e) => setForm({ ...form, description: e.target.value })}
            ref={(el) => {
              // Hauteur ajustee au contenu a chaque rendu (saisie ou
              // ouverture d'une fiche existante avec une longue description).
              if (el) {
                el.style.height = "auto";
                el.style.height = `${el.scrollHeight}px`;
              }
            }}
          />
        </div>
      </div>
      <div className="field">
        <label htmlFor="cat-icone">Icône (image)</label>
        <div className="admin-icon-picker">
          {(iconFile || form.icone) && (
            <img
              className="admin-icon"
              src={iconFile ? URL.createObjectURL(iconFile) : form.icone}
              alt=""
            />
          )}
          <input
            id="cat-icone"
            type="file"
            accept="image/*"
            onChange={(e) => setIconFile(e.target.files[0] || null)}
          />
          {(iconFile || form.icone) && (
            <button
              type="button"
              className="text-button"
              onClick={() => {
                setIconFile(null);
                setForm({ ...form, icone: "" });
              }}
            >
              Retirer l’icône
            </button>
          )}
        </div>
      </div>
      {msg && <p className="admin-error">{msg}</p>}
      <div className="admin-form-actions">
        <button className="primary" type="submit" disabled={uploading}>
          {uploading ? "Envoi de l’image…" : editing ? "Enregistrer" : "Ajouter"}
        </button>
        {editing && (
          <button type="button" className="text-button" onClick={cancel}>
            Annuler
          </button>
        )}
        {editing && (
          <button
            type="button"
            className="text-button"
            onClick={() => onViewRecette(editing)}
          >
            Voir la recette ›
          </button>
        )}
      </div>
    </form>
  );

  const visibleRows = filterCategorie
    ? rows.filter((r) => categoryAndDescendantIds(filterCategorie).has(r.categorie_id))
    : rows;

  return (
    <div>
      <div className="admin-catalogue-filter field">
        <label htmlFor="cat-filter">Afficher</label>
        <select
          id="cat-filter"
          value={filterCategorie}
          onChange={(e) => setFilterCategorie(e.target.value)}
        >
          <option value="">Toutes les catégories ({rows.length} objets)</option>
          {categoryTreeOptions(null, 0)}
        </select>
      </div>
      {filterCategorie && !visibleRows.length && (
        <p className="muted">Aucun objet dans cette catégorie.</p>
      )}
      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Icône</th>
              <th>Nom</th>
              <th>Code</th>
              <th>Catégorie</th>
              <th>Empilable</th>
              <th>Utilisable</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {visibleRows.map((r) => (
              <Fragment key={r.id}>
                <tr className={editing === r.id ? "editing" : ""}>
                  <td>
                    {r.icone ? (
                      <img className="admin-icon" src={r.icone} alt="" />
                    ) : (
                      "—"
                    )}
                  </td>
                  <td>{r.nom}</td>
                  <td>{r.code_unique}</td>
                  <td>{nomCategorie(r.categorie_id)}</td>
                  <td>{r.empilable ? "Oui" : "Non"}</td>
                  <td>{r.utilisable ? "Oui" : "Non"}</td>
                  <td className="admin-row-actions">
                    <button type="button" className="text-button" onClick={() => startEdit(r)}>
                      Modifier
                    </button>
                    <button type="button" className="text-button" onClick={() => del(r.id)}>
                      Supprimer
                    </button>
                  </td>
                </tr>
                {editing === r.id && (
                  <tr className="admin-edit-row">
                    <td colSpan={7}>{formEl}</td>
                  </tr>
                )}
              </Fragment>
            ))}
          </tbody>
        </table>
      </div>
      {!editing && formEl}
    </div>
  );
}

function emptyRecette() {
  return { code_unique: "", nom: "", atelier: ATELIERS[0], resultat_objet_id: "", quantite_produite: 1 };
}

// Icône (image) du produit fini d'une recette. L'image appartient à
// l'objet du catalogue résultat (objet_catalogue.icone) — pas un second
// champ sur la recette elle-même, pour ne pas dupliquer la même image à
// deux endroits qui pourraient diverger (cf. section 8 CLAUDE.md).
function ObjectIconPicker({ objet, onUpload }) {
  const [cropSource, setCropSource] = useState(null);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState("");

  return (
    <div className="icon-picker">
      <label className="icon-frame" htmlFor={`obj-icon-${objet.id}`} title="Image du produit fini">
        {objet.icone ? (
          <img src={objet.icone} alt="" />
        ) : (
          <span className="icon-placeholder-mark" aria-hidden="true">
            +
          </span>
        )}
        <span className="portrait-frame-hint" aria-hidden="true">
          {objet.icone ? "Changer" : "Ajouter"}
        </span>
      </label>
      <input
        id={`obj-icon-${objet.id}`}
        type="file"
        accept="image/*"
        className="sr-only-file"
        onChange={(e) => {
          const f = e.target.files[0];
          if (f) setCropSource(f);
          e.target.value = "";
        }}
      />
      {uploading && <span className="icon-uploading">Envoi…</span>}
      {error && <p className="admin-error">{error}</p>}
      {cropSource && (
        <PortraitCropper
          file={cropSource}
          viewW={200}
          viewH={200}
          outputW={400}
          outputH={400}
          title="Recadrer l’image du produit"
          onCancel={() => setCropSource(null)}
          onConfirm={async (blob) => {
            setCropSource(null);
            setUploading(true);
            const file = new File([blob], "produit.jpg", { type: "image/jpeg" });
            const result = await uploadImage("catalogue-icones", file, objet.code_unique || objet.nom);
            if (result.error) {
              setUploading(false);
              setError(result.error);
              return;
            }
            const err = await onUpload(result.url);
            setUploading(false);
            if (err) setError(err);
          }}
        />
      )}
    </div>
  );
}

function RecettesSection({ onCraftItem, onBack, focusObjetId }) {
  const catalogue = useTable("objet_catalogue", { order: "nom" });
  const recettes = useTable("recette", { order: "nom" });
  const ingredients = useTable("ingredient_recette", { order: "id" });
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(emptyRecette());
  const [msg, setMsg] = useState("");
  const [ingredientForm, setIngredientForm] = useState({});
  const [ingredientQty, setIngredientQty] = useState({});
  // Fait défiler jusqu'à la recette de l'objet dont on vient (bouton
  // « Voir la recette » côté catalogue), une seule fois par demande.
  const recetteRefs = useRef({});
  const scrollAppliedRef = useRef(null);
  useEffect(() => {
    if (!focusObjetId || !recettes.rows || scrollAppliedRef.current === focusObjetId) return;
    const r = recettes.rows.find((r) => r.resultat_objet_id === focusObjetId);
    if (r) {
      recetteRefs.current[r.id]?.scrollIntoView({ behavior: "smooth", block: "center" });
      scrollAppliedRef.current = focusObjetId;
    }
  }, [focusObjetId, recettes.rows]);

  function nomObjet(id) {
    return catalogue.rows?.find((o) => o.id === id)?.nom || "?";
  }
  function startEdit(r) {
    setEditing(r.id);
    setForm({
      code_unique: r.code_unique,
      nom: r.nom,
      atelier: r.atelier,
      resultat_objet_id: r.resultat_objet_id,
      quantite_produite: r.quantite_produite,
    });
    setMsg("");
  }
  function cancelEdit() {
    setEditing(null);
    setForm(emptyRecette());
    setMsg("");
  }
  async function submit(e) {
    e.preventDefault();
    if (!form.code_unique.trim() || !form.nom.trim() || !form.resultat_objet_id) {
      setMsg("Le code, le nom et l’objet résultat sont obligatoires.");
      return;
    }
    const values = { ...form, quantite_produite: Number(form.quantite_produite) || 1 };
    const err = editing ? await recettes.update(editing, values) : await recettes.insert(values);
    if (err) setMsg(err);
    else cancelEdit();
  }
  async function delRecette(id) {
    if (!confirm("Supprimer cette recette (et ses ingrédients) ?")) return;
    const err = await recettes.remove(id);
    if (err) setMsg(err);
    else ingredients.reload();
  }
  async function addIngredient(recetteId) {
    const f = ingredientForm[recetteId];
    if (!f?.objet_id || !f?.quantite) return;
    const err = await ingredients.insert({
      recette_id: recetteId,
      objet_id: f.objet_id,
      quantite_requise: Number(f.quantite),
    });
    if (err) setMsg(err);
    else setIngredientForm({ ...ingredientForm, [recetteId]: { objet_id: "", quantite: "" } });
  }
  async function delIngredient(id) {
    const err = await ingredients.remove(id);
    if (err) setMsg(err);
  }
  async function saveIngredientQty(i) {
    const raw = ingredientQty[i.id];
    const n = Number(raw);
    if (raw === undefined || raw === "" || !Number.isInteger(n) || n < 1 || n === i.quantite_requise) {
      setIngredientQty((prev) => {
        const next = { ...prev };
        delete next[i.id];
        return next;
      });
      return;
    }
    const err = await ingredients.update(i.id, { quantite_requise: n });
    if (err) setMsg(err);
    setIngredientQty((prev) => {
      const next = { ...prev };
      delete next[i.id];
      return next;
    });
  }

  if (catalogue.error || recettes.error || ingredients.error)
    return <p className="admin-error">{catalogue.error || recettes.error || ingredients.error}</p>;
  if (!catalogue.rows || !recettes.rows || !ingredients.rows) return <p>Chargement…</p>;

  const formEl = (
    <form className="admin-form" onSubmit={submit}>
      <h3>{editing ? "Modifier la recette" : "Ajouter une recette"}</h3>
      <div className="admin-form-grid">
        <div className="field">
          <label htmlFor="rec-code">Code unique</label>
          <div className="input-wrap">
            <input
              id="rec-code"
              value={form.code_unique}
              onChange={(e) => setForm({ ...form, code_unique: e.target.value })}
            />
          </div>
        </div>
        <div className="field">
          <label htmlFor="rec-nom">Nom</label>
          <div className="input-wrap">
            <input
              id="rec-nom"
              value={form.nom}
              onChange={(e) => setForm({ ...form, nom: e.target.value })}
            />
          </div>
        </div>
        <div className="field">
          <label htmlFor="rec-atelier">Atelier</label>
          <select
            id="rec-atelier"
            value={form.atelier}
            onChange={(e) => setForm({ ...form, atelier: e.target.value })}
          >
            {ATELIERS.map((a) => (
              <option key={a} value={a}>
                {ATELIER_LABELS[a] || a}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label htmlFor="rec-resultat">Objet produit</label>
          <select
            id="rec-resultat"
            value={form.resultat_objet_id}
            onChange={(e) => setForm({ ...form, resultat_objet_id: e.target.value })}
          >
            <option value="">Choisir…</option>
            {catalogue.rows.map((o) => (
              <option key={o.id} value={o.id}>
                {o.nom}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label htmlFor="rec-qte">Quantité produite</label>
          <div className="input-wrap">
            <input
              id="rec-qte"
              type="number"
              min="1"
              value={form.quantite_produite}
              onChange={(e) => setForm({ ...form, quantite_produite: e.target.value })}
            />
          </div>
        </div>
      </div>
      {msg && <p className="admin-error">{msg}</p>}
      <div className="admin-form-actions">
        <button className="primary" type="submit">
          {editing ? "Enregistrer" : "Ajouter la recette"}
        </button>
        {editing && (
          <button type="button" className="text-button" onClick={cancelEdit}>
            Annuler
          </button>
        )}
      </div>
    </form>
  );

  return (
    <div>
      {recettes.rows.map((r) => {
        const resultObjet = catalogue.rows.find((o) => o.id === r.resultat_objet_id);
        return (
        <div
          className="admin-recette"
          key={r.id}
          ref={(el) => {
            recetteRefs.current[r.id] = el;
          }}
        >
          <div className="admin-recette-header">
            {resultObjet && (
              <ObjectIconPicker
                objet={resultObjet}
                onUpload={(url) => catalogue.update(resultObjet.id, { icone: url })}
              />
            )}
            <strong>{r.nom}</strong>
            <span className="admin-tag">{ATELIER_LABELS[r.atelier] || r.atelier}</span>
            <span>→ {nomObjet(r.resultat_objet_id)} ×{r.quantite_produite}</span>
            <button type="button" className="text-button" onClick={() => startEdit(r)}>
              Modifier
            </button>
            <button type="button" className="text-button" onClick={() => delRecette(r.id)}>
              Supprimer
            </button>
            <button
              type="button"
              className="text-button"
              onClick={() => onCraftItem(r.resultat_objet_id, r.atelier)}
            >
              {CRAFT_BUTTON_LABELS[r.atelier] || "Placer en fabrication"}
            </button>
            <button type="button" className="text-button" onClick={() => onBack(r.resultat_objet_id)}>
              ‹ Retour
            </button>
          </div>
          {editing === r.id && formEl}
          <ul className="admin-ingredient-list">
            {ingredients.rows
              .filter((i) => i.recette_id === r.id)
              .map((i) => (
                <li key={i.id}>
                  {nomObjet(i.objet_id)} ×
                  <input
                    type="number"
                    min="1"
                    className="ingredient-qty-input"
                    value={ingredientQty[i.id] ?? i.quantite_requise}
                    onChange={(e) =>
                      setIngredientQty({ ...ingredientQty, [i.id]: e.target.value })
                    }
                    onBlur={() => saveIngredientQty(i)}
                    aria-label={`Quantité de ${nomObjet(i.objet_id)}`}
                  />
                  <button type="button" className="text-button" onClick={() => delIngredient(i.id)}>
                    ✕
                  </button>
                </li>
              ))}
          </ul>
          <div className="admin-ingredient-form">
            <select
              value={ingredientForm[r.id]?.objet_id || ""}
              onChange={(e) =>
                setIngredientForm({
                  ...ingredientForm,
                  [r.id]: { ...ingredientForm[r.id], objet_id: e.target.value },
                })
              }
            >
              <option value="">Ingrédient…</option>
              {catalogue.rows.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.nom}
                </option>
              ))}
            </select>
            <input
              type="number"
              min="1"
              placeholder="Qté"
              value={ingredientForm[r.id]?.quantite || ""}
              onChange={(e) =>
                setIngredientForm({
                  ...ingredientForm,
                  [r.id]: { ...ingredientForm[r.id], quantite: e.target.value },
                })
              }
            />
            <button type="button" className="text-button" onClick={() => addIngredient(r.id)}>
              Ajouter l’ingrédient
            </button>
          </div>
        </div>
        );
      })}
      {!editing && formEl}
    </div>
  );
}

function emptyMercenaire(classeId = "") {
  return {
    nom: "",
    classe_id: classeId,
    portrait: "",
    veterance: "",
    attaque: "",
    defense: "",
    esprit: "",
    mouvement: "",
    mana: "",
    sante: "",
    notes: "",
  };
}

function toIntOrNull(v) {
  return v === "" || v === null || v === undefined ? null : Number(v);
}

// Recadrage d'une image : la photo choisie n'a pas forcément le format
// attendu ni le bon cadrage ; on laisse déplacer/zoomer avant de
// valider, plutôt que de subir un recadrage automatique (object-fit).
// Portrait de mercenaire (3:4) et icône de produit fini (1:1) partagent
// le même outil, avec un format de vue/sortie différent.
function cropBaseScale(viewW, viewH, w, h) {
  return Math.max(viewW / w, viewH / h);
}
function clampCropOffset(viewW, viewH, offset, natural, zoom) {
  const scale = cropBaseScale(viewW, viewH, natural.w, natural.h) * zoom;
  const dispW = natural.w * scale;
  const dispH = natural.h * scale;
  const minX = viewW - dispW;
  const minY = viewH - dispH;
  return {
    x: Math.min(0, Math.max(minX, offset.x)),
    y: Math.min(0, Math.max(minY, offset.y)),
  };
}

function PortraitCropper({
  file,
  viewW = 240,
  viewH = 320,
  outputW = 480,
  outputH = 640,
  title = "Recadrer le portrait",
  onCancel,
  onConfirm,
}) {
  const [src, setSrc] = useState(null);
  const [natural, setNatural] = useState(null);
  const [loadError, setLoadError] = useState(false);
  const [zoom, setZoom] = useState(1);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const dragRef = useRef(null);
  const dialogRef = useRef(null);
  const imgRef = useRef(null);

  useEffect(() => {
    dialogRef.current?.showModal();
  }, []);

  // L'URL de l'image est créée et révoquée dans le même effet (plutôt
  // qu'au niveau du state) : avec StrictMode, React exécute chaque effet
  // une fois « pour de faux » (montage-nettoyage) avant de le rejouer
  // pour de bon. Une URL créée dans un état initial puis révoquée par un
  // nettoyage d'effet se retrouve donc révoquée avant sa véritable
  // utilisation — c'était la cause du cadre resté vide, rien à voir avec
  // le format de l'image.
  useEffect(() => {
    const url = URL.createObjectURL(file);
    setSrc(url);
    return () => URL.revokeObjectURL(url);
  }, [file]);

  // Sonde de chargement indépendante du DOM : un <img> place dans une
  // <dialog> pas encore ouverte (donc masquee) ne declenche pas toujours
  // son evenement onload selon le navigateur. Un objet Image() classique
  // charge quel que soit l'etat d'affichage, et permet aussi de detecter
  // un format vraiment illisible (ex. photo iPhone en HEIC) au lieu d'un
  // cadre vide silencieux.
  useEffect(() => {
    if (!src) return;
    let cancelled = false;
    const probe = new Image();
    probe.onload = () => {
      if (cancelled) return;
      const w = probe.naturalWidth;
      const h = probe.naturalHeight;
      const scale = cropBaseScale(viewW, viewH, w, h);
      setNatural({ w, h });
      setOffset({ x: (viewW - w * scale) / 2, y: (viewH - h * scale) / 2 });
    };
    probe.onerror = () => {
      if (!cancelled) setLoadError(true);
    };
    probe.src = src;
    return () => {
      cancelled = true;
    };
  }, [src]);

  function onPointerDown(e) {
    e.currentTarget.setPointerCapture(e.pointerId);
    dragRef.current = { startX: e.clientX, startY: e.clientY, offX: offset.x, offY: offset.y };
  }
  function onPointerMove(e) {
    if (!dragRef.current || !natural) return;
    const dx = e.clientX - dragRef.current.startX;
    const dy = e.clientY - dragRef.current.startY;
    setOffset(
      clampCropOffset(
        viewW,
        viewH,
        { x: dragRef.current.offX + dx, y: dragRef.current.offY + dy },
        natural,
        zoom,
      ),
    );
  }
  function stopDrag() {
    dragRef.current = null;
  }
  function changeZoom(z) {
    setZoom(z);
    if (natural) setOffset((prev) => clampCropOffset(viewW, viewH, prev, natural, z));
  }
  function confirm() {
    if (!natural) return;
    const canvas = document.createElement("canvas");
    canvas.width = outputW;
    canvas.height = outputH;
    const factor = outputW / viewW;
    const scale = cropBaseScale(viewW, viewH, natural.w, natural.h) * zoom * factor;
    canvas
      .getContext("2d")
      .drawImage(imgRef.current, offset.x * factor, offset.y * factor, natural.w * scale, natural.h * scale);
    canvas.toBlob((blob) => blob && onConfirm(blob), "image/jpeg", 0.9);
  }

  return (
    <dialog
      ref={dialogRef}
      className="parchment modal crop-modal"
      onCancel={(e) => {
        e.preventDefault();
        onCancel();
      }}
    >
      <div className="modal-heading">
        <h2>{title}</h2>
        <button type="button" className="text-button" onClick={onCancel}>
          Fermer
        </button>
      </div>
      <div
        className="crop-viewport"
        style={{ width: viewW, height: viewH }}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={stopDrag}
        onPointerLeave={stopDrag}
      >
        {natural ? (
          <img
            ref={imgRef}
            src={src}
            alt=""
            draggable="false"
            style={{
              width: natural.w * cropBaseScale(viewW, viewH, natural.w, natural.h) * zoom,
              height: natural.h * cropBaseScale(viewW, viewH, natural.w, natural.h) * zoom,
              transform: `translate(${offset.x}px, ${offset.y}px)`,
            }}
          />
        ) : loadError ? (
          <p className="crop-status crop-status-error">
            Impossible d’afficher cette image.
            <br />
            Essayez un format JPG ou PNG.
          </p>
        ) : (
          <p className="crop-status">Chargement…</p>
        )}
      </div>
      <div className="crop-zoom-row">
        <label htmlFor="crop-zoom">Zoom</label>
        <input
          id="crop-zoom"
          type="range"
          min="1"
          max="3"
          step="0.01"
          value={zoom}
          onChange={(e) => changeZoom(Number(e.target.value))}
        />
      </div>
      <p className="crop-hint">Glissez l’image pour la repositionner.</p>
      <div className="admin-form-actions">
        <button type="button" className="primary" onClick={confirm} disabled={!natural}>
          Valider le recadrage
        </button>
        <button type="button" className="text-button" onClick={onCancel}>
          Annuler
        </button>
      </div>
    </dialog>
  );
}

function MercenairesSection() {
  const mercenaires = useTable("mercenaire", { order: "nom" });
  const classes = useTable("classe", { order: "nom" });
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(emptyMercenaire());
  const [portraitFile, setPortraitFile] = useState(null);
  const [cropSource, setCropSource] = useState(null);
  const [uploading, setUploading] = useState(false);
  const [msg, setMsg] = useState("");

  async function recropCurrent() {
    if (portraitFile) {
      setCropSource(portraitFile);
      return;
    }
    if (form.portrait) {
      const res = await fetch(form.portrait);
      const blob = await res.blob();
      setCropSource(new File([blob], "portrait.jpg", { type: blob.type || "image/jpeg" }));
    }
  }

  function nomClasse(id) {
    return classes.rows?.find((c) => c.id === id)?.nom || "—";
  }
  function startEdit(m) {
    setEditing(m.id);
    setForm({
      nom: m.nom,
      classe_id: m.classe_id || "",
      portrait: m.portrait || "",
      veterance: m.veterance ?? "",
      attaque: m.attaque ?? "",
      defense: m.defense ?? "",
      esprit: m.esprit ?? "",
      mouvement: m.mouvement ?? "",
      mana: m.mana ?? "",
      sante: m.sante ?? "",
      notes: m.notes || "",
    });
    setPortraitFile(null);
  }
  function cancel() {
    setEditing(null);
    setForm(emptyMercenaire(classes.rows?.[0]?.id || ""));
    setPortraitFile(null);
    setMsg("");
  }
  async function submit(e) {
    e.preventDefault();
    if (!form.nom.trim()) {
      setMsg("Le nom est obligatoire.");
      return;
    }
    let portrait = form.portrait || null;
    if (portraitFile) {
      setUploading(true);
      const result = await uploadImage("mercenaire-portraits", portraitFile, form.nom);
      setUploading(false);
      if (result.error) {
        setMsg(result.error);
        return;
      }
      portrait = result.url;
    }
    const values = {
      nom: form.nom,
      classe_id: form.classe_id || null,
      portrait,
      veterance: toIntOrNull(form.veterance),
      attaque: toIntOrNull(form.attaque),
      defense: toIntOrNull(form.defense),
      esprit: toIntOrNull(form.esprit),
      mouvement: toIntOrNull(form.mouvement),
      mana: toIntOrNull(form.mana),
      sante: toIntOrNull(form.sante),
      notes: form.notes || null,
    };
    const err = editing
      ? await mercenaires.update(editing, values)
      : await mercenaires.insert(values);
    if (err) setMsg(err);
    else cancel();
  }
  async function del(id) {
    if (!confirm("Supprimer ce mercenaire ?")) return;
    const err = await mercenaires.remove(id);
    if (err) setMsg(err);
  }

  if (mercenaires.error || classes.error)
    return <p className="admin-error">{mercenaires.error || classes.error}</p>;
  if (!mercenaires.rows || !classes.rows) return <p>Chargement…</p>;
  if (!editing && !form.classe_id && classes.rows[0]) {
    setForm({ ...form, classe_id: classes.rows[0].id });
  }

  const formEl = (
      <form className="admin-form" onSubmit={submit}>
        <h3>{editing ? "Modifier le mercenaire" : "Ajouter un mercenaire"}</h3>
        <div className="admin-form-grid">
          <div className="field">
            <label htmlFor="merc-nom">Nom</label>
            <div className="input-wrap">
              <input
                id="merc-nom"
                value={form.nom}
                onChange={(e) => setForm({ ...form, nom: e.target.value })}
                required
              />
            </div>
          </div>
          <div className="field">
            <label htmlFor="merc-classe">Classe</label>
            <select
              id="merc-classe"
              value={form.classe_id}
              onChange={(e) => setForm({ ...form, classe_id: e.target.value })}
            >
              {classes.rows.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.nom}
                </option>
              ))}
            </select>
          </div>
          <div className="field portrait-field">
            <label htmlFor="merc-portrait" className="portrait-frame">
              {portraitFile || form.portrait ? (
                <img
                  src={portraitFile ? URL.createObjectURL(portraitFile) : form.portrait}
                  alt=""
                />
              ) : (
                <span className="portrait-placeholder">
                  <span className="portrait-placeholder-mark" aria-hidden="true">
                    +
                  </span>
                  Portrait
                </span>
              )}
              <span className="portrait-frame-hint" aria-hidden="true">
                {portraitFile || form.portrait ? "Changer" : "Choisir une image"}
              </span>
            </label>
            <input
              id="merc-portrait"
              type="file"
              accept="image/*"
              className="sr-only-file"
              onChange={(e) => {
                const f = e.target.files[0];
                if (f) setCropSource(f);
                e.target.value = "";
              }}
            />
            {(portraitFile || form.portrait) && (
              <div className="portrait-actions">
                <button type="button" className="text-button" onClick={recropCurrent}>
                  Recadrer
                </button>
                <button
                  type="button"
                  className="text-button portrait-remove"
                  onClick={() => {
                    setPortraitFile(null);
                    setForm({ ...form, portrait: "" });
                  }}
                >
                  Retirer le portrait
                </button>
              </div>
            )}
            {cropSource && (
              <PortraitCropper
                file={cropSource}
                onCancel={() => setCropSource(null)}
                onConfirm={(blob) => {
                  setPortraitFile(new File([blob], "portrait.jpg", { type: "image/jpeg" }));
                  setCropSource(null);
                }}
              />
            )}
          </div>
          {["veterance", "attaque", "defense", "esprit", "mouvement", "mana", "sante"].map((field) => (
            <div className="field" key={field}>
              <label htmlFor={`merc-${field}`}>{field[0].toUpperCase() + field.slice(1)}</label>
              <div className="input-wrap">
                <input
                  id={`merc-${field}`}
                  type="number"
                  value={form[field]}
                  onChange={(e) => setForm({ ...form, [field]: e.target.value })}
                />
              </div>
            </div>
          ))}
        </div>
        <div className="field">
          <label htmlFor="merc-notes">Notes</label>
          <div className="input-wrap">
            <input
              id="merc-notes"
              value={form.notes}
              onChange={(e) => setForm({ ...form, notes: e.target.value })}
            />
          </div>
        </div>
        {msg && <p className="admin-error">{msg}</p>}
        <div className="admin-form-actions">
          <button className="primary" type="submit" disabled={uploading}>
            {uploading ? "Envoi de l’image…" : editing ? "Enregistrer" : "Ajouter"}
          </button>
          {editing && (
            <button type="button" className="text-button" onClick={cancel}>
              Annuler
            </button>
          )}
        </div>
      </form>
  );

  return (
    <div>
      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Portrait</th>
              <th>Nom</th>
              <th>Classe</th>
              <th>Vétérance</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {mercenaires.rows.map((m) => (
              <Fragment key={m.id}>
                <tr className={editing === m.id ? "editing" : ""}>
                  <td>
                    {m.portrait ? (
                      <img className="admin-icon" src={m.portrait} alt="" />
                    ) : (
                      "—"
                    )}
                  </td>
                  <td>{m.nom}</td>
                  <td>{nomClasse(m.classe_id)}</td>
                  <td>{m.veterance ?? "—"}</td>
                  <td className="admin-row-actions">
                    <button type="button" className="text-button" onClick={() => startEdit(m)}>
                      Modifier
                    </button>
                    <button type="button" className="text-button" onClick={() => del(m.id)}>
                      Supprimer
                    </button>
                  </td>
                </tr>
                {editing === m.id && (
                  <tr className="admin-edit-row">
                    <td colSpan={5}>{formEl}</td>
                  </tr>
                )}
              </Fragment>
            ))}
          </tbody>
        </table>
      </div>
      {!editing && formEl}
    </div>
  );
}

function ArsenalSection() {
  const inventaires = useTable("inventaire", { order: "id" });
  const lignes = useTable("ligne_inventaire", { order: "id" });
  const catalogue = useTable("objet_catalogue", { order: "nom" });
  const [objetId, setObjetId] = useState("");
  const [quantite, setQuantite] = useState("");
  const [msg, setMsg] = useState("");

  if (inventaires.error || lignes.error || catalogue.error)
    return <p className="admin-error">{inventaires.error || lignes.error || catalogue.error}</p>;
  if (!inventaires.rows || !lignes.rows || !catalogue.rows) return <p>Chargement…</p>;

  const arsenal = inventaires.rows.find((i) => i.type === "arsenal");
  if (!arsenal) return <p>Aucun arsenal trouvé.</p>;

  const stock = lignes.rows.filter((l) => l.inventaire_id === arsenal.id);

  function nomObjet(id) {
    return catalogue.rows.find((o) => o.id === id)?.nom || "?";
  }

  async function submit(e) {
    e.preventDefault();
    if (!objetId || quantite === "") return;
    const existing = stock.find((l) => l.objet_id === objetId);
    const err = existing
      ? await lignes.update(existing.id, { quantite: Number(quantite) })
      : await lignes.insert({ inventaire_id: arsenal.id, objet_id: objetId, quantite: Number(quantite) });
    if (err) setMsg(err);
    else {
      setMsg("");
      setObjetId("");
      setQuantite("");
    }
  }
  async function del(id) {
    if (!confirm("Retirer cet objet de l’arsenal ?")) return;
    const err = await lignes.remove(id);
    if (err) setMsg(err);
  }

  return (
    <div>
      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Objet</th>
              <th>Quantité</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {stock.map((l) => (
              <tr key={l.id}>
                <td>{nomObjet(l.objet_id)}</td>
                <td>{l.quantite}</td>
                <td className="admin-row-actions">
                  <button type="button" className="text-button" onClick={() => del(l.id)}>
                    Retirer
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <form className="admin-form" onSubmit={submit}>
        <h3>Définir la quantité d’un objet</h3>
        <p>Sélectionner un objet déjà présent met à jour sa quantité totale.</p>
        <div className="admin-ingredient-form">
          <select value={objetId} onChange={(e) => setObjetId(e.target.value)}>
            <option value="">Objet…</option>
            {catalogue.rows.map((o) => (
              <option key={o.id} value={o.id}>
                {o.nom}
              </option>
            ))}
          </select>
          <input
            type="number"
            min="0"
            placeholder="Quantité"
            value={quantite}
            onChange={(e) => setQuantite(e.target.value)}
          />
          <button className="text-button" type="submit">
            Enregistrer
          </button>
        </div>
        {msg && <p className="admin-error">{msg}</p>}
      </form>
    </div>
  );
}

export function Admin({ onCraftItem = () => {} }) {
  const session = useSession();
  const [tab, setTab] = useState("catalogue");
  // Aller-retour entre la fiche d'un objet et sa recette : quel objet
  // rouvrir côté catalogue, quelle recette rejoindre côté recettes.
  const [recetteFocusId, setRecetteFocusId] = useState(null);
  const [catalogueFocusId, setCatalogueFocusId] = useState(null);
  function viewRecette(objetId) {
    setRecetteFocusId(objetId);
    setTab("recettes");
  }
  function backToCatalogue(objetId) {
    setCatalogueFocusId(objetId);
    setTab("catalogue");
  }

  if (session === undefined)
    return (
      <main className="admin-page">
        <p>Chargement…</p>
      </main>
    );
  if (!session)
    return (
      <main className="admin-page" style={{ backgroundImage: `url(${ASSETS.login})` }}>
        <LoginForm />
      </main>
    );

  return (
    <main className="admin-page admin-page-authed">
      <header className="admin-header">
        <h1>Administration — Forteresse</h1>
        <div className="admin-header-actions">
          <span>{session.user.email}</span>
          <button className="text-button" onClick={() => supabase.auth.signOut()}>
            Se déconnecter
          </button>
          <a className="text-button" href="#forteresse">
            Retour au jeu
          </a>
        </div>
      </header>
      <nav className="admin-tabs">
        <button className={tab === "catalogue" ? "active" : ""} onClick={() => setTab("catalogue")}>
          Catalogue
        </button>
        <button className={tab === "categories" ? "active" : ""} onClick={() => setTab("categories")}>
          Catégories
        </button>
        <button className={tab === "recettes" ? "active" : ""} onClick={() => setTab("recettes")}>
          Recettes
        </button>
        <button className={tab === "classes" ? "active" : ""} onClick={() => setTab("classes")}>
          Classes
        </button>
        <button className={tab === "mercenaires" ? "active" : ""} onClick={() => setTab("mercenaires")}>
          Mercenaires
        </button>
        <button className={tab === "arsenal" ? "active" : ""} onClick={() => setTab("arsenal")}>
          Arsenal
        </button>
      </nav>
      <div className="admin-content parchment">
        {tab === "catalogue" && (
          <CatalogueSection onViewRecette={viewRecette} focusObjetId={catalogueFocusId} />
        )}
        {tab === "categories" && (
          <NamedListSection
            table="categorie"
            singular="catégorie"
            blockedBy="des objets du catalogue"
            hierarchical
          />
        )}
        {tab === "recettes" && (
          <RecettesSection
            onCraftItem={onCraftItem}
            onBack={backToCatalogue}
            focusObjetId={recetteFocusId}
          />
        )}
        {tab === "classes" && (
          <NamedListSection table="classe" singular="classe" blockedBy="des mercenaires" />
        )}
        {tab === "mercenaires" && <MercenairesSection />}
        {tab === "arsenal" && <ArsenalSection />}
      </div>
    </main>
  );
}
