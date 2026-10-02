import { Fragment, useEffect, useState } from "react";
import { supabase } from "./supabaseClient";
import { RichTextarea } from "./RichText.jsx";
import {
  CATEGORIES_CAPACITES,
  EMPLACEMENTS_ICONES,
  ETATS_JEU,
  SENS_CREATURE,
  SOUS_TYPES_CREATURE,
  TAILLES_CREATURE,
  TYPES_CREATURE,
  TYPES_DEGATS,
  creatureVide,
  entier,
} from "./creatures-data.js";

// Catalogue des créatures (administration, MJ seul). Une créature = identité, stats, défenses (listes de
// choix), description, cinq listes extensibles (capacités, actions, actions bonus, réactions, actions
// légendaires) et 12 emplacements d'icônes cliquables en jeu. Les capacités sont PARTAGÉES par titre :
// taper un titre déjà connu reprend son texte et son icône ; en corriger le texte met à jour toutes les
// créatures qui l'utilisent (y compris celles déjà en jeu).

const cle = (t) => (t || "").trim().toLowerCase();

function MultiChoix({ libelle, options, valeur, onChange }) {
  const bascule = (o) => onChange(valeur.includes(o) ? valeur.filter((v) => v !== o) : [...valeur, o]);
  return (
    <details className="creature-multi">
      <summary>
        {libelle}
        {valeur.length ? <strong> ({valeur.length})</strong> : null}
      </summary>
      <div className="creature-multi-liste">
        {options.map((o) => (
          <label key={o}>
            <input type="checkbox" checked={valeur.includes(o)} onChange={() => bascule(o)} /> {o}
          </label>
        ))}
      </div>
      {valeur.length > 0 && <p className="muted creature-multi-resume">{valeur.join(", ")}</p>}
    </details>
  );
}

function listesVides() {
  return Object.fromEntries(CATEGORIES_CAPACITES.map((c) => [c.id, []]));
}

export function CreaturesSection({ kit }) {
  const { uploadImage, DeleteButton } = kit;
  const [creatures, setCreatures] = useState(null);
  const [capacites, setCapacites] = useState([]);
  const [liens, setLiens] = useState([]);
  const [icones, setIcones] = useState([]);
  const [erreur, setErreur] = useState("");
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(creatureVide());
  const [listes, setListes] = useState(listesVides());
  const [slots, setSlots] = useState(Array(EMPLACEMENTS_ICONES).fill(""));
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);
  const [confirmingId, setConfirmingId] = useState(null);

  async function charger() {
    const [c, p, l, i] = await Promise.all([
      supabase.from("creature").select("*").order("nom"),
      supabase.from("capacite_creature").select("*").order("titre"),
      supabase.from("creature_capacite").select("*").order("position"),
      supabase.from("creature_icone").select("*").order("position"),
    ]);
    const err = c.error || p.error || l.error || i.error;
    if (err) {
      setErreur(err.message);
      return;
    }
    setErreur("");
    setCreatures(c.data);
    setCapacites(p.data);
    setLiens(l.data);
    setIcones(i.data);
  }
  useEffect(() => {
    charger();
  }, []);

  if (erreur) return <p className="admin-error">{erreur}</p>;
  if (!creatures) return <p>Chargement…</p>;

  const capParTitre = (t) => capacites.find((c) => cle(c.titre) === cle(t));
  const nbUtilisations = (capId) => new Set(liens.filter((l) => l.capacite_id === capId).map((l) => l.creature_id)).size;
  const titresConnus = [
    ...new Set([...capacites.map((c) => c.titre), ...Object.values(listes).flat().map((e) => e.titre.trim()).filter(Boolean)]),
  ].sort((a, b) => a.localeCompare(b, "fr"));

  function startEdit(c) {
    setEditing(c.id);
    setForm({
      nom: c.nom,
      type: c.type || "",
      sous_type: c.sous_type || "",
      taille: c.taille || "",
      sante_max: String(c.sante_max),
      energie_max: String(c.energie_max),
      vitesse: String(c.vitesse),
      fp: String(c.fp),
      puissance: String(c.puissance),
      velocite: String(c.velocite),
      mental: String(c.mental),
      vulnerabilites: c.vulnerabilites || [],
      resistances: c.resistances || [],
      immunites_degats: c.immunites_degats || [],
      immunites_etats: c.immunites_etats || [],
      sens: c.sens || [],
      description: c.description || "",
    });
    const next = listesVides();
    liens
      .filter((l) => l.creature_id === c.id)
      .sort((a, b) => a.position - b.position)
      .forEach((l) => {
        const cap = capacites.find((x) => x.id === l.capacite_id);
        if (cap) next[l.categorie]?.push({ titre: cap.titre, texte: cap.texte || "", icone: cap.icone || "", fichier: null, auto: cap.texte || "" });
      });
    setListes(next);
    const s = Array(EMPLACEMENTS_ICONES).fill("");
    icones
      .filter((i) => i.creature_id === c.id)
      .forEach((i) => {
        s[i.position] = capacites.find((x) => x.id === i.capacite_id)?.titre || "";
      });
    setSlots(s);
    setMsg("");
    window.scrollTo?.({ top: 0, behavior: "smooth" });
  }
  function cancel() {
    setEditing(null);
    setForm(creatureVide());
    setListes(listesVides());
    setSlots(Array(EMPLACEMENTS_ICONES).fill(""));
    setMsg("");
  }
  const champ = (k) => (e) => setForm({ ...form, [k]: e.target.value });

  function majEntree(cat, i, patch) {
    setListes((prev) => ({ ...prev, [cat]: prev[cat].map((e, k) => (k === i ? { ...e, ...patch } : e)) }));
  }
  function changerTitre(cat, i, titre) {
    const e = listes[cat][i];
    const connue = capParTitre(titre);
    const patch = { titre };
    // Titre déjà connu : son texte et son icône se remplissent tout seuls (sauf texte saisi à la main).
    if (connue && (!e.texte.trim() || e.texte === e.auto)) {
      patch.texte = connue.texte || "";
      patch.auto = connue.texte || "";
      patch.icone = connue.icone || "";
      patch.fichier = null;
    }
    majEntree(cat, i, patch);
  }

  async function submit(ev) {
    ev.preventDefault();
    if (!form.nom.trim()) {
      setMsg("Le nom est obligatoire.");
      return;
    }
    setBusy(true);
    setMsg("");
    try {
      const valeurs = {
        nom: form.nom.trim(),
        type: form.type || null,
        sous_type: form.sous_type.trim() || null,
        taille: form.taille || null,
        sante_max: entier(form.sante_max, 1, 9999),
        energie_max: entier(form.energie_max, 0, 999),
        vitesse: entier(form.vitesse, 0, 99),
        fp: entier(form.fp, 0, 99),
        puissance: entier(form.puissance, 0, 99),
        velocite: entier(form.velocite, 0, 99),
        mental: entier(form.mental, 0, 99),
        vulnerabilites: form.vulnerabilites,
        resistances: form.resistances,
        immunites_degats: form.immunites_degats,
        immunites_etats: form.immunites_etats,
        sens: form.sens,
        description: form.description || null,
      };
      let id = editing;
      if (id) {
        const { error } = await supabase.from("creature").update(valeurs).eq("id", id);
        if (error) throw error;
      } else {
        const { data, error } = await supabase.from("creature").insert(valeurs).select("id").single();
        if (error) throw error;
        id = data.id;
      }
      // Capacités partagées : créées ou mises à jour par titre.
      const idParTitre = new Map();
      for (const cat of CATEGORIES_CAPACITES) {
        for (const e of listes[cat.id]) {
          const titre = e.titre.trim();
          if (!titre || idParTitre.has(cle(titre))) continue;
          let icone = e.icone || null;
          if (e.fichier) {
            const r = await uploadImage("catalogue-icones", e.fichier, `creature-${titre}`);
            if (r.error) throw new Error(r.error);
            icone = r.url;
          }
          const connue = capParTitre(titre);
          if (connue) {
            if ((connue.texte || "") !== e.texte || (connue.icone || null) !== icone) {
              const { error } = await supabase.from("capacite_creature").update({ texte: e.texte, icone }).eq("id", connue.id);
              if (error) throw error;
            }
            idParTitre.set(cle(titre), connue.id);
          } else {
            const { data, error } = await supabase
              .from("capacite_creature")
              .insert({ titre, texte: e.texte, icone })
              .select("id")
              .single();
            if (error) throw error;
            idParTitre.set(cle(titre), data.id);
          }
        }
      }
      const { error: delCap } = await supabase.from("creature_capacite").delete().eq("creature_id", id);
      if (delCap) throw delCap;
      const lignes = [];
      for (const cat of CATEGORIES_CAPACITES) {
        let pos = 0;
        for (const e of listes[cat.id]) {
          const capId = idParTitre.get(cle(e.titre));
          if (capId) lignes.push({ creature_id: id, categorie: cat.id, position: pos++, capacite_id: capId });
        }
      }
      if (lignes.length) {
        const { error } = await supabase.from("creature_capacite").insert(lignes);
        if (error) throw error;
      }
      // Emplacements d'icônes cliquables.
      const { error: delIco } = await supabase.from("creature_icone").delete().eq("creature_id", id);
      if (delIco) throw delIco;
      const icoLignes = slots
        .map((t, position) => {
          const capId = idParTitre.get(cle(t)) || capParTitre(t)?.id;
          return t && capId ? { creature_id: id, position, capacite_id: capId } : null;
        })
        .filter(Boolean);
      if (icoLignes.length) {
        const { error } = await supabase.from("creature_icone").insert(icoLignes);
        if (error) throw error;
      }
      await charger();
      cancel();
    } catch (err) {
      setMsg(err.message || String(err));
    } finally {
      setBusy(false);
    }
  }

  async function supprimer(id) {
    const { error } = await supabase.from("creature").delete().eq("id", id);
    if (error) setMsg(error.message);
    else await charger();
  }

  const nombre = (k, libelle, min, max) => (
    <div className="field" key={k}>
      <label htmlFor={`cr-${k}`}>{libelle}</label>
      <div className="input-wrap">
        <input id={`cr-${k}`} type="number" min={min} max={max} value={form[k]} onChange={champ(k)} />
      </div>
    </div>
  );

  const formEl = (
    <form className="admin-form" onSubmit={submit}>
      <h3>{editing ? "Modifier la créature" : "Ajouter une créature"}</h3>
      <p className="eyebrow admin-section-label">Stats</p>
      <div className="admin-form-grid">
        <div className="field">
          <label htmlFor="cr-nom">Nom</label>
          <div className="input-wrap">
            <input id="cr-nom" value={form.nom} onChange={champ("nom")} required />
          </div>
        </div>
        <div className="field">
          <label htmlFor="cr-type">Type</label>
          <div className="input-wrap">
            <select id="cr-type" value={form.type} onChange={champ("type")}>
              <option value="">—</option>
              {TYPES_CREATURE.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </select>
          </div>
        </div>
        <div className="field">
          <label htmlFor="cr-soustype">Sous-type</label>
          <div className="input-wrap">
            <input id="cr-soustype" list="cr-soustypes" value={form.sous_type} onChange={champ("sous_type")} />
            <datalist id="cr-soustypes">
              {SOUS_TYPES_CREATURE.map((t) => (
                <option key={t} value={t} />
              ))}
            </datalist>
          </div>
        </div>
        <div className="field">
          <label htmlFor="cr-taille">Taille</label>
          <div className="input-wrap">
            <select id="cr-taille" value={form.taille} onChange={champ("taille")}>
              <option value="">—</option>
              {TAILLES_CREATURE.map(([code, nom]) => (
                <option key={code} value={code}>
                  {nom} ({code})
                </option>
              ))}
            </select>
          </div>
        </div>
        {nombre("sante_max", "Santé (max)", 1, 9999)}
        {nombre("energie_max", "Énergie (max)", 0, 999)}
        {nombre("vitesse", "Vitesse (en cases)", 0, 99)}
        {nombre("fp", "FP", 0, 99)}
        {nombre("puissance", "Puissance", 0, 99)}
        {nombre("velocite", "Vélocité", 0, 99)}
        {nombre("mental", "Mental", 0, 99)}
      </div>
      <div className="creature-multis">
        <MultiChoix libelle="Vulnérabilités" options={TYPES_DEGATS} valeur={form.vulnerabilites} onChange={(v) => setForm({ ...form, vulnerabilites: v })} />
        <MultiChoix libelle="Résistances" options={TYPES_DEGATS} valeur={form.resistances} onChange={(v) => setForm({ ...form, resistances: v })} />
        <MultiChoix libelle="Immunités aux dégâts" options={TYPES_DEGATS} valeur={form.immunites_degats} onChange={(v) => setForm({ ...form, immunites_degats: v })} />
        <MultiChoix libelle="Immunités aux états" options={ETATS_JEU.map((e) => e.nom)} valeur={form.immunites_etats} onChange={(v) => setForm({ ...form, immunites_etats: v })} />
        <MultiChoix libelle="Sens" options={SENS_CREATURE} valeur={form.sens} onChange={(v) => setForm({ ...form, sens: v })} />
      </div>

      <p className="eyebrow admin-section-label">Icônes cliquables en jeu (12 emplacements, chacun relié à une capacité par son titre)</p>
      <div className="creature-slots">
        {slots.map((titre, i) => {
          const cap = capParTitre(titre) || Object.values(listes).flat().find((e) => cle(e.titre) === cle(titre));
          const icone = cap?.icone;
          return (
            <div className="creature-slot" key={i}>
              <span className="creature-slot-icone" aria-hidden="true">
                {icone ? <img src={icone} alt="" /> : <small>{i + 1}</small>}
              </span>
              <select
                aria-label={`Icône ${i + 1}`}
                value={titre}
                onChange={(e) => setSlots((prev) => prev.map((s, k) => (k === i ? e.target.value : s)))}
              >
                <option value="">— vide —</option>
                {titresConnus.map((t) => (
                  <option key={t} value={t}>
                    {t}
                  </option>
                ))}
              </select>
            </div>
          );
        })}
      </div>

      {CATEGORIES_CAPACITES.map((cat) => (
        <div className="admin-recette-block" key={cat.id}>
          <p className="eyebrow admin-section-label">{cat.label}</p>
          {listes[cat.id].map((e, i) => {
            const connue = capParTitre(e.titre);
            return (
              <div className="creature-capacite" key={i}>
                <div className="creature-capacite-tete">
                  <input
                    list="cr-titres"
                    placeholder="Titre"
                    aria-label={`Titre, ${cat.singulier} ${i + 1}`}
                    value={e.titre}
                    onChange={(ev) => changerTitre(cat.id, i, ev.target.value)}
                  />
                  {(e.fichier || e.icone) && (
                    <img className="admin-icon" src={e.fichier ? URL.createObjectURL(e.fichier) : e.icone} alt="" />
                  )}
                  <input
                    type="file"
                    accept="image/*"
                    aria-label={`Icône, ${cat.singulier} ${i + 1}`}
                    onChange={(ev) => majEntree(cat.id, i, { fichier: ev.target.files[0] || null })}
                  />
                  {(e.fichier || e.icone) && (
                    <button type="button" className="text-button" onClick={() => majEntree(cat.id, i, { fichier: null, icone: "" })}>
                      Retirer l’icône
                    </button>
                  )}
                  <button
                    type="button"
                    className="text-button"
                    onClick={() => setListes((prev) => ({ ...prev, [cat.id]: prev[cat.id].filter((_, k) => k !== i) }))}
                  >
                    Supprimer
                  </button>
                </div>
                <RichTextarea
                  id={`cr-${cat.id}-${i}`}
                  rows={2}
                  grow
                  value={e.texte}
                  onChange={(v) => majEntree(cat.id, i, { texte: v })}
                />
                {connue && (
                  <p className="muted creature-capacite-note">
                    Texte et icône partagés avec {Math.max(0, nbUtilisations(connue.id) - (editing && liens.some((l) => l.creature_id === editing && l.capacite_id === connue.id) ? 1 : 0))} autre(s) créature(s) :
                    toute correction s’applique à toutes.
                  </p>
                )}
              </div>
            );
          })}
          <button
            type="button"
            className="text-button"
            onClick={() =>
              setListes((prev) => ({
                ...prev,
                [cat.id]: [...prev[cat.id], { titre: "", texte: "", icone: "", fichier: null, auto: "" }],
              }))
            }
          >
            + Ajouter une {cat.singulier}
          </button>
        </div>
      ))}
      <datalist id="cr-titres">
        {titresConnus.map((t) => (
          <option key={t} value={t} />
        ))}
      </datalist>

      <div className="field">
        <label htmlFor="cr-desc">Description de la créature</label>
        <RichTextarea id="cr-desc" rows={4} grow value={form.description} onChange={(v) => setForm({ ...form, description: v })} />
      </div>
      {msg && <p className="admin-error">{msg}</p>}
      <div className="admin-form-actions">
        <button className="primary" type="submit" disabled={busy}>
          {busy ? "Enregistrement…" : editing ? "Enregistrer" : "Ajouter"}
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
      <p className="muted">
        Catalogue réservé au MJ. Les capacités, actions, réactions… sont partagées par titre : un même titre reprend
        automatiquement le même texte et la même icône.
      </p>
      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Nom</th>
              <th>Type</th>
              <th>Taille</th>
              <th>Santé</th>
              <th>Énergie</th>
              <th>FP</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {creatures.map((c) => (
              <Fragment key={c.id}>
                <tr className={editing === c.id ? "editing" : ""}>
                  <td>{c.nom}</td>
                  <td>{[c.type, c.sous_type].filter(Boolean).join(" · ") || "—"}</td>
                  <td>{c.taille || "—"}</td>
                  <td>{c.sante_max}</td>
                  <td>{c.energie_max}</td>
                  <td>{c.fp}</td>
                  <td className="admin-row-actions">
                    <button type="button" className="text-button" onClick={() => startEdit(c)}>
                      Modifier
                    </button>
                    <DeleteButton
                      id={c.id}
                      confirmingId={confirmingId}
                      onAskConfirm={() => setConfirmingId(c.id)}
                      onCancel={() => setConfirmingId(null)}
                      onConfirm={() => {
                        setConfirmingId(null);
                        supprimer(c.id);
                      }}
                    />
                  </td>
                </tr>
                {editing === c.id && (
                  <tr className="admin-edit-row">
                    <td colSpan={7}>{formEl}</td>
                  </tr>
                )}
              </Fragment>
            ))}
            {!creatures.length && (
              <tr>
                <td colSpan={7} className="muted">
                  Aucune créature pour le moment.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
      {!editing && formEl}
    </div>
  );
}
