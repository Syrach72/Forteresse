import { Fragment, useEffect, useRef, useState } from "react";
import { supabase } from "./supabaseClient";
import { ASSETS } from "./data";
import { useSessions } from "./Sessions.jsx";
import { TableauCompetences } from "./MercFiche.jsx";

// Atelier de fabrication d'un objet, déduit de la rubrique racine de sa
// catégorie (vérifié sur les recettes existantes : aucune exception). Il n'y
// a donc plus de champ « Atelier » à renseigner sur la fiche.
const ATELIER_PAR_RACINE = {
  armes: "forge",
  armures: "armurerie",
  "produits alchimiques": "alchimie",
  gemmes: "magie",
  // Objet divers : se fabrique à la forge OU à l'armurerie (au choix du joueur) ; "forge" n'est que la
  // valeur enregistrée sur la recette.
  "objet divers": "forge",
};
// Rubriques dont les objets peuvent entrer dans une recette. Les Produits
// Alchimiques y figurent : plusieurs recettes existantes en consomment.
const RACINES_INGREDIENTS = ["composants", "matériaux", "produits alchimiques"];
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

function useTable(table, { order = "id", key = "id" } = {}) {
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
    const { error } = await supabase.from(table).update(values).eq(key, id);
    if (error) return error.message;
    await reload();
    return "";
  }
  async function remove(id) {
    const { error } = await supabase.from(table).delete().eq(key, id);
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
    icone: "",
    veterance_requise: "",
    duree_fabrication_instances: "",
    cout_achat_or: "",
    portee: "",
    protection: "",
    type_armure: "",
    malus_discretion: "",
    malus_vitesse: "",
    malus_esquive: "",
    parade: "",
    allonge: "",
    type_degats: "",
    deux_mains: false,
    legere: false,
    emploi_materiau_id: "",
    emploi_production: "",
    emploi_production_outil: "",
    emploi_outil_id: "",
    emploi_entretien: "",
  };
}
// Malus d'armure (Discrétion, Vitesse) : entier négatif ou nul, 2 chiffres au
// plus. Un chiffre tapé sans signe devient négatif (2 -> -2), « - » seul reste
// en attente de son chiffre ; « 0 » = aucun malus, vide = non renseigné.
function nettoyerMalus(raw) {
  const chiffres = String(raw).replace(/\D/g, "").slice(0, 2);
  if (chiffres === "") return String(raw).includes("-") ? "-" : "";
  const n = Number(chiffres);
  return n === 0 ? "0" : `-${n}`;
}
function malusOuNull(v) {
  const n = Number(v);
  return v === "" || v === "-" || !Number.isFinite(n) ? null : n;
}

// Icônes du catalogue : réduites avant envoi (400 px au plus, WebP). Elles
// s'affichent à 185 px au maximum ; une image d'origine de plusieurs Mo
// (jusqu'à 3000 px) épuisait le quota de trafic du projet Supabase gratuit.
// Repli sur le fichier d'origine si la réduction échoue ou n'allège pas.
async function reduireIcone(file) {
  try {
    const bmp = await createImageBitmap(file);
    const s = Math.min(1, 400 / Math.max(bmp.width, bmp.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(bmp.width * s));
    canvas.height = Math.max(1, Math.round(bmp.height * s));
    const ctx = canvas.getContext("2d");
    ctx.imageSmoothingQuality = "high";
    ctx.drawImage(bmp, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise((r) => canvas.toBlob(r, "image/webp", 0.9));
    if (blob && blob.size < file.size) return new File([blob], "icone.webp", { type: "image/webp" });
  } catch {
    // image illisible par le navigateur : on envoie le fichier tel quel
  }
  return file;
}

async function uploadImage(bucket, originalFile, seed) {
  // Seules les icônes du catalogue sont réduites (les portraits de
  // mercenaires gardent leur qualité d'origine).
  const file = bucket === "catalogue-icones" ? await reduireIcone(originalFile) : originalFile;
  const ext = (file.name.split(".").pop() || "png").toLowerCase();
  const path = `${(seed || "image").replace(/[^a-z0-9-]/gi, "-")}-${Date.now()}.${ext}`;
  // Le nom du fichier contient déjà un timestamp unique : un même chemin ne
  // désigne jamais deux contenus différents. On peut donc dire au navigateur
  // de garder l'image en cache longtemps (1 an) sans risque d'affichage
  // périmé, ce qui réduit le trafic "Cached Egress" facturé par Supabase.
  const { error } = await supabase.storage.from(bucket).upload(path, file, {
    upsert: true,
    cacheControl: "31536000",
  });
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
// Confirmation de suppression en ligne (Confirmer/Annuler), plutot que la
// boite confirm() native du navigateur : elle est facile a manquer, et
// Chrome desactive silencieusement tous les confirm() suivants sur une page
// des qu'on en a declenche plusieurs rapprochees (case a cocher "Empecher
// cette page de creer d'autres boites de dialogue") — le bouton Supprimer
// semble alors ne plus rien faire du tout, sans aucune erreur visible.
function DeleteButton({ id, label = "Supprimer", confirmingId, onAskConfirm, onCancel, onConfirm }) {
  if (confirmingId === id) {
    return (
      <>
        <button type="button" className="text-button text-button-danger" onClick={onConfirm}>
          Confirmer
        </button>
        <button type="button" className="text-button" onClick={onCancel}>
          Annuler
        </button>
      </>
    );
  }
  return (
    <button type="button" className="text-button" onClick={onAskConfirm}>
      {label}
    </button>
  );
}
// Sélecteur avec recherche : les menus d'objets du catalogue dépassent 270
// entrées, illisibles en <select> natif. Un champ texte filtre la liste au
// fur et à mesure de la frappe (sous-chaîne, insensible à la casse) ; option
// vide toujours proposée en premier. `options` accepte un `group` optionnel
// par entrée pour reconstituer un regroupement façon <optgroup>.
function SearchableSelect({ value, onChange, options, emptyLabel = "—", ariaLabel, className = "" }) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const wrapRef = useRef(null);
  useEffect(() => {
    function onDocClick(e) {
      if (wrapRef.current && !wrapRef.current.contains(e.target)) {
        setOpen(false);
        setQuery("");
      }
    }
    document.addEventListener("mousedown", onDocClick);
    return () => document.removeEventListener("mousedown", onDocClick);
  }, []);
  const selected = options.find((o) => o.value === value);
  // Recherche insensible aux accents : les joueurs ne tapent pas toujours
  // "Épée" avec l'accent, et « objet_catalogue » contient beaucoup de noms
  // accentués (Épée, Défenseur, Griffe de troll…).
  const normaliser = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  const q = normaliser(query.trim());
  const filtered = q ? options.filter((o) => normaliser(o.label).includes(q)) : options;
  const groupes = [];
  const index = new Map();
  for (const o of filtered) {
    const cle = o.group || "";
    if (!index.has(cle)) {
      index.set(cle, groupes.length);
      groupes.push({ nom: cle, options: [] });
    }
    groupes[index.get(cle)].options.push(o);
  }
  function choisir(o) {
    onChange(o ? o.value : "");
    setOpen(false);
    setQuery("");
  }
  return (
    <div className={`searchable-select ${className}`.trim()} ref={wrapRef}>
      <input
        type="text"
        role="combobox"
        aria-expanded={open}
        aria-label={ariaLabel}
        value={open ? query : selected?.label || ""}
        placeholder={emptyLabel}
        onFocus={(e) => {
          setOpen(true);
          setQuery("");
          e.target.select();
        }}
        onChange={(e) => {
          setQuery(e.target.value);
          setOpen(true);
        }}
        onKeyDown={(e) => {
          if (e.key === "Escape") {
            setOpen(false);
            setQuery("");
            e.currentTarget.blur();
          }
          if (e.key === "Enter") {
            e.preventDefault();
            if (filtered[0]) choisir(filtered[0]);
          }
        }}
      />
      {open && (
        <ul className="searchable-select-list" role="listbox">
          <li>
            <button type="button" onMouseDown={(e) => e.preventDefault()} onClick={() => choisir(null)}>
              {emptyLabel}
            </button>
          </li>
          {groupes.map((g) => (
            <Fragment key={g.nom || "_"}>
              {g.nom && <li className="searchable-select-group">{g.nom}</li>}
              {g.options.map((o) => (
                <li key={o.value}>
                  <button
                    type="button"
                    className={o.value === value ? "active" : ""}
                    onMouseDown={(e) => e.preventDefault()}
                    onClick={() => choisir(o)}
                  >
                    {o.label}
                  </button>
                </li>
              ))}
            </Fragment>
          ))}
          {!filtered.length && <li className="searchable-select-empty">Aucun résultat.</li>}
        </ul>
      )}
    </div>
  );
}
function NamedListSection({ table, singular, blockedBy, hierarchical = false }) {
  const { rows, error, insert, update, remove } = useTable(table, {
    order: "nom",
  });
  const [editing, setEditing] = useState(null);
  const [nom, setNom] = useState("");
  const [parentId, setParentId] = useState("");
  const [msg, setMsg] = useState("");
  const [confirmingId, setConfirmingId] = useState(null);

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
          <DeleteButton
            id={r.id}
            confirmingId={confirmingId}
            onAskConfirm={() => setConfirmingId(r.id)}
            onCancel={() => setConfirmingId(null)}
            onConfirm={() => {
              setConfirmingId(null);
              del(r.id);
            }}
          />
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

// Catégorie racine d'une catégorie (remonte les parent_id).
function racineDe(categories, categorieId) {
  let current = categories.find((c) => c.id === categorieId);
  while (current?.parent_id) current = categories.find((c) => c.id === current.parent_id);
  return current || null;
}

// Bloc « Recette » de la fiche d'un objet fabricable : ingrédients, quantité
// produite et envoi vers l'atelier. Remplace l'ancien onglet Recettes. La
// ligne `recette` (une par objet dans l'interface) est créée en douce au
// premier ingrédient, avec code et nom repris de l'objet ; les ingrédients
// s'enregistrent immédiatement, sans passer par « Enregistrer » de la fiche.
// Sans `objet` (formulaire « Ajouter un objet »), le bloc travaille sur un
// brouillon (`brouillon` : { lignes, qteProduite }, tenu par la section) qui
// n'est enregistré qu'avec l'objet, au clic sur « Ajouter ».
function RecetteBlock({
  objet,
  atelier,
  objets,
  categories,
  recettes,
  ingredients,
  onCraftItem,
  brouillon,
  setBrouillon,
}) {
  const enBrouillon = !objet;
  const recette = enBrouillon
    ? undefined
    : recettes.rows.find((r) => r.resultat_objet_id === objet.id);
  const lignes = enBrouillon
    ? brouillon.lignes
    : recette
      ? ingredients.rows.filter((i) => i.recette_id === recette.id)
      : [];
  const [choix, setChoix] = useState({ objet_id: "", quantite: "1" });
  const [qtyEdits, setQtyEdits] = useState({});
  const [qteLocale, setQteLocale] = useState(String(recette?.quantite_produite ?? 1));
  const qteProduite = enBrouillon ? brouillon.qteProduite : qteLocale;
  const setQteProduite = enBrouillon
    ? (v) => setBrouillon({ ...brouillon, qteProduite: v })
    : setQteLocale;
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);

  function nomObjet(id) {
    return objets.find((o) => o.id === id)?.nom || "?";
  }
  // Ingrédients proposés, regroupés par rubrique : hors l'objet lui-même et
  // hors ceux déjà dans la recette (un même objet ne peut y figurer qu'une fois).
  const groupes = [];
  objets.forEach((o) => {
    const racine = racineDe(categories, o.categorie_id);
    if (
      !racine ||
      !RACINES_INGREDIENTS.includes(racine.nom.trim().toLowerCase()) ||
      o.id === objet?.id ||
      o.actif === false ||
      lignes.some((l) => l.objet_id === o.id)
    )
      return;
    let groupe = groupes.find((g) => g.nom === racine.nom);
    if (!groupe) groupes.push((groupe = { nom: racine.nom, options: [] }));
    groupe.options.push(o);
  });

  async function ajouterIngredient() {
    const quantite = Number(choix.quantite);
    if (!choix.objet_id) {
      setMsg("Choisissez un ingrédient.");
      return;
    }
    if (!Number.isInteger(quantite) || quantite < 1) {
      setMsg("La quantité doit être un entier d’au moins 1.");
      return;
    }
    if (enBrouillon) {
      setMsg("");
      setBrouillon({
        ...brouillon,
        lignes: [
          ...brouillon.lignes,
          { id: choix.objet_id, objet_id: choix.objet_id, quantite_requise: quantite },
        ],
      });
      setChoix({ objet_id: "", quantite: "1" });
      return;
    }
    setBusy(true);
    setMsg("");
    let recetteId = recette?.id;
    let creee = false;
    if (!recetteId) {
      const produite = Math.floor(Number(qteProduite));
      const { data, error } = await supabase
        .from("recette")
        .insert({
          code_unique: `recette-${objet.code_unique}`,
          nom: objet.nom,
          atelier,
          resultat_objet_id: objet.id,
          quantite_produite: produite >= 1 ? produite : 1,
        })
        .select("id")
        .single();
      if (error) {
        setBusy(false);
        setMsg(error.message);
        return;
      }
      recetteId = data.id;
      creee = true;
    }
    const err = await ingredients.insert({
      recette_id: recetteId,
      objet_id: choix.objet_id,
      quantite_requise: quantite,
    });
    // Recette créée à l'instant mais ingrédient refusé : on ne laisse pas
    // une recette vide derrière soi.
    if (err && creee) await supabase.from("recette").delete().eq("id", recetteId);
    await recettes.reload();
    setBusy(false);
    if (err) setMsg(err);
    else setChoix({ objet_id: "", quantite: "1" });
  }
  async function retirerIngredient(id) {
    if (enBrouillon) {
      setBrouillon({ ...brouillon, lignes: brouillon.lignes.filter((l) => l.id !== id) });
      return;
    }
    setMsg((await ingredients.remove(id)) || "");
  }
  async function enregistrerQuantite(ligne) {
    const brut = qtyEdits[ligne.id];
    const n = Number(brut);
    setQtyEdits((prev) => {
      const next = { ...prev };
      delete next[ligne.id];
      return next;
    });
    if (brut === undefined || brut === "" || !Number.isInteger(n) || n < 1 || n === ligne.quantite_requise)
      return;
    setMsg((await ingredients.update(ligne.id, { quantite_requise: n })) || "");
  }
  async function enregistrerQuantiteProduite() {
    if (enBrouillon) return; // validée à l'ajout de l'objet
    const n = Number(qteProduite);
    if (!Number.isInteger(n) || n < 1) {
      setQteProduite(String(recette?.quantite_produite ?? 1));
      return;
    }
    if (recette && n !== recette.quantite_produite)
      setMsg((await recettes.update(recette.id, { quantite_produite: n })) || "");
  }
  // Entrée dans un champ du bloc : ne doit pas enregistrer la fiche entière
  // (le bloc est dans son formulaire) ; dans la ligne d'ajout, elle ajoute.
  function surEntree(e) {
    if (e.key !== "Enter" || e.target.tagName !== "INPUT") return;
    e.preventDefault();
    if (e.target.dataset.ajout) ajouterIngredient();
  }

  return (
    <div className="admin-recette-block" onKeyDown={surEntree}>
      <p className="eyebrow admin-section-label">Recette</p>
      {lignes.length ? (
        <ul className="admin-ingredient-list">
          {lignes.map((l) => (
            <li key={l.id}>
              {nomObjet(l.objet_id)} ×
              <input
                type="number"
                min="1"
                className="ingredient-qty-input"
                value={enBrouillon ? l.quantite_requise : (qtyEdits[l.id] ?? l.quantite_requise)}
                onChange={(e) =>
                  enBrouillon
                    ? setBrouillon({
                        ...brouillon,
                        lignes: brouillon.lignes.map((x) =>
                          x.id === l.id ? { ...x, quantite_requise: e.target.value } : x,
                        ),
                      })
                    : setQtyEdits({ ...qtyEdits, [l.id]: e.target.value })
                }
                onBlur={() => !enBrouillon && enregistrerQuantite(l)}
                aria-label={`Quantité de ${nomObjet(l.objet_id)}`}
              />
              <button
                type="button"
                className="text-button"
                onClick={() => retirerIngredient(l.id)}
                aria-label={`Retirer ${nomObjet(l.objet_id)}`}
              >
                ✕
              </button>
            </li>
          ))}
        </ul>
      ) : (
        <p className="muted">Aucun ingrédient renseigné pour l’instant.</p>
      )}
      <div className="admin-ingredient-form">
        <SearchableSelect
          value={choix.objet_id}
          onChange={(v) => setChoix({ ...choix, objet_id: v })}
          options={groupes.flatMap((g) => g.options.map((o) => ({ value: o.id, label: o.nom, group: g.nom })))}
          emptyLabel="Ingrédient…"
          ariaLabel="Ingrédient à ajouter"
        />
        <input
          type="number"
          min="1"
          placeholder="Qté"
          data-ajout="1"
          value={choix.quantite}
          onChange={(e) => setChoix({ ...choix, quantite: e.target.value })}
          aria-label="Quantité de l’ingrédient à ajouter"
        />
        <button type="button" className="text-button" disabled={busy} onClick={ajouterIngredient}>
          Ajouter l’ingrédient
        </button>
      </div>
      <div className="admin-ingredient-form admin-recette-footer">
        <label htmlFor="rec-qte-produite">Quantité produite</label>
        <input
          id="rec-qte-produite"
          type="number"
          min="1"
          value={qteProduite}
          onChange={(e) => setQteProduite(e.target.value)}
          onBlur={enregistrerQuantiteProduite}
        />
        {lignes.length > 0 && !enBrouillon && (
          <button
            type="button"
            className="text-button"
            onClick={() => onCraftItem(objet.id, recette.atelier)}
          >
            {CRAFT_BUTTON_LABELS[recette.atelier] || "Placer en fabrication"}
          </button>
        )}
      </div>
      {enBrouillon && (
        <p className="muted">La recette sera créée en même temps que l’objet, au clic sur « Ajouter ».</p>
      )}
      {msg && <p className="admin-error">{msg}</p>}
    </div>
  );
}

const BROUILLON_VIDE = { lignes: [], qteProduite: "1" };

function CatalogueSection({ onCraftItem }) {
  const { rows, error, reload, update, remove } = useTable("objet_catalogue", {
    order: "nom",
  });
  // Recette en cours de saisie dans le formulaire « Ajouter un objet ».
  const [brouillon, setBrouillon] = useState(BROUILLON_VIDE);
  const categories = useTable("categorie", { order: "nom" });
  const recettes = useTable("recette", { order: "nom" });
  const ingredients = useTable("ingredient_recette", { order: "id" });
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(emptyCatalogueItem());
  const [iconFile, setIconFile] = useState(null);
  const [uploading, setUploading] = useState(false);
  const [msg, setMsg] = useState("");
  const [filterCategorie, setFilterCategorie] = useState("");
  const [confirmingId, setConfirmingId] = useState(null);
  const [bulkRecache, setBulkRecache] = useState(null); // { i, total, echecs } pendant le traitement, sinon null
  const [confirmingBulk, setConfirmingBulk] = useState(false);

  // Reprend chaque icône déjà en ligne (comme le bouton "Réenregistrer"
  // individuel) pour lui appliquer le nouveau cache navigateur 1 an. Ne
  // touche pas aux objets sans icône. Continue même si un objet échoue
  // (image supprimée manuellement du bucket, etc.) et récapitule à la fin.
  async function reencacherTout() {
    setConfirmingBulk(false);
    const cibles = rows.filter((r) => r.icone);
    const echecs = [];
    for (let i = 0; i < cibles.length; i++) {
      const r = cibles[i];
      setBulkRecache({ i: i + 1, total: cibles.length, echecs: echecs.length });
      try {
        const res = await fetch(r.icone);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const original = await res.blob();
        const reduit = await reduireIcone(new File([original], "icone", { type: original.type }));
        const result = await uploadImage("catalogue-icones", reduit, r.code_unique);
        if (result.error) throw new Error(result.error);
        const err = await update(r.id, { icone: result.url });
        if (err) throw new Error(err);
      } catch (e) {
        echecs.push(`${r.nom} (${r.code_unique}) : ${e.message || e}`);
      }
    }
    setBulkRecache(null);
    setMsg(
      echecs.length
        ? `${cibles.length - echecs.length}/${cibles.length} icônes réenregistrées. Échecs : ${echecs.join(" · ")}`
        : `${cibles.length} icônes réenregistrées avec le nouveau cache.`,
    );
  }

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
  // Bouclier : la catégorie de l'objet ou l'un de ses ancêtres s'appelle
  // « Bouclier… » (sous la rubrique Armures).
  function isCategorieBouclier(categorieId) {
    let current = categories.rows?.find((c) => c.id === categorieId);
    while (current) {
      if (current.nom.trim().toLowerCase().startsWith("bouclier")) return true;
      current = categories.rows.find((c) => c.id === current.parent_id);
    }
    return false;
  }
  // Armures : sous la rubrique « Armures », boucliers exclus (un bouclier
  // n'a ni protection ni type, ni vétérance, ni portée : voir malus).
  function isCategorieArmure(categorieId) {
    let current = categories.rows?.find((c) => c.id === categorieId);
    let dansArmures = false;
    while (current) {
      const nom = current.nom.trim().toLowerCase();
      if (nom.startsWith("bouclier")) return false;
      if (nom === "armures") dansArmures = true;
      current = categories.rows.find((c) => c.id === current.parent_id);
    }
    return dansArmures;
  }
  function categorieFlags(categorieId) {
    const arme = isCategorieArme(categorieId);
    const armure = !arme && isCategorieArmure(categorieId);
    const bouclier = !arme && isCategorieBouclier(categorieId);
    const alchimique = !arme && isCategorieParmi(categorieId, ["produits alchimiques"]);
    const gemme = !arme && isCategorieParmi(categorieId, ["gemmes"]);
    // Collecte : un métier (Mineur, Bûcheron, Tanneur...) du Marché, page
    // « Matériaux et Embauche ». Ne rejoint pas l'arsenal, va dans Gestion
    // des Employés.
    const emploi = !arme && isCategorieParmi(categorieId, ["collecte"]);
    // « Objet divers » : achetable, et fabricable indifféremment à la forge ou à l'armurerie
    // (boutons « Catalogue des objets » de ces deux pages) quand il a une recette.
    const craftable =
      arme ||
      isCategorieParmi(categorieId, ["produits alchimiques", "gemmes", "armures", "objet divers"]);
    // Achat au marché : armes/armures/produits alchimiques (qui ont aussi une
    // fabrication), composants/objets divers (achetés directement, sans
    // recette) et collecte (coût d'embauche), mais jamais les gemmes
    // (obtenues seulement par fabrication, sertissage ou quête — règle de Bruno).
    const achetable =
      (craftable && !gemme) ||
      isCategorieParmi(categorieId, ["composants", "objet divers", "collecte"]);
    const racine = racineDe(categories.rows || [], categorieId);
    const atelier = ATELIER_PAR_RACINE[racine?.nom.trim().toLowerCase()] || null;
    return { arme, armure, bouclier, alchimique, gemme, emploi, craftable, achetable, atelier };
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
      protection: row.protection || "",
      type_armure: row.type_armure || "",
      malus_discretion: row.malus_discretion == null ? "" : String(row.malus_discretion),
      malus_vitesse: row.malus_vitesse == null ? "" : String(row.malus_vitesse),
      malus_esquive: row.malus_esquive == null ? "" : String(row.malus_esquive),
      parade: row.parade || "",
      allonge: row.allonge || "",
      type_degats: row.type_degats || "",
      deux_mains: !!row.deux_mains,
      legere: !!row.legere,
      emploi_materiau_id: row.emploi_materiau_id || "",
      emploi_production: row.emploi_production ?? "",
      emploi_production_outil: row.emploi_production_outil ?? "",
      emploi_outil_id: row.emploi_outil_id || "",
      emploi_entretien: row.emploi_entretien ?? "",
    });
    setIconFile(null);
    setMsg("");
  }
  function cancel() {
    setEditing(null);
    setBrouillon(BROUILLON_VIDE);
    setForm(emptyCatalogueItem(categories.rows?.[0]?.id || ""));
    setIconFile(null);
    setMsg("");
  }
  // Ajoute l'objet puis, s'il est fabricable et que le brouillon a des
  // ingrédients, sa recette. Tout ou rien : si la recette échoue, l'objet est
  // retiré (rien ne reste à moitié créé) et la saisie est conservée.
  async function ajouterAvecRecette(values, atelier) {
    const lignes = atelier ? brouillon.lignes : [];
    if (lignes.some((l) => !Number.isInteger(Number(l.quantite_requise)) || Number(l.quantite_requise) < 1))
      return "Chaque ingrédient de la recette doit avoir une quantité entière d’au moins 1.";
    const produite = Math.floor(Number(brouillon.qteProduite));
    if (lignes.length && !(produite >= 1)) return "La quantité produite doit être d’au moins 1.";
    const { data, error: errObjet } = await supabase
      .from("objet_catalogue")
      .insert(values)
      .select("id")
      .single();
    if (errObjet) return errObjet.message;
    if (lignes.length) {
      const { data: rec, error: errRecette } = await supabase
        .from("recette")
        .insert({
          code_unique: `recette-${values.code_unique}`,
          nom: values.nom,
          atelier,
          resultat_objet_id: data.id,
          quantite_produite: produite,
        })
        .select("id")
        .single();
      let echec = errRecette?.message || "";
      if (!echec) {
        const { error: errLignes } = await supabase.from("ingredient_recette").insert(
          lignes.map((l) => ({
            recette_id: rec.id,
            objet_id: l.objet_id,
            quantite_requise: Number(l.quantite_requise),
          })),
        );
        echec = errLignes?.message || "";
      }
      if (echec) {
        await supabase.from("recette").delete().eq("resultat_objet_id", data.id);
        const { error: errNettoyage } = await supabase
          .from("objet_catalogue")
          .delete()
          .eq("id", data.id);
        await reload();
        return (
          `La recette n’a pas pu être créée (${echec}) : l’objet n’a pas été ajouté.` +
          (errNettoyage ? ` Nettoyage impossible, supprimez « ${values.nom} » à la main.` : "")
        );
      }
      await recettes.reload();
      await ingredients.reload();
    }
    await reload();
    return "";
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
    const { arme, armure, bouclier, alchimique, emploi, craftable, achetable, atelier } = categorieFlags(
      form.categorie_id,
    );
    // Un objet qui a une recette doit rester dans une rubrique fabricable :
    // sinon la recette deviendrait invisible tout en restant en base.
    const recette = editing
      ? recettes.rows.find((r) => r.resultat_objet_id === editing)
      : null;
    if (recette && !atelier) {
      setMsg(
        "Cet objet a une recette : sa catégorie doit rester Armes, Armures, Produits Alchimiques ou Gemmes.",
      );
      return;
    }
    const values = {
      ...form,
      description: form.description || null,
      icone,
      // Vetérance : Armes et Armures (hors boucliers). Portee : Armes et
      // Produits Alchimiques (texte libre, ex. « 30/90c » ou « personnelle »).
      // Protection et type : Armures seules (hors boucliers). Stats de combat
      // sans sens pour une potion ou une gemme. Cout d'achat et temps de
      // fabrication : Armes + Produits Alchimiques/Gemmes/Armures. Effaces
      // si l'objet ne fait plus partie de la rubrique concernee, pour ne
      // pas laisser trainer une valeur sur un ingredient ou un materiau.
      veterance_requise:
        arme || armure ? toIntOrNull(form.veterance_requise) : null,
      duree_fabrication_instances: craftable
        ? toIntOrNull(form.duree_fabrication_instances)
        : null,
      cout_achat_or: achetable ? toIntOrNull(form.cout_achat_or) : null,
      portee: arme || alchimique ? form.portee.trim() || null : null,
      protection: armure ? form.protection.trim() || null : null,
      type_armure: armure ? form.type_armure || null : null,
      malus_discretion: armure || bouclier ? malusOuNull(form.malus_discretion) : null,
      malus_vitesse: armure || bouclier ? malusOuNull(form.malus_vitesse) : null,
      malus_esquive: bouclier ? malusOuNull(form.malus_esquive) : null,
      parade: bouclier ? form.parade.trim() || null : null,
      allonge: arme ? form.allonge.trim() || null : null,
      type_degats: arme ? form.type_degats.trim() || null : null,
      deux_mains: arme ? !!form.deux_mains : false,
      legere: arme ? !!form.legere : false,
      emploi_materiau_id: emploi ? form.emploi_materiau_id || null : null,
      emploi_production: emploi ? toIntOrNull(form.emploi_production) : null,
      emploi_production_outil: emploi ? toIntOrNull(form.emploi_production_outil) : null,
      emploi_outil_id: emploi ? form.emploi_outil_id || null : null,
      emploi_entretien: emploi ? toIntOrNull(form.emploi_entretien) : null,
    };
    const err = editing
      ? await update(editing, values)
      : await ajouterAvecRecette(values, craftable ? atelier : null);
    if (err) {
      setMsg(err);
      return;
    }
    // Changement de rubrique fabricable (ex. Armes -> Armures) : l'atelier de
    // la recette suit, pour que « Placer dans… » et le jeu restent cohérents.
    if (recette && recette.atelier !== atelier) {
      const errAtelier = await recettes.update(recette.id, { atelier });
      if (errAtelier) {
        setMsg(errAtelier);
        return;
      }
    }
    cancel();
  }
  // Supprimer un objet supprime aussi sa propre recette (ses lignes
  // d'ingrédients partent en cascade). Refusé d'emblée s'il sert
  // d'ingrédient ailleurs ; si la suppression échoue malgré tout (objet dans
  // un inventaire...), la recette est recréée à l'identique.
  async function del(id) {
    setMsg("");
    const serviDans = ingredients.rows.find((i) => i.objet_id === id);
    if (serviDans) {
      const autre = recettes.rows.find((r) => r.id === serviDans.recette_id);
      setMsg(
        `Suppression impossible : cet objet est un ingrédient de la recette « ${autre?.nom || "?"} ».`,
      );
      return;
    }
    const recette = recettes.rows.find((r) => r.resultat_objet_id === id);
    const lignes = recette ? ingredients.rows.filter((i) => i.recette_id === recette.id) : [];
    if (recette) {
      const { error: errRecette } = await supabase.from("recette").delete().eq("id", recette.id);
      if (errRecette) {
        setMsg("Suppression impossible : " + errRecette.message);
        return;
      }
    }
    const err = await remove(id);
    if (recette) {
      if (err) {
        await supabase.from("recette").insert(recette);
        if (lignes.length) await supabase.from("ingredient_recette").insert(lignes);
      }
      await recettes.reload();
      await ingredients.reload();
    }
    if (err)
      setMsg("Suppression impossible (probablement utilisé dans un inventaire) : " + err);
  }

  if (error || categories.error || recettes.error || ingredients.error)
    return (
      <p className="admin-error">
        {error || categories.error || recettes.error || ingredients.error}
      </p>
    );
  if (!rows || !categories.rows || !recettes.rows || !ingredients.rows)
    return <p>Chargement…</p>;
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
      </div>
      {(() => {
        const { arme, armure, bouclier, alchimique, emploi, craftable, achetable, atelier } = categorieFlags(
          form.categorie_id,
        );
        if (!craftable && !achetable) return null;
        // Cellule de malus (entier négatif ou nul) : Discrétion et Vitesse pour
        // les armures et les boucliers, Esquive pour les boucliers seuls.
        const celluleMalus = (champ, id, libelle) => (
          <div className="field field-xs">
            <label htmlFor={id}>{libelle}</label>
            <div className="input-wrap">
              <input
                id={id}
                inputMode="numeric"
                maxLength={3}
                placeholder="-1"
                value={form[champ]}
                onChange={(e) => setForm({ ...form, [champ]: nettoyerMalus(e.target.value) })}
              />
            </div>
          </div>
        );
        return (
          <>
          <p className="eyebrow admin-section-label">
            {craftable ? "Fabrication" : emploi ? "Embauche" : "Achat"}
          </p>
          <div className="admin-form-grid admin-form-grid-compact">
            {(arme || armure) && (
              <div className="field field-xs">
                <label htmlFor="cat-veterance">Vétérance requise</label>
                <div className="input-wrap">
                  <input
                    id="cat-veterance"
                    type="number"
                    min="1"
                    max="20"
                    value={form.veterance_requise}
                    onChange={(e) =>
                      setForm({
                        ...form,
                        veterance_requise: e.target.value.slice(0, 2),
                      })
                    }
                  />
                </div>
              </div>
            )}
            {craftable && (
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
            )}
            {achetable && (
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
            )}
            {(arme || alchimique) && (
              <div className="field field-portee">
                <label htmlFor="cat-portee">Portée</label>
                <div className="input-wrap">
                  <input
                    id="cat-portee"
                    maxLength={12}
                    placeholder={arme ? "30/90c" : "personnelle"}
                    title="Portée en cases (ex. 30/90c) ou « personnelle » ; vide pour une arme de corps à corps"
                    value={form.portee}
                    onChange={(e) => setForm({ ...form, portee: e.target.value.slice(0, 12) })}
                  />
                </div>
              </div>
            )}
            {arme && (
              <>
                <div className="field field-huit">
                  <label htmlFor="cat-allonge">Allonge</label>
                  <div className="input-wrap">
                    <input
                      id="cat-allonge"
                      maxLength={8}
                      value={form.allonge}
                      onChange={(e) => setForm({ ...form, allonge: e.target.value.slice(0, 8) })}
                    />
                  </div>
                </div>
                <div className="field field-huit">
                  <label htmlFor="cat-type-degats">Type de dégâts</label>
                  <div className="input-wrap">
                    <input
                      id="cat-type-degats"
                      maxLength={8}
                      value={form.type_degats}
                      onChange={(e) =>
                        setForm({ ...form, type_degats: e.target.value.slice(0, 8) })
                      }
                    />
                  </div>
                </div>
                <div className="field field-xs">
                  <label htmlFor="cat-deux-mains">Deux Mains</label>
                  <select
                    id="cat-deux-mains"
                    value={form.deux_mains ? "oui" : "non"}
                    onChange={(e) =>
                      setForm({ ...form, deux_mains: e.target.value === "oui" })
                    }
                  >
                    <option value="non">Non</option>
                    <option value="oui">Oui</option>
                  </select>
                </div>
                <div className="field field-xs">
                  <label htmlFor="cat-legere">Légère</label>
                  <select
                    id="cat-legere"
                    value={form.legere ? "oui" : "non"}
                    onChange={(e) => setForm({ ...form, legere: e.target.value === "oui" })}
                  >
                    <option value="non">Non</option>
                    <option value="oui">Oui</option>
                  </select>
                </div>
              </>
            )}
            {armure && (
              <>
                <div className="field field-protection">
                  <label htmlFor="cat-protection">Protection</label>
                  <div className="input-wrap">
                    <input
                      id="cat-protection"
                      maxLength={5}
                      value={form.protection}
                      onChange={(e) =>
                        setForm({ ...form, protection: e.target.value.slice(0, 5) })
                      }
                    />
                  </div>
                </div>
                <div className="field field-xs">
                  <label htmlFor="cat-type-armure">Type</label>
                  <div className="input-wrap">
                    <input
                      id="cat-type-armure"
                      maxLength={1}
                      pattern="[A-Z]"
                      value={form.type_armure}
                      onChange={(e) =>
                        setForm({
                          ...form,
                          type_armure: e.target.value
                            .toUpperCase()
                            .replace(/[^A-Z]/g, "")
                            .slice(0, 1),
                        })
                      }
                    />
                  </div>
                </div>
              </>
            )}
            {bouclier && (
              <div className="field field-protection">
                <label htmlFor="cat-parade">Parade</label>
                <div className="input-wrap">
                  <input
                    id="cat-parade"
                    maxLength={5}
                    value={form.parade}
                    onChange={(e) => setForm({ ...form, parade: e.target.value.slice(0, 5) })}
                  />
                </div>
              </div>
            )}
            {(armure || bouclier) && (
              <>
                {celluleMalus("malus_discretion", "cat-malus-discretion", "Discrétion")}
                {celluleMalus("malus_vitesse", "cat-malus-vitesse", "Vitesse")}
              </>
            )}
            {bouclier && celluleMalus("malus_esquive", "cat-malus-esquive", "Esquive")}
          </div>
          {emploi && (
            <>
              <p className="eyebrow admin-section-label">Métier</p>
              <div className="admin-form-grid admin-form-grid-compact">
                <div className="field">
                  <label htmlFor="cat-emploi-materiau">Matériau produit</label>
                  <SearchableSelect
                    value={form.emploi_materiau_id}
                    onChange={(v) => setForm({ ...form, emploi_materiau_id: v })}
                    options={rows
                      .filter((r) => racineDe(categories.rows || [], r.categorie_id)?.nom === "Matériaux")
                      .map((r) => ({ value: r.id, label: r.nom }))}
                    emptyLabel="— Aucun —"
                    ariaLabel="Matériau produit par ce métier"
                  />
                </div>
                <div className="field field-narrow">
                  <label htmlFor="cat-emploi-production">Production de base (par instance)</label>
                  <div className="input-wrap">
                    <input
                      id="cat-emploi-production"
                      type="number"
                      min="0"
                      value={form.emploi_production}
                      onChange={(e) => setForm({ ...form, emploi_production: e.target.value })}
                    />
                  </div>
                </div>
                <div className="field field-narrow">
                  <label htmlFor="cat-emploi-production-outil">
                    Bonus de production avec outil
                  </label>
                  <div className="input-wrap">
                    <input
                      id="cat-emploi-production-outil"
                      type="number"
                      min="0"
                      value={form.emploi_production_outil}
                      onChange={(e) => setForm({ ...form, emploi_production_outil: e.target.value })}
                    />
                  </div>
                </div>
                <div className="field">
                  <label htmlFor="cat-emploi-outil">Outil spécialisé</label>
                  <SearchableSelect
                    value={form.emploi_outil_id}
                    onChange={(v) => setForm({ ...form, emploi_outil_id: v })}
                    options={rows.map((r) => ({ value: r.id, label: r.nom }))}
                    emptyLabel="— Aucun —"
                    ariaLabel="Outil spécialisé de ce métier"
                  />
                </div>
                <div className="field field-narrow">
                  <label htmlFor="cat-emploi-entretien">
                    Coût d’entretien (Po, par instance)
                  </label>
                  <div className="input-wrap">
                    <input
                      id="cat-emploi-entretien"
                      type="number"
                      min="0"
                      value={form.emploi_entretien}
                      onChange={(e) => setForm({ ...form, emploi_entretien: e.target.value })}
                    />
                  </div>
                </div>
              </div>
            </>
          )}
          {/* Recette : uniquement les rubriques fabricables (Armes, Armures,
              Produits Alchimiques, Gemmes). Composants/Objet divers/Collecte
              s'achètent ou se collectent, ils n'ont pas de recette. */}
          {craftable &&
            (editing ? (
              <RecetteBlock
                key={editing}
                objet={rows.find((r) => r.id === editing)}
                atelier={atelier}
                objets={rows}
                categories={categories.rows}
                recettes={recettes}
                ingredients={ingredients}
                onCraftItem={onCraftItem}
              />
            ) : (
              <RecetteBlock
                key="nouveau"
                atelier={atelier}
                objets={rows}
                categories={categories.rows}
                recettes={recettes}
                ingredients={ingredients}
                brouillon={brouillon}
                setBrouillon={setBrouillon}
              />
            ))}
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
          {form.icone && !iconFile && (
            <button
              type="button"
              className="text-button"
              onClick={async () => {
                const res = await fetch(form.icone);
                const blob = await res.blob();
                const ext = blob.type.split("/")[1] || "png";
                setIconFile(new File([blob], `icone.${ext}`, { type: blob.type || "image/png" }));
              }}
            >
              Réenregistrer (cache prolongé)
            </button>
          )}
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
      <div className="admin-bulk-recache">
        {bulkRecache ? (
          <p className="muted">
            Réenregistrement en cours… {bulkRecache.i}/{bulkRecache.total}
            {bulkRecache.echecs ? ` (${bulkRecache.echecs} échec${bulkRecache.echecs > 1 ? "s" : ""})` : ""}
          </p>
        ) : confirmingBulk ? (
          <p>
            Réenregistrer les {rows.filter((r) => r.icone).length} icônes existantes avec le nouveau cache
            (1 an) ? Aucun changement visuel, mais ça prend quelques minutes.{" "}
            <button type="button" className="text-button" onClick={reencacherTout}>
              Confirmer
            </button>{" "}
            <button type="button" className="text-button" onClick={() => setConfirmingBulk(false)}>
              Annuler
            </button>
          </p>
        ) : (
          <button type="button" className="text-button" onClick={() => setConfirmingBulk(true)}>
            Réenregistrer toutes les icônes (cache prolongé)
          </button>
        )}
      </div>
      {msg && !bulkRecache && !confirmingBulk && <p className="admin-error">{msg}</p>}
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
              <th></th>
            </tr>
          </thead>
          <tbody>
            {visibleRows.map((r) => (
              <Fragment key={r.id}>
                <tr className={editing === r.id ? "editing" : ""}>
                  <td>
                    {r.icone ? (
                      <img className="admin-icon" src={r.icone} alt="" loading="lazy" decoding="async" />
                    ) : (
                      "—"
                    )}
                  </td>
                  <td>{r.nom}</td>
                  <td>{r.code_unique}</td>
                  <td>{nomCategorie(r.categorie_id)}</td>
                  <td>{r.empilable ? "Oui" : "Non"}</td>
                  <td className="admin-row-actions">
                    <button type="button" className="text-button" onClick={() => startEdit(r)}>
                      Modifier
                    </button>
                    <DeleteButton
                      id={r.id}
                      confirmingId={confirmingId}
                      onAskConfirm={() => setConfirmingId(r.id)}
                      onCancel={() => setConfirmingId(null)}
                      onConfirm={() => {
                        setConfirmingId(null);
                        del(r.id);
                      }}
                    />
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

// Tableau de compétences d'un mercenaire (fiche admin) : un clic sur une cellule ouvre le choix
// d'une compétence du catalogue (objets des rubriques « Compétences Passives » pour une cellule
// passive, « Compétences Actives » pour une cellule active) ou vide la cellule. Aucune cellule
// n'est grisée ici.
function CompetencesEditor({ mercenaireId }) {
  const [catalogue, setCatalogue] = useState(null);
  const [cellules, setCellules] = useState(null);
  const [sel, setSel] = useState(null);
  const [choix, setChoix] = useState("");
  const [msg, setMsg] = useState("");
  async function charger() {
    const [c, o, m] = await Promise.all([
      supabase.from("categorie").select("id, nom, parent_id"),
      supabase.from("objet_catalogue").select("id, nom, icone, categorie_id").order("nom"),
      supabase
        .from("mercenaire_competence")
        .select("veterance, type, position, competence_id")
        .eq("mercenaire_id", mercenaireId),
    ]);
    const err = c.error || o.error || m.error;
    if (err) setMsg(err.message);
    else {
      const racine = (id) => {
        let cur = c.data.find((x) => x.id === id);
        while (cur?.parent_id) cur = c.data.find((x) => x.id === cur.parent_id);
        return (cur?.nom || "").toLowerCase();
      };
      setCatalogue(
        o.data
          .map((x) => ({ ...x, racine: racine(x.categorie_id) }))
          .filter((x) => x.racine.includes("compétences") || x.racine.includes("competences")),
      );
      setCellules(m.data);
      setMsg("");
    }
  }
  useEffect(() => {
    setSel(null);
    setCatalogue(null);
    setCellules(null);
    charger();
  }, [mercenaireId]);
  if (msg && !cellules) return <p className="admin-error">{msg}</p>;
  if (!cellules || !catalogue) return <p>Chargement du tableau de compétences…</p>;
  const parId = new Map(catalogue.map((c) => [c.id, c]));
  const idPlace = (niveau, type, position) =>
    cellules.find((x) => x.veterance === niveau && x.type === type && x.position === position)?.competence_id || "";
  const affichage = cellules.map((x) => ({ ...x, competence: parId.get(x.competence_id) }));
  async function placer() {
    if (!sel) return;
    setMsg("");
    const ligne = { mercenaire_id: mercenaireId, veterance: sel.niveau, type: sel.type, position: sel.position };
    const { error } = choix
      ? await supabase
          .from("mercenaire_competence")
          .upsert({ ...ligne, competence_id: choix }, { onConflict: "mercenaire_id,veterance,type,position" })
      : await supabase.from("mercenaire_competence").delete().match(ligne);
    if (error) setMsg(error.message);
    else await charger();
  }
  // Une cellule passive ne propose que les compétences passives, une active que les actives.
  const options = sel
    ? catalogue
        .filter((c) => c.racine.includes(sel.type === "passive" ? "passive" : "active"))
        .map((c) => ({ value: c.id, label: c.nom }))
    : [];
  return (
    <div className="admin-form comp-editeur">
      <h3>Compétences</h3>
      <p className="muted">
        Cliquez une cellule (ligne = vétérance requise), choisissez une compétence du catalogue (rubriques « Compétences
        Passives » et « Compétences Actives ») puis « Placer ».
      </p>
      <TableauCompetences
        cellules={affichage}
        veterance={null}
        selection={sel}
        onCell={(c) => {
          setSel(c);
          setChoix(idPlace(c.niveau, c.type, c.position));
          setMsg("");
        }}
      />
      {sel && (
        <div className="comp-editeur-choix">
          <strong>
            Vétérance {sel.niveau} · {sel.type === "passive" ? "passive" : "active"} n°{sel.position + 1}
          </strong>
          <SearchableSelect
            value={choix}
            onChange={setChoix}
            options={options}
            emptyLabel="— Cellule vide —"
            ariaLabel="Compétence à placer"
          />
          <button type="button" className="primary" onClick={placer}>
            {choix ? "Placer" : "Vider la cellule"}
          </button>
          <button type="button" className="text-button" onClick={() => setSel(null)}>
            Fermer
          </button>
        </div>
      )}
      {msg && <p className="admin-error">{msg}</p>}
    </div>
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
  const [confirmingId, setConfirmingId] = useState(null);

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
              <label htmlFor={`merc-${field}`}>
                {field === "veterance" ? "Vétérance de départ" : field[0].toUpperCase() + field.slice(1)}
              </label>
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
              <th>Vétérance de départ</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {mercenaires.rows.map((m) => (
              <Fragment key={m.id}>
                <tr className={editing === m.id ? "editing" : ""}>
                  <td>
                    {m.portrait ? (
                      <img className="admin-icon" src={m.portrait} alt="" loading="lazy" decoding="async" />
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
                    <DeleteButton
                      id={m.id}
                      confirmingId={confirmingId}
                      onAskConfirm={() => setConfirmingId(m.id)}
                      onCancel={() => setConfirmingId(null)}
                      onConfirm={() => {
                        setConfirmingId(null);
                        del(m.id);
                      }}
                    />
                  </td>
                </tr>
                {editing === m.id && (
                  <tr className="admin-edit-row">
                    <td colSpan={5}>
                      {formEl}
                      <CompetencesEditor mercenaireId={m.id} />
                    </td>
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

// Or de la compagnie : une seule trésorerie, partagée par tous les joueurs
// (table partie_etat). Seul l administrateur peut la fixer ; les achats, ventes
// et déblocages des joueurs la modifient ensuite (voir le journal en Trésorerie).
function OrCompagnie() {
  const [or, setOr] = useState(null);
  const [saisie, setSaisie] = useState("");
  const [msg, setMsg] = useState("");
  useEffect(() => {
    supabase
      .from("partie_etat")
      .select("or_compagnie")
      .maybeSingle()
      .then(({ data }) => {
        if (data) {
          setOr(data.or_compagnie);
          setSaisie(String(data.or_compagnie));
        }
      });
  }, []);
  async function enregistrer(e) {
    e.preventDefault();
    const n = Number(saisie);
    if (String(saisie).trim() === "" || !Number.isInteger(n) || n < 0 || n > 100000000) {
      setMsg("Saisissez un entier de 0 à 100 000 000.");
      return;
    }
    const { data, error } = await supabase.rpc("partie_or_definir", { p_montant: n });
    if (error) setMsg(error.message);
    else {
      setOr(data);
      setMsg("Or de la compagnie enregistré.");
    }
  }
  if (or === null) return null;
  return (
    <form className="admin-form" onSubmit={enregistrer} noValidate>
      <h3>Or de la compagnie</h3>
      <p>
        Trésorerie unique, partagée par tous les joueurs (actuellement {or} Po).
        Les achats, ventes et déblocages des joueurs la modifient ensuite.
      </p>
      <div className="admin-ingredient-form">
        <input
          type="number"
          min="0"
          step="1"
          aria-label="Or de la compagnie"
          value={saisie}
          onChange={(e) => setSaisie(e.target.value)}
        />
        <button className="text-button" type="submit">
          Enregistrer l’or
        </button>
      </div>
      {msg && <p className="admin-error">{msg}</p>}
    </form>
  );
}

function ArsenalSection() {
  const inventaires = useTable("inventaire", { order: "id" });
  const lignes = useTable("ligne_inventaire", { order: "id" });
  const catalogue = useTable("objet_catalogue", { order: "nom" });
  const categories = useTable("categorie", { order: "nom" });
  const [objetId, setObjetId] = useState("");
  const [quantite, setQuantite] = useState("");
  const [msg, setMsg] = useState("");
  const [confirmingId, setConfirmingId] = useState(null);
  // "" = onglet Général (toutes les catégories) ; sinon id de la catégorie
  // (racine ou sous-catégorie) dont l'onglet est actif.
  const [tabCategorie, setTabCategorie] = useState("");
  // Catégorie choisie dans « Définir la quantité d'un objet » pour réduire
  // la liste des objets proposés.
  const [formCategorie, setFormCategorie] = useState("");

  if (inventaires.error || lignes.error || catalogue.error || categories.error)
    return (
      <p className="admin-error">
        {inventaires.error || lignes.error || catalogue.error || categories.error}
      </p>
    );
  if (!inventaires.rows || !lignes.rows || !catalogue.rows || !categories.rows)
    return <p>Chargement…</p>;

  const arsenal = inventaires.rows.find((i) => i.type === "arsenal");
  if (!arsenal) return <p>Aucun arsenal trouvé.</p>;

  const stock = lignes.rows.filter((l) => l.inventaire_id === arsenal.id);

  function objet(id) {
    return catalogue.rows.find((o) => o.id === id);
  }
  function nomObjet(id) {
    return objet(id)?.nom || "?";
  }
  function nomCategorie(id) {
    return categories.rows.find((c) => c.id === id)?.nom || "—";
  }
  const childrenOf = (parentId) =>
    categories.rows.filter((c) => (c.parent_id || null) === parentId);
  // Une catégorie et toutes ses sous-catégories (récursivement).
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
  // Racine (catégorie sans parent) d'une catégorie donnée.
  function rootOf(id) {
    let current = categories.rows.find((c) => c.id === id);
    while (current?.parent_id)
      current = categories.rows.find((c) => c.id === current.parent_id);
    return current;
  }
  function categoryTreeOptions(parentId, depth) {
    return childrenOf(parentId).flatMap((c) => [
      <option key={c.id} value={c.id}>
        {"— ".repeat(depth)}
        {c.nom}
      </option>,
      ...categoryTreeOptions(c.id, depth + 1),
    ]);
  }
  function inCategory(objetIdValue, categorieId) {
    if (!categorieId) return true;
    const o = objet(objetIdValue);
    return !!o && categoryAndDescendantIds(categorieId).has(o.categorie_id);
  }
  function selectTab(id) {
    setTabCategorie(id);
    setFormCategorie(id);
    setObjetId("");
  }

  const activeRoot = tabCategorie ? rootOf(tabCategorie) : null;
  const rootTabs = childrenOf(null);
  const subTabs = activeRoot ? childrenOf(activeRoot.id) : [];
  const visibleStock = stock.filter((l) => inCategory(l.objet_id, tabCategorie));
  const formObjets = catalogue.rows.filter((o) =>
    formCategorie ? categoryAndDescendantIds(formCategorie).has(o.categorie_id) : true,
  );

  // Ajoute (sign = 1) ou retire (sign = -1) la quantité saisie à celle déjà
  // en stock ; la quantité ne descend jamais sous zéro.
  async function adjust(sign) {
    const delta = Math.floor(Number(quantite));
    if (!objetId || !(delta > 0)) {
      setMsg("Choisissez un objet et une quantité supérieure à zéro.");
      return;
    }
    const existing = stock.find((l) => l.objet_id === objetId);
    if (sign < 0 && !existing) {
      setMsg("Cet objet n’est pas dans l’arsenal : rien à retirer.");
      return;
    }
    const current = existing?.quantite ?? 0;
    const next = Math.max(0, current + sign * delta);
    const err = existing
      ? await lignes.update(existing.id, { quantite: next })
      : await lignes.insert({ inventaire_id: arsenal.id, objet_id: objetId, quantite: next });
    if (err) setMsg(err);
    else {
      setMsg("");
      setQuantite("");
    }
  }
  function submit(e) {
    e.preventDefault();
    adjust(1);
  }
  async function del(id) {
    const err = await lignes.remove(id);
    if (err) setMsg(err);
  }

  return (
    <div>
      <OrCompagnie />
      <nav className="admin-subtabs" aria-label="Catégories de l’arsenal">
        <button
          type="button"
          className={tabCategorie === "" ? "active" : ""}
          onClick={() => selectTab("")}
        >
          Général ({stock.length})
        </button>
        {rootTabs.map((c) => (
          <button
            key={c.id}
            type="button"
            className={activeRoot?.id === c.id ? "active" : ""}
            onClick={() => selectTab(c.id)}
          >
            {c.nom} ({stock.filter((l) => inCategory(l.objet_id, c.id)).length})
          </button>
        ))}
      </nav>
      {subTabs.length > 0 && (
        <nav className="admin-subtabs admin-subtabs-level2" aria-label={`Sous-catégories de ${activeRoot.nom}`}>
          <button
            type="button"
            className={tabCategorie === activeRoot.id ? "active" : ""}
            onClick={() => selectTab(activeRoot.id)}
          >
            Tout {activeRoot.nom}
          </button>
          {subTabs.map((c) => (
            <button
              key={c.id}
              type="button"
              className={tabCategorie === c.id ? "active" : ""}
              onClick={() => selectTab(c.id)}
            >
              {c.nom}
            </button>
          ))}
        </nav>
      )}
      {tabCategorie && !visibleStock.length && (
        <p className="muted">Aucun objet de cette catégorie dans l’arsenal.</p>
      )}
      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Objet</th>
              {!tabCategorie && <th>Catégorie</th>}
              <th>Quantité</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {visibleStock.map((l) => (
              <tr key={l.id}>
                <td>{nomObjet(l.objet_id)}</td>
                {!tabCategorie && (
                  <td>{nomCategorie(rootOf(objet(l.objet_id)?.categorie_id)?.id)}</td>
                )}
                <td>{l.quantite}</td>
                <td className="admin-row-actions">
                  <DeleteButton
                    id={l.id}
                    label="Supprimer"
                    confirmingId={confirmingId}
                    onAskConfirm={() => setConfirmingId(l.id)}
                    onCancel={() => setConfirmingId(null)}
                    onConfirm={() => {
                      setConfirmingId(null);
                      del(l.id);
                    }}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <form className="admin-form" onSubmit={submit}>
        <h3>Ajouter ou retirer une quantité</h3>
        <p>
          La quantité saisie s’ajoute à celle déjà en stock, ou s’en retranche
          (sans jamais descendre sous zéro).
        </p>
        <div className="admin-ingredient-form">
          <select
            aria-label="Catégorie"
            value={formCategorie}
            onChange={(e) => {
              setFormCategorie(e.target.value);
              setObjetId("");
            }}
          >
            <option value="">Toutes les catégories</option>
            {categoryTreeOptions(null, 0)}
          </select>
          <SearchableSelect
            value={objetId}
            onChange={setObjetId}
            options={formObjets.map((o) => ({ value: o.id, label: o.nom }))}
            emptyLabel="Objet…"
            ariaLabel="Objet"
          />
          <input
            type="number"
            min="1"
            step="1"
            placeholder="Quantité"
            value={quantite}
            onChange={(e) => setQuantite(e.target.value)}
          />
          <button className="text-button" type="submit">
            Ajouter
          </button>
          <button className="text-button" type="button" onClick={() => adjust(-1)}>
            Retirer
          </button>
        </div>
        {msg && <p className="admin-error">{msg}</p>}
      </form>
    </div>
  );
}

// Sauvegarde à la demande : toutes les tables de la partie et du catalogue,
// téléchargées dans un fichier JSON sur l'ordinateur de l'administrateur (aucun
// service externe). Une table illisible est notée dans le fichier sans
// interrompre les autres. Pas de restauration automatique : le fichier sert de
// filet de sécurité (l'offre gratuite de Supabase n'a pas de sauvegardes).
const TABLES_SAUVEGARDE = [
  "categorie",
  "classe",
  "objet_catalogue",
  "recette",
  "ingredient_recette",
  "mercenaire",
  "inventaire",
  "ligne_inventaire",
  "recrutement",
  "mercenaire_competence",
  "mercenaire_equipement",
  "invitation",
  "profil",
];
async function telechargerSauvegarde() {
  const contenu = { date: new Date().toISOString(), tables: {}, erreurs: {} };
  for (const table of TABLES_SAUVEGARDE) {
    const { data, error } = await supabase.from(table).select("*").limit(10000);
    if (error) contenu.erreurs[table] = error.message;
    else contenu.tables[table] = data;
  }
  const lignes = Object.values(contenu.tables).reduce((a, t) => a + t.length, 0);
  const blob = new Blob([JSON.stringify(contenu, null, 1)], { type: "application/json" });
  const lien = document.createElement("a");
  lien.href = URL.createObjectURL(blob);
  lien.download = `forteresse-sauvegarde-${contenu.date.slice(0, 10)}.json`;
  document.body.appendChild(lien);
  lien.click();
  lien.remove();
  setTimeout(() => URL.revokeObjectURL(lien.href), 10000);
  return { lignes, tables: Object.keys(contenu.tables).length, erreurs: Object.keys(contenu.erreurs) };
}

// Code d'invitation : 8 caractères sans ambiguïté (ni 0/O ni 1/I), tirés au
// hasard par le navigateur ; affiché XXXX-XXXX mais stocké sans tiret.
const ALPHABET_INVITATION = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
function genererCodeInvitation() {
  const tirage = crypto.getRandomValues(new Uint32Array(8));
  return Array.from(tirage, (n) => ALPHABET_INVITATION[n % ALPHABET_INVITATION.length]).join("");
}
const formaterCode = (code) => `${code.slice(0, 4)}-${code.slice(4)}`;
function messageInvitation(code, nomSession) {
  return `Rejoins la partie ${nomSession ? `« ${nomSession} » ` : ""}de la forteresse : ${location.origin}/#inscription — code d’invitation : ${formaterCode(code)}. (Si tu as déjà un compte : connecte-toi, puis « Rejoindre une session » en haut de l’écran.)`;
}

// Suivi du maintien actif de la base (voir api/keepalive.js) : heure du dernier
// appel de chacune des deux tâches planifiées (Vercel, GitHub). Alerte s'il n'y
// a plus eu d'appel planifié depuis plus de 2 jours. N'affiche rien si la
// table de suivi est absente ou illisible.
function EtatMaintien() {
  const [rows, setRows] = useState(null);
  useEffect(() => {
    let annule = false;
    supabase
      .from("maintien")
      .select("*")
      .then(({ data, error }) => {
        if (!annule && !error) setRows(data);
      });
    return () => {
      annule = true;
    };
  }, []);
  if (!rows) return null;
  const dernier = (source) => rows.find((r) => r.source === source)?.dernier;
  const depuis = (iso) => {
    if (!iso) return "pas encore reçu";
    const min = Math.max(1, Math.round((Date.now() - new Date(iso).getTime()) / 60000));
    if (min < 60) return `il y a ${min} min`;
    const h = Math.round(min / 60);
    return h < 48 ? `il y a ${h} h` : `il y a ${Math.round(h / 24)} j`;
  };
  const planifies = ["vercel", "github"].map(dernier).filter(Boolean);
  const recent = planifies.length ? Math.max(...planifies.map((d) => new Date(d).getTime())) : null;
  const alerte = recent !== null && Date.now() - recent > 48 * 3600 * 1000;
  return (
    <p className={alerte ? "admin-etat admin-etat-alerte" : "admin-etat"} role="status">
      Maintien actif de la base — Vercel : {depuis(dernier("vercel"))} · GitHub :{" "}
      {depuis(dernier("github"))}
      {alerte && " — ⚠ aucun appel planifié depuis plus de 2 jours"}
      {recent === null && " (en attente du premier appel planifié, chaque matin)"}
    </p>
  );
}

function emptyQuete() {
  return { nom: "", description: "", veterance_requise: "", instances_requises: "1", recompense_or: "", icone: "" };
}
const QUETE_SLOTS = [0, 1, 2, 3, 4];

// Fiche d'une quête : titre, description, vétérance moyenne requise (affichée
// en jeu avec la pastille laurier déjà utilisée pour les mercenaires),
// icône de type (à venir, laissée vide tant que Bruno n'en a pas), jusqu'à 5
// récompenses en objets (chacune un objet du catalogue + une quantité) et une
// récompense en or. Les récompenses sont remplacées en bloc à chaque
// enregistrement (supprimées puis réinsérées) plutôt que diffées, comme la
// recette d'un objet du catalogue.
function QuetesSection() {
  const quetes = useTable("quete", { order: "nom" });
  // Avancement propre à la session choisie (vide dans le contexte « base de départ »).
  const etats = useTable("quete_etat", { order: "quete_id", key: "quete_id" });
  const recompenses = useTable("quete_recompense", { order: "position" });
  const catalogue = useTable("objet_catalogue", { order: "nom" });
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(emptyQuete());
  const [iconFile, setIconFile] = useState(null);
  // 5 emplacements (position 1 à 5) : null si vide, sinon { objet_id, quantite }.
  const [slots, setSlots] = useState([null, null, null, null, null]);
  const [uploading, setUploading] = useState(false);
  const [msg, setMsg] = useState("");
  const [confirmingId, setConfirmingId] = useState(null);

  if (quetes.error || recompenses.error || catalogue.error || etats.error)
    return <p className="admin-error">{quetes.error || recompenses.error || catalogue.error || etats.error}</p>;
  if (!quetes.rows || !recompenses.rows || !catalogue.rows || !etats.rows) return <p>Chargement…</p>;
  const etatDe = (id) => etats.rows.find((e) => e.quete_id === id);

  function nomObjet(id) {
    return catalogue.rows.find((o) => o.id === id)?.nom || "?";
  }
  function recompensesDe(queteId) {
    return recompenses.rows
      .filter((r) => r.quete_id === queteId)
      .sort((a, b) => a.position - b.position);
  }
  function startEdit(q) {
    setEditing(q.id);
    setForm({
      nom: q.nom,
      description: q.description || "",
      veterance_requise: q.veterance_requise ?? "",
      instances_requises: q.instances_requises ?? 1,
      recompense_or: q.recompense_or ?? "",
      icone: q.icone || "",
    });
    setIconFile(null);
    const next = [null, null, null, null, null];
    recompensesDe(q.id).forEach((r) => {
      next[r.position - 1] = { objet_id: r.objet_id, quantite: r.quantite };
    });
    setSlots(next);
    setMsg("");
  }
  function cancel() {
    setEditing(null);
    setForm(emptyQuete());
    setIconFile(null);
    setSlots([null, null, null, null, null]);
    setMsg("");
  }
  function setSlot(index, patch) {
    setSlots((prev) =>
      prev.map((s, i) => (i === index ? { objet_id: "", quantite: 1, ...s, ...patch } : s)),
    );
  }
  function clearSlot(index) {
    setSlots((prev) => prev.map((s, i) => (i === index ? null : s)));
  }
  async function submit(e) {
    e.preventDefault();
    if (!form.nom.trim()) {
      setMsg("Le titre est obligatoire.");
      return;
    }
    let icone = form.icone || null;
    if (iconFile) {
      setUploading(true);
      const result = await uploadImage("catalogue-icones", iconFile, form.nom);
      setUploading(false);
      if (result.error) {
        setMsg(result.error);
        return;
      }
      icone = result.url;
    }
    const values = {
      nom: form.nom,
      description: form.description || "",
      veterance_requise: toIntOrNull(form.veterance_requise) ?? 0,
      instances_requises: Math.min(99, Math.max(1, toIntOrNull(form.instances_requises) ?? 1)),
      recompense_or: toIntOrNull(form.recompense_or) ?? 0,
      icone,
    };
    let queteId = editing;
    if (editing) {
      const { error } = await supabase.from("quete").update(values).eq("id", editing);
      if (error) {
        setMsg(error.message);
        return;
      }
    } else {
      const { data, error } = await supabase.from("quete").insert(values).select("id").single();
      if (error) {
        setMsg(error.message);
        return;
      }
      queteId = data.id;
    }
    const { error: delErr } = await supabase.from("quete_recompense").delete().eq("quete_id", queteId);
    if (delErr) {
      setMsg(delErr.message);
      return;
    }
    const lignes = slots
      .map((s, i) =>
        s && s.objet_id
          ? {
              quete_id: queteId,
              position: i + 1,
              objet_id: s.objet_id,
              quantite: Math.max(1, Math.floor(Number(s.quantite) || 1)),
            }
          : null,
      )
      .filter(Boolean);
    if (lignes.length) {
      const { error: insErr } = await supabase.from("quete_recompense").insert(lignes);
      if (insErr) {
        setMsg(insErr.message);
        return;
      }
    }
    await quetes.reload();
    await recompenses.reload();
    cancel();
  }
  async function del(id) {
    const err = await quetes.remove(id);
    if (err) setMsg(err);
  }
  async function remettreDisponible(id) {
    const err = await etats.remove(id);
    if (err) setMsg(err);
  }

  const formEl = (
    <form className="admin-form" onSubmit={submit}>
      <h3>{editing ? "Modifier la quête" : "Ajouter une quête"}</h3>
      <div className="admin-form-grid">
        <div className="field">
          <label htmlFor="quete-nom">Titre</label>
          <div className="input-wrap">
            <input
              id="quete-nom"
              value={form.nom}
              onChange={(e) => setForm({ ...form, nom: e.target.value })}
              required
            />
          </div>
        </div>
        <div className="field">
          <label htmlFor="quete-veterance">Vétérance moyenne requise</label>
          <div className="input-wrap">
            <input
              id="quete-veterance"
              type="number"
              min="0"
              value={form.veterance_requise}
              onChange={(e) => setForm({ ...form, veterance_requise: e.target.value })}
            />
          </div>
        </div>
        <div className="field">
          <label htmlFor="quete-instances">Instances requises</label>
          <div className="input-wrap">
            <input
              id="quete-instances"
              type="number"
              min="1"
              max="99"
              value={form.instances_requises}
              onChange={(e) => setForm({ ...form, instances_requises: e.target.value })}
            />
          </div>
        </div>
        <div className="field">
          <label htmlFor="quete-or">Récompense en or (Po)</label>
          <div className="input-wrap">
            <input
              id="quete-or"
              type="number"
              min="0"
              value={form.recompense_or}
              onChange={(e) => setForm({ ...form, recompense_or: e.target.value })}
            />
          </div>
        </div>
      </div>
      <div className="field">
        <label htmlFor="quete-desc">Description</label>
        <textarea
          id="quete-desc"
          rows={3}
          value={form.description}
          onChange={(e) => setForm({ ...form, description: e.target.value })}
        />
      </div>
      <div className="field">
        <label htmlFor="quete-icone">Icône de type (à gauche de la fiche, facultative)</label>
        <div className="admin-icon-picker">
          {(iconFile || form.icone) && (
            <img className="admin-icon" src={iconFile ? URL.createObjectURL(iconFile) : form.icone} alt="" />
          )}
          <input
            id="quete-icone"
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
      <div className="admin-recette-block">
        <p className="eyebrow admin-section-label">
          Récompenses en objets (jusqu’à 5, cliquables par les joueurs en jeu)
        </p>
        {QUETE_SLOTS.map((i) => (
          <div className="admin-ingredient-form" key={i}>
            <SearchableSelect
              value={slots[i]?.objet_id || ""}
              onChange={(v) => (v ? setSlot(i, { objet_id: v }) : clearSlot(i))}
              options={catalogue.rows.map((o) => ({ value: o.id, label: o.nom }))}
              emptyLabel={`— Emplacement ${i + 1} vide —`}
              ariaLabel={`Objet, emplacement ${i + 1}`}
            />
            {slots[i] && (
              <>
                <input
                  type="number"
                  min="1"
                  value={slots[i].quantite}
                  onChange={(e) => setSlot(i, { quantite: e.target.value })}
                  aria-label={`Quantité, emplacement ${i + 1}`}
                />
                <button type="button" className="text-button" onClick={() => clearSlot(i)}>
                  Vider
                </button>
              </>
            )}
          </div>
        ))}
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
              <th>Icône</th>
              <th>Titre</th>
              <th>Vétérance</th>
              <th>Instances</th>
              <th>Or</th>
              <th>Récompenses</th>
              <th>État</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {quetes.rows.map((q) => (
              <Fragment key={q.id}>
                <tr className={editing === q.id ? "editing" : ""}>
                  <td>
                    {q.icone ? (
                      <img className="admin-icon" src={q.icone} alt="" loading="lazy" decoding="async" />
                    ) : (
                      "—"
                    )}
                  </td>
                  <td>{q.nom}</td>
                  <td>{q.veterance_requise}</td>
                  <td>{q.instances_requises ?? 1}</td>
                  <td>{q.recompense_or}</td>
                  <td>
                    {recompensesDe(q.id).length
                      ? recompensesDe(q.id)
                          .map((r) => `${nomObjet(r.objet_id)} ×${r.quantite}`)
                          .join(", ")
                      : "—"}
                  </td>
                  <td>
                    {etatDe(q.id)?.terminee_le
                      ? "Terminée"
                      : etatDe(q.id)?.en_cours
                        ? `En cours (reste ${etatDe(q.id).instances_restantes ?? q.instances_requises ?? 1})`
                        : "Disponible"}
                  </td>
                  <td className="admin-row-actions">
                    <button type="button" className="text-button" onClick={() => startEdit(q)}>
                      Modifier
                    </button>
                    {etatDe(q.id)?.terminee_le && (
                      <button type="button" className="text-button" onClick={() => remettreDisponible(q.id)}>
                        Remettre disponible
                      </button>
                    )}
                    <DeleteButton
                      id={q.id}
                      confirmingId={confirmingId}
                      onAskConfirm={() => setConfirmingId(q.id)}
                      onCancel={() => setConfirmingId(null)}
                      onConfirm={() => {
                        setConfirmingId(null);
                        del(q.id);
                      }}
                    />
                  </td>
                </tr>
                {editing === q.id && (
                  <tr className="admin-edit-row">
                    <td colSpan={8}>{formEl}</td>
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

// Inscription sur invitation : l'administrateur crée un code par joueur, le lui
// transmet, et le joueur le saisit sur « Créer un compte ». Chaque code ne
// sert qu'une fois ; le contrôle réel est dans la base (déclencheur sur
// auth.users, voir la migration invitations).
function InvitationsSection({ sess, sessionInitiale }) {
  const { rows, error, insert, remove } = useTable("invitation", { order: "cree_le", key: "code" });
  const [sessionId, setSessionId] = useState(sessionInitiale || sess.courante?.id || "");
  useEffect(() => {
    if (sessionInitiale) setSessionId(sessionInitiale);
  }, [sessionInitiale]);
  const nomSession = (id) => sess.sessions.find((x) => x.id === id)?.nom || "";
  const [note, setNote] = useState("");
  const [msg, setMsg] = useState("");
  const [dernier, setDernier] = useState(null);
  const [copie, setCopie] = useState("");
  const [confirmingId, setConfirmingId] = useState(null);

  async function copier(code, idSession) {
    try {
      await navigator.clipboard.writeText(messageInvitation(code, nomSession(idSession)));
      setCopie(code);
      setTimeout(() => setCopie(""), 2500);
    } catch {
      setMsg("Copie impossible : sélectionnez le message et copiez-le à la main.");
    }
  }
  async function creer(e) {
    e.preventDefault();
    setMsg("");
    if (!sessionId) {
      setMsg("Choisissez la session que ce joueur rejoindra.");
      return;
    }
    const code = genererCodeInvitation();
    const err = await insert({ code, note: note.trim() || null, session_id: sessionId });
    if (err) {
      setMsg(err);
      return;
    }
    setDernier({ code, session: sessionId });
    setNote("");
  }
  async function supprimer(code) {
    const err = await remove(code);
    if (err) setMsg(err);
  }

  if (error) return <p className="admin-error">{error}</p>;
  if (!rows) return <p>Chargement…</p>;
  const triees = [...rows].sort((a, b) => b.cree_le.localeCompare(a.cree_le));
  const formatDate = (d) => new Date(d).toLocaleDateString("fr-FR");

  return (
    <div>
      <p>
        Personne ne peut créer de compte sans code d’invitation. Un code est lié à une
        session : créez-en un par joueur et transmettez-le lui. Il le saisit sur la page
        « Créer un compte » (nouveau joueur) ou dans « Rejoindre une session » (joueur qui a
        déjà un compte). Chaque code ne sert qu’une fois.
      </p>
      <form className="admin-form" onSubmit={creer}>
        <h3>Nouvelle invitation</h3>
        <div className="admin-form-grid">
          <div className="field">
            <label htmlFor="inv-session">Session à rejoindre</label>
            <div className="input-wrap">
              <select id="inv-session" value={sessionId} onChange={(e) => setSessionId(e.target.value)}>
                <option value="">— choisir —</option>
                {sess.sessions.map((x) => (
                  <option key={x.id} value={x.id}>
                    {x.nom}
                  </option>
                ))}
              </select>
            </div>
          </div>
          <div className="field">
            <label htmlFor="inv-note">Pour qui ? (facultatif, pour vous retrouver)</label>
            <div className="input-wrap">
              <input
                id="inv-note"
                value={note}
                maxLength={60}
                onChange={(e) => setNote(e.target.value)}
              />
            </div>
          </div>
        </div>
        {msg && <p className="admin-error">{msg}</p>}
        <div className="admin-form-actions">
          <button className="primary" type="submit">
            Créer une invitation
          </button>
        </div>
      </form>
      {dernier && (
        <div className="undo-banner" role="status">
          <p>
            Invitation créée pour « {nomSession(dernier.session)} » : <strong>{formaterCode(dernier.code)}</strong>
          </p>
          <p>{messageInvitation(dernier.code, nomSession(dernier.session))}</p>
          <button className="text-button" type="button" onClick={() => copier(dernier.code, dernier.session)}>
            {copie === dernier.code ? "Message copié ✓" : "Copier le message"}
          </button>
        </div>
      )}
      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Code</th>
              <th>Session</th>
              <th>Pour</th>
              <th>Créée le</th>
              <th>État</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {triees.map((r) => (
              <tr key={r.code}>
                <td>
                  <strong>{formaterCode(r.code)}</strong>
                </td>
                <td>{nomSession(r.session_id) || "—"}</td>
                <td>{r.note || "—"}</td>
                <td>{formatDate(r.cree_le)}</td>
                <td>{r.utilise_par || r.utilise_le ? `Utilisée le ${formatDate(r.utilise_le)}` : "Disponible"}</td>
                <td className="admin-row-actions">
                  {!r.utilise_le && (
                    <>
                      <button type="button" className="text-button" onClick={() => copier(r.code, r.session_id)}>
                        {copie === r.code ? "Copié ✓" : "Copier le message"}
                      </button>
                      <DeleteButton
                        id={r.code}
                        label="Révoquer"
                        confirmingId={confirmingId}
                        onAskConfirm={() => setConfirmingId(r.code)}
                        onCancel={() => setConfirmingId(null)}
                        onConfirm={() => {
                          setConfirmingId(null);
                          supprimer(r.code);
                        }}
                      />
                    </>
                  )}
                </td>
              </tr>
            ))}
            {!triees.length && (
              <tr>
                <td colSpan={6}>Aucune invitation pour l’instant.</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Sessions (parties indépendantes, voir docs/SESSIONS.md)
// ---------------------------------------------------------------------------

// Ce que le MJ consulte : la base de départ ou une session. Le catalogue (objets, catégories,
// classes, mercenaires, quêtes) est commun à toutes les sessions et ne dépend pas de ce choix ;
// il détermine seulement l'onglet Arsenal (or et arsenal de départ, ou ceux de la session) et
// l'état de jeu (vétérance, avancement des quêtes) que vous modifiez.
function ContexteAdmin({ sess }) {
  const [erreur, setErreur] = useState("");
  const valeur = sess.base ? "__base" : sess.courante?.id || "";
  let texte = "Choisissez ce que vous modifiez : la base de départ ou une session.";
  let classe = "admin-contexte";
  if (sess.base) {
    classe += " admin-contexte-base";
    texte =
      "Base de départ : l’or, l’arsenal et le budget donnés à chaque session à son lancement. Le catalogue (objets, catégories, classes, mercenaires, quêtes) est commun à toutes les sessions, quel que soit ce choix.";
  } else if (sess.courante?.lancee_le) {
    classe += " admin-contexte-session";
    texte = `Session « ${sess.courante.nom} » : l’or, l’arsenal, la vétérance et les quêtes que vous modifiez ne concernent que cette session. Le catalogue est commun à toutes les sessions.`;
  } else if (sess.courante) {
    classe += " admin-contexte-attente";
    texte = `La session « ${sess.courante.nom} » n’est pas encore lancée : elle prendra l’or, l’arsenal et le budget de la base de départ à son lancement. Le catalogue est commun à toutes les sessions.`;
  }
  return (
    <div className={classe}>
      <label>
        <strong>Vous consultez :</strong>{" "}
        <select
          value={valeur}
          onChange={async (e) => {
            setErreur("");
            const v = e.target.value;
            if (!v) return;
            const r = await sess.choisir(v === "__base" ? null : v);
            if (r.error) setErreur(r.error);
          }}
        >
          {!valeur && <option value="">— choisir —</option>}
          <option value="__base">Base de départ</option>
          {sess.sessions.map((x) => (
            <option key={x.id} value={x.id}>
              Session : {x.nom}
              {x.lancee_le ? "" : " (pas encore lancée)"}
            </option>
          ))}
        </select>
      </label>
      <p>{texte}</p>
      {erreur && <p className="admin-error">{erreur}</p>}
    </div>
  );
}

// Onglet Sessions : créer, ouvrir, renommer, inviter, remettre à zéro.
function SessionsSection({ sess, onInviter }) {
  const [nom, setNom] = useState("");
  const [msg, setMsg] = useState("");
  const [membres, setMembres] = useState({});
  const [renommer, setRenommer] = useState(null); // { id, nom }
  const [zero, setZero] = useState(null); // { id, nom, saisie }
  const [occupe, setOccupe] = useState(false);

  async function chargerMembres() {
    const { data } = await supabase.from("session_membre").select("session_id");
    const c = {};
    (data || []).forEach((m) => {
      c[m.session_id] = (c[m.session_id] || 0) + 1;
    });
    setMembres(c);
  }
  useEffect(() => {
    chargerMembres();
  }, [sess.sessions.length]);

  async function creer(e) {
    e.preventDefault();
    if (!nom.trim() || occupe) return;
    setOccupe(true);
    setMsg("");
    const { error } = await supabase.rpc("session_creer", { p_nom: nom.trim() });
    setOccupe(false);
    if (error) {
      setMsg(error.message);
      return;
    }
    setNom("");
    setMsg(`Session « ${nom.trim()} » créée. Elle sera lancée par votre premier « +1 Instance » dans cette session.`);
    await sess.recharger();
  }
  async function enregistrerNom(e) {
    e.preventDefault();
    if (!renommer?.nom.trim()) return;
    const { error } = await supabase.rpc("session_renommer", { p_session: renommer.id, p_nom: renommer.nom });
    if (error) {
      setMsg(error.message);
      return;
    }
    setRenommer(null);
    await sess.recharger();
  }
  async function remettreAZero() {
    if (!zero || zero.saisie.trim().toLowerCase() !== zero.nom.trim().toLowerCase()) return;
    setOccupe(true);
    const { error } = await supabase.rpc("session_reinitialiser", { p_session: zero.id });
    setOccupe(false);
    if (error) {
      setMsg(error.message);
      return;
    }
    setMsg(`La session « ${zero.nom} » est remise à zéro (sauvegarde automatique faite) : elle attend un nouveau lancement.`);
    setZero(null);
    if (sess.courante?.id === zero.id) location.reload();
    else await sess.recharger();
  }

  return (
    <div>
      <p>
        Chaque session est une partie indépendante (équipe, or, arsenal, dortoir, quêtes…). Une session
        neuve attend : votre premier <strong>« +1 Instance »</strong> dedans la lance en copiant la base de
        départ ; les joueurs jouent ensuite.
      </p>
      <form className="admin-form" onSubmit={creer}>
        <h3>Nouvelle session</h3>
        <div className="admin-ingredient-form">
          <input
            aria-label="Nom de la session"
            placeholder="Nom de la session (ex. Équipe du vendredi)"
            value={nom}
            maxLength={60}
            onChange={(e) => setNom(e.target.value)}
          />
          <button className="primary" type="submit" disabled={!nom.trim() || occupe}>
            Créer la session
          </button>
        </div>
        {msg && <p className="admin-error">{msg}</p>}
      </form>
      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Session</th>
              <th>État</th>
              <th>Joueurs</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {sess.sessions.map((x) => (
              <Fragment key={x.id}>
                <tr className={sess.courante?.id === x.id ? "editing" : ""}>
                  <td>
                    <strong>{x.nom}</strong>
                    {sess.courante?.id === x.id && " (session ouverte)"}
                  </td>
                  <td>{x.lancee_le ? `Lancée le ${new Date(x.lancee_le).toLocaleDateString("fr-FR")}` : "En attente du lancement"}</td>
                  <td>{membres[x.id] || 0}</td>
                  <td className="admin-row-actions">
                    <button type="button" className="text-button" onClick={() => sess.choisir(x.id)}>
                      Ouvrir
                    </button>
                    <a
                      className="text-button"
                      href="#forteresse"
                      onClick={async (e) => {
                        e.preventDefault();
                        await supabase.rpc("session_choisir", { p_session: x.id });
                        location.hash = "forteresse";
                        location.reload();
                      }}
                    >
                      Jouer / diriger
                    </a>
                    <button type="button" className="text-button" onClick={() => setRenommer({ id: x.id, nom: x.nom })}>
                      Renommer
                    </button>
                    <button type="button" className="text-button" onClick={() => onInviter(x.id)}>
                      Inviter
                    </button>
                    <button
                      type="button"
                      className="text-button text-button-danger"
                      onClick={() => setZero({ id: x.id, nom: x.nom, saisie: "" })}
                    >
                      Remettre à zéro
                    </button>
                  </td>
                </tr>
                {renommer?.id === x.id && (
                  <tr className="admin-edit-row">
                    <td colSpan={4}>
                      <form className="admin-ingredient-form" onSubmit={enregistrerNom}>
                        <input
                          aria-label="Nouveau nom"
                          value={renommer.nom}
                          maxLength={60}
                          onChange={(e) => setRenommer({ ...renommer, nom: e.target.value })}
                        />
                        <button className="text-button" type="submit">
                          Enregistrer le nom
                        </button>
                        <button className="text-button" type="button" onClick={() => setRenommer(null)}>
                          Annuler
                        </button>
                      </form>
                    </td>
                  </tr>
                )}
                {zero?.id === x.id && (
                  <tr className="admin-edit-row">
                    <td colSpan={4}>
                      <div className="admin-zero">
                        <p>
                          <strong>Remise à zéro de « {x.nom} »</strong> : or, arsenal, recrutements, lits, quêtes,
                          fabrications et contenu de la session seront effacés ; la session redeviendra « en attente
                          du lancement » et reprendra la base au prochain « +1 Instance ». Une sauvegarde
                          automatique est faite juste avant. Pour confirmer, tapez le nom de la session :
                        </p>
                        <div className="admin-ingredient-form">
                          <input
                            aria-label="Nom de la session pour confirmer"
                            value={zero.saisie}
                            onChange={(e) => setZero({ ...zero, saisie: e.target.value })}
                          />
                          <button
                            className="text-button text-button-danger"
                            type="button"
                            disabled={occupe || zero.saisie.trim().toLowerCase() !== x.nom.trim().toLowerCase()}
                            onClick={remettreAZero}
                          >
                            Remettre à zéro
                          </button>
                          <button className="text-button" type="button" onClick={() => setZero(null)}>
                            Annuler
                          </button>
                        </div>
                      </div>
                    </td>
                  </tr>
                )}
              </Fragment>
            ))}
            {!sess.sessions.length && (
              <tr>
                <td colSpan={4}>Aucune session pour l’instant.</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// Arsenal de départ de la base : or et objets donnés à chaque session à son lancement.
function DepartBaseSection() {
  const departLignes = useTable("base_depart_ligne", { order: "objet_id", key: "objet_id" });
  const catalogue = useTable("objet_catalogue", { order: "nom" });
  const [or, setOr] = useState(null);
  const [saisieOr, setSaisieOr] = useState("");
  const [objetId, setObjetId] = useState("");
  const [quantite, setQuantite] = useState("");
  const [msg, setMsg] = useState("");
  const [confirmingId, setConfirmingId] = useState(null);
  useEffect(() => {
    supabase
      .from("base_depart")
      .select("or_compagnie")
      .maybeSingle()
      .then(({ data }) => {
        if (data) {
          setOr(data.or_compagnie);
          setSaisieOr(String(data.or_compagnie));
        }
      });
  }, []);
  async function enregistrerOr(e) {
    e.preventDefault();
    const n = Number(saisieOr);
    if (String(saisieOr).trim() === "" || !Number.isInteger(n) || n < 0 || n > 100000000) {
      setMsg("Saisissez un entier de 0 à 100 000 000.");
      return;
    }
    const { error } = await supabase.from("base_depart").update({ or_compagnie: n }).eq("id", true);
    if (error) setMsg(error.message);
    else {
      setOr(n);
      setMsg("Or de départ enregistré.");
    }
  }
  if (departLignes.error || catalogue.error)
    return <p className="admin-error">{departLignes.error || catalogue.error}</p>;
  if (!departLignes.rows || !catalogue.rows) return <p>Chargement…</p>;
  const nomObjet = (id) => catalogue.rows.find((o) => o.id === id)?.nom || "?";
  async function ajouter(e) {
    e.preventDefault();
    const n = Math.floor(Number(quantite));
    if (!objetId || !(n > 0)) {
      setMsg("Choisissez un objet et une quantité supérieure à zéro.");
      return;
    }
    const { error } = await supabase.from("base_depart_ligne").upsert({ objet_id: objetId, quantite: n }, { onConflict: "objet_id" });
    if (error) {
      setMsg(error.message);
      return;
    }
    await departLignes.reload();
    setMsg("");
    setObjetId("");
    setQuantite("");
  }
  return (
    <div>
      <p>
        Valeurs de départ de la <strong>base</strong> : chaque session les reçoit à son lancement (premier
        « +1 Instance »). Elles ne changent pas les sessions déjà lancées.
      </p>
      <form className="admin-form" onSubmit={enregistrerOr} noValidate>
        <h3>Or de départ</h3>
        <div className="admin-ingredient-form">
          <input
            type="number"
            min="0"
            step="1"
            aria-label="Or de départ"
            value={saisieOr}
            onChange={(e) => setSaisieOr(e.target.value)}
          />
          <button className="text-button" type="submit">
            Enregistrer l’or de départ
          </button>
        </div>
        {or !== null && <p className="muted">Valeur actuelle : {or} Po.</p>}
      </form>
      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Objet de départ</th>
              <th>Quantité</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {departLignes.rows.map((l) => (
              <tr key={l.objet_id}>
                <td>{nomObjet(l.objet_id)}</td>
                <td>{l.quantite}</td>
                <td className="admin-row-actions">
                  <DeleteButton
                    id={l.objet_id}
                    confirmingId={confirmingId}
                    onAskConfirm={() => setConfirmingId(l.objet_id)}
                    onCancel={() => setConfirmingId(null)}
                    onConfirm={async () => {
                      setConfirmingId(null);
                      const err = await departLignes.remove(l.objet_id);
                      if (err) setMsg(err);
                    }}
                  />
                </td>
              </tr>
            ))}
            {!departLignes.rows.length && (
              <tr>
                <td colSpan={3}>Aucun objet de départ : les sessions démarrent avec un arsenal vide.</td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      <form className="admin-form" onSubmit={ajouter}>
        <h3>Ajouter ou remplacer un objet de départ</h3>
        <div className="admin-ingredient-form">
          <SearchableSelect
            value={objetId}
            onChange={setObjetId}
            options={catalogue.rows.map((o) => ({ value: o.id, label: o.nom }))}
            emptyLabel="Objet…"
            ariaLabel="Objet"
          />
          <input
            type="number"
            min="1"
            step="1"
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

// undefined tant que le statut admin n'a pas ete verifie (evite un flash du
// panneau avant que la reponse serveur arrive), true/false ensuite. Reverifie
// a chaque changement de session (connexion/deconnexion).
function useIsAdmin(session) {
  const [isAdmin, setIsAdmin] = useState(undefined);
  useEffect(() => {
    if (!session) {
      setIsAdmin(undefined);
      return;
    }
    let cancelled = false;
    setIsAdmin(undefined);
    supabase.rpc("is_admin").then(({ data, error }) => {
      if (!cancelled) setIsAdmin(!error && !!data);
    });
    return () => {
      cancelled = true;
    };
  }, [session]);
  return isAdmin;
}

export function Admin({ onCraftItem = () => {} }) {
  const session = useSession();
  const isAdmin = useIsAdmin(session);
  const sess = useSessions(session?.user?.id, true);
  const [tab, setTab] = useState("sessions");
  const [sessionInvit, setSessionInvit] = useState("");
  const [sauvegardeMsg, setSauvegardeMsg] = useState("");
  const [sauvegardeEnCours, setSauvegardeEnCours] = useState(false);
  async function sauvegarder() {
    setSauvegardeEnCours(true);
    setSauvegardeMsg("");
    try {
      const r = await telechargerSauvegarde();
      setSauvegardeMsg(
        `Sauvegarde téléchargée : ${r.lignes} enregistrements, ${r.tables} tables${r.erreurs.length ? ` (illisibles : ${r.erreurs.join(", ")})` : ""}.`,
      );
    } catch (e) {
      setSauvegardeMsg("Sauvegarde impossible : " + (e.message || e));
    }
    setSauvegardeEnCours(false);
  }

  // Le catalogue est commun ; seul l'arsenal dépend du contexte (base, ou session déjà lancée).
  const arsenalIndisponible = !sess.base && !sess.courante?.lancee_le;
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
  if (isAdmin === undefined)
    return (
      <main className="admin-page">
        <p>Chargement…</p>
      </main>
    );
  if (!isAdmin)
    return (
      <main className="admin-page" style={{ backgroundImage: `url(${ASSETS.login})` }}>
        <div className="parchment admin-card">
          <p className="eyebrow">Administration</p>
          <h1>Accès réservé</h1>
          <p className="auth-intro">
            Le compte {session.user.email} n’a pas accès à cette page.
          </p>
          <button className="primary" type="button" onClick={() => supabase.auth.signOut()}>
            Se déconnecter
          </button>
          <a className="text-button" href="#forteresse">
            Retour au jeu
          </a>
        </div>
      </main>
    );

  return (
    <main className="admin-page admin-page-authed">
      <header className="admin-header">
        <h1>Administration — Forteresse</h1>
        <div className="admin-header-actions">
          <span>{session.user.email}</span>
          <button
            className="text-button"
            onClick={sauvegarder}
            disabled={sauvegardeEnCours}
            title="Télécharge un fichier avec toutes les données de la partie et du catalogue"
          >
            {sauvegardeEnCours ? "Sauvegarde…" : "Télécharger une sauvegarde"}
          </button>
          <button className="text-button" onClick={() => supabase.auth.signOut()}>
            Se déconnecter
          </button>
          <a className="text-button" href="#forteresse">
            Retour au jeu
          </a>
        </div>
      </header>
      <ContexteAdmin sess={sess} />
      <nav className="admin-tabs">
        <button className={tab === "sessions" ? "active" : ""} onClick={() => setTab("sessions")}>
          Sessions
        </button>
        <button className={tab === "catalogue" ? "active" : ""} onClick={() => setTab("catalogue")}>
          Catalogue
        </button>
        <button className={tab === "categories" ? "active" : ""} onClick={() => setTab("categories")}>
          Catégories
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
        <button className={tab === "quetes" ? "active" : ""} onClick={() => setTab("quetes")}>
          Quêtes
        </button>
        <button className={tab === "invitations" ? "active" : ""} onClick={() => setTab("invitations")}>
          Invitations
        </button>
      </nav>
      <EtatMaintien />
      {sauvegardeMsg && (
        <p className="admin-etat" role="status">
          {sauvegardeMsg}
        </p>
      )}
      <div className="admin-content parchment">
        {tab === "sessions" && (
          <SessionsSection
            sess={sess}
            onInviter={(id) => {
              setSessionInvit(id);
              setTab("invitations");
            }}
          />
        )}
        {tab !== "sessions" && tab !== "invitations" && !sess.pret && <p>Chargement…</p>}
        {tab === "arsenal" && sess.pret && arsenalIndisponible && (
          <p className="muted">
            L’arsenal se modifie dans la <strong>base de départ</strong> ou dans une session déjà
            lancée : choisissez-en une avec le menu « Vous consultez » en haut de la page.
          </p>
        )}
        {sess.pret && tab === "catalogue" && <CatalogueSection onCraftItem={onCraftItem} />}
        {sess.pret && tab === "categories" && (
          <NamedListSection
            table="categorie"
            singular="catégorie"
            blockedBy="des objets du catalogue"
            hierarchical
          />
        )}
        {sess.pret && tab === "classes" && (
          <NamedListSection table="classe" singular="classe" blockedBy="des mercenaires" />
        )}
        {sess.pret && tab === "mercenaires" && <MercenairesSection />}
        {sess.pret && !arsenalIndisponible && tab === "arsenal" && (sess.base ? <DepartBaseSection /> : <ArsenalSection />)}
        {sess.pret && tab === "quetes" && <QuetesSection />}
        {tab === "invitations" && <InvitationsSection sess={sess} sessionInitiale={sessionInvit} />}
      </div>
    </main>
  );
}
