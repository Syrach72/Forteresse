import { Fragment, useEffect, useState } from "react";
import { supabase } from "./supabaseClient";
import { RichTextarea } from "./RichText.jsx";
import {
  CATEGORIES_CAPACITES,
  ETATS_JEU,
  IMMUNITES_SUPPLEMENTAIRES,
  SENS_CREATURE,
  SOUS_TYPES_CREATURE,
  TAILLES_CREATURE,
  TYPES_CREATURE,
  TYPES_DEGATS,
  TYPES_VULNERABILITES,
  TYPES_VOL,
  creatureVide,
  entier,
  statsAuto,
} from "./creatures-data.js";

// Catalogue des créatures (administration, MJ seul). Une créature = identité, stats, défenses (listes de
// choix), description, cinq listes extensibles (capacités, actions, actions bonus, réactions, actions
// légendaires), chacune avec son emplacement d'icône (icône des compétences des mercenaires, ou image
// téléversée). Les capacités sont PARTAGÉES par titre :
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
  const { uploadImage, DeleteButton, SearchableSelect } = kit;
  const [creatures, setCreatures] = useState(null);
  const [capacites, setCapacites] = useState([]);
  const [liens, setLiens] = useState([]);
  // Compétences des mercenaires (objets du catalogue des rubriques « Compétences ») : source des icônes.
  const [competences, setCompetences] = useState([]);
  // Armes du catalogue (rubrique « Armes ») et armes choisies pour chaque créature (3 au plus).
  const [armesCatalogue, setArmesCatalogue] = useState([]);
  const [liensArmes, setLiensArmes] = useState([]);
  const [armes, setArmes] = useState([]);
  // Entrée dont le choix d'icône est ouvert : « catégorie:position ».
  const [slotOuvert, setSlotOuvert] = useState(null);
  const [erreur, setErreur] = useState("");
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(creatureVide());
  const [listes, setListes] = useState(listesVides());
  const [msg, setMsg] = useState("");
  const [busy, setBusy] = useState(false);
  const [confirmingId, setConfirmingId] = useState(null);
  // Filtre « toutes catégories » : premier mot du type (bête, vase… ; « bête/vermine » -> bête). "" = toutes.
  const [filtreType, setFiltreType] = useState("");

  async function charger() {
    const [c, p, l, cat, obj, ar] = await Promise.all([
      supabase.from("creature").select("*").order("nom"),
      supabase.from("capacite_creature").select("*").order("titre"),
      supabase.from("creature_capacite").select("*").order("position"),
      supabase.from("categorie").select("id, nom, parent_id"),
      supabase.from("objet_catalogue").select("id, nom, description, icone, categorie_id").order("nom"),
      supabase.from("creature_arme").select("*").order("position"),
    ]);
    const err = c.error || p.error || l.error || cat.error || obj.error || ar.error;
    if (err) {
      setErreur(err.message);
      return;
    }
    setErreur("");
    setCreatures(c.data);
    setCapacites(p.data);
    setLiens(l.data);
    const racine = (id) => {
      let cur = cat.data.find((x) => x.id === id);
      while (cur?.parent_id) cur = cat.data.find((x) => x.id === cur.parent_id);
      return cur?.nom || "";
    };
    setCompetences(
      obj.data
        .map((o) => ({ ...o, racine: racine(o.categorie_id) }))
        .filter((o) => /comp[ée]tences/i.test(o.racine)),
    );
    setArmesCatalogue(obj.data.filter((o) => cle(racine(o.categorie_id)) === "armes"));
    setLiensArmes(ar.data);
  }
  useEffect(() => {
    charger();
  }, []);

  if (erreur) return <p className="admin-error">{erreur}</p>;
  if (!creatures) return <p>Chargement…</p>;

  const motType = (c) => (c.type || "").trim().toLowerCase().split(/[\s/(,]+/)[0] || "sans type";
  const groupesType = [...new Set(creatures.map(motType))].sort((a, b) => a.localeCompare(b, "fr"));
  const creaturesAffichees = creatures
    .filter((c) => !filtreType || motType(c) === filtreType)
    .sort((a, b) => motType(a).localeCompare(motType(b), "fr") || a.nom.localeCompare(b.nom, "fr"));
  const capParTitre = (t) => capacites.find((c) => cle(c.titre) === cle(t));
  const nbUtilisations = (capId) => new Set(liens.filter((l) => l.capacite_id === capId).map((l) => l.creature_id)).size;
  const titresConnus = capacites.map((c) => c.titre).sort((a, b) => a.localeCompare(b, "fr"));

  function startEdit(c) {
    setEditing(c.id);
    setForm({
      nom: c.nom,
      type: c.type || "",
      sous_type: c.sous_type || "",
      taille: c.taille || "",
      compagnon: c.compagnon || "",
      sante_max: String(c.sante_max),
      energie_max: String(c.energie_max),
      vitesse: String(c.vitesse),
      vitesse_escalade: String(c.vitesse_escalade ?? 0),
      vitesse_nage: String(c.vitesse_nage ?? 0),
      vitesse_vol: String(c.vitesse_vol ?? 0),
      vol_type: c.vol_type || "",
      fp: String(c.fp),
      puissance: String(c.puissance),
      velocite: String(c.velocite),
      mental: String(c.mental),
      esquive: c.esquive || "",
      parade: c.parade || "",
      armure: c.armure || "",
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
        if (cap)
          next[l.categorie]?.push({
            titre: cap.titre,
            texte: l.texte ?? cap.texte ?? "",
            icone: cap.icone || "",
            fichier: null,
            auto: cap.texte || "",
            majBase: false,
          });
      });
    setListes(next);
    setArmes(liensArmes.filter((a) => a.creature_id === c.id).map((a) => a.objet_id));
    setSlotOuvert(null);
    setMsg("");
    window.scrollTo?.({ top: 0, behavior: "smooth" });
  }
  function cancel() {
    setEditing(null);
    setForm(creatureVide());
    setListes(listesVides());
    setArmes([]);
    setSlotOuvert(null);
    setMsg("");
  }
  const champ = (k) => (e) => setForm({ ...form, [k]: e.target.value });
  // Puissance, Vélocité et Mental recalculent aussitôt Santé max, Esquive et Énergie max (modifiables ensuite).
  const champStat = (k) => (e) => {
    const f = { ...form, [k]: e.target.value };
    const auto = statsAuto(f);
    if (k === "puissance") f.sante_max = auto.sante_max;
    if (k === "velocite") f.esquive = auto.esquive;
    if (k === "mental") f.energie_max = auto.energie_max;
    setForm(f);
  };

  function majEntree(cat, i, patch) {
    setListes((prev) => ({ ...prev, [cat]: prev[cat].map((e, k) => (k === i ? { ...e, ...patch } : e)) }));
  }
  function changerTitre(cat, i, titre) {
    const e = listes[cat][i];
    const connue = capParTitre(titre);
    const patch = { titre, majBase: false };
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
        compagnon: form.compagnon || null,
        sante_max: entier(form.sante_max, 1, 9999),
        energie_max: entier(form.energie_max, 0, 999),
        vitesse: entier(form.vitesse, 0, 99),
        vitesse_escalade: entier(form.vitesse_escalade, 0, 99),
        vitesse_nage: entier(form.vitesse_nage, 0, 99),
        vitesse_vol: entier(form.vitesse_vol, 0, 99),
        // La précision du vol n'a de sens qu'avec une vitesse de vol.
        vol_type: entier(form.vitesse_vol, 0, 99) > 0 ? form.vol_type || null : null,
        fp: entier(form.fp, 0, 99),
        puissance: entier(form.puissance, 0, 99),
        velocite: entier(form.velocite, 0, 99),
        mental: entier(form.mental, 0, 99),
        esquive: form.esquive.trim() || null,
        parade: form.parade.trim() || null,
        armure: form.armure.trim() || null,
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
      // Capacités : le titre renvoie à une capacité commune (texte + icône). Un texte modifié pour cette
      // créature est gardé sur elle seule (creature_capacite.texte) ; « Appliquer à toutes » corrige le texte commun.
      const creees = new Map();
      const baseDe = (titre) => creees.get(cle(titre)) || capParTitre(titre);
      const lignes = [];
      for (const cat of CATEGORIES_CAPACITES) {
        let pos = 0;
        for (const e of listes[cat.id]) {
          const titre = e.titre.trim();
          if (!titre) continue;
          let icone = e.icone || null;
          if (e.fichier) {
            const r = await uploadImage("catalogue-icones", e.fichier, "creature-" + titre);
            if (r.error) throw new Error(r.error);
            icone = r.url;
          }
          let base = baseDe(titre);
          let surcharge = null;
          if (!base) {
            const { data, error } = await supabase
              .from("capacite_creature")
              .insert({ titre, texte: e.texte, icone })
              .select("id, titre, texte, icone")
              .single();
            if (error) throw error;
            base = data;
            creees.set(cle(titre), base);
          } else {
            const patch = {};
            if (e.majBase && (base.texte || "") !== e.texte) patch.texte = e.texte;
            if ((base.icone || null) !== icone) patch.icone = icone;
            if (Object.keys(patch).length) {
              const { error } = await supabase.from("capacite_creature").update(patch).eq("id", base.id);
              if (error) throw error;
              base = { ...base, ...patch };
              creees.set(cle(titre), base);
            }
            surcharge = e.texte !== (base.texte || "") ? e.texte : null;
          }
          lignes.push({ creature_id: id, categorie: cat.id, position: pos++, capacite_id: base.id, texte: surcharge });
        }
      }
      const { error: delCap } = await supabase.from("creature_capacite").delete().eq("creature_id", id);
      if (delCap) throw delCap;
      if (lignes.length) {
        const { error } = await supabase.from("creature_capacite").insert(lignes);
        if (error) throw error;
      }
      const { error: delArmes } = await supabase.from("creature_arme").delete().eq("creature_id", id);
      if (delArmes) throw delArmes;
      const lignesArmes = armes.filter(Boolean).slice(0, 3).map((objet_id, position) => ({ creature_id: id, position, objet_id }));
      if (lignesArmes.length) {
        const { error } = await supabase.from("creature_arme").insert(lignesArmes);
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
        <input id={`cr-${k}`} type="number" min={min} max={max} value={form[k]} onChange={["puissance", "velocite", "mental"].includes(k) ? champStat(k) : champ(k)} />
      </div>
    </div>
  );

  const texteCourt = (k, libelle) => (
    <div className="field" key={k}>
      <label htmlFor={`cr-${k}`}>{libelle}</label>
      <div className="input-wrap">
        <input id={`cr-${k}`} maxLength={12} value={form[k]} onChange={champ(k)} />
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
        <div className="field">
          <label htmlFor="cr-compagnon">Compagnon des joueurs</label>
          <div className="input-wrap">
            <select id="cr-compagnon" value={form.compagnon} onChange={champ("compagnon")}>
              <option value="">Non (créature du MJ seul)</option>
              <option value="faucon">Compagnon animal : faucon</option>
              <option value="chien">Compagnon animal : chien</option>
              <option value="panthere">Compagnon animal : panthère</option>
              <option value="familier">Familier (Incantateur)</option>
            </select>
          </div>
          <p className="muted">
            Rend cette fiche lisible par les joueurs : Rôdeurs Maîtres des Bêtes (faucon, chien, panthère) et Incantateurs
            (familier) pourront la choisir à la vétérance 3.
          </p>
        </div>
        {nombre("sante_max", "Santé (max, auto)", 1, 9999)}
        {nombre("energie_max", "Énergie (max, auto)", 0, 999)}
        {nombre("vitesse", "Vitesse (en cases)", 0, 99)}
        {nombre("vitesse_escalade", "Escalade (en cases)", 0, 99)}
        {nombre("vitesse_nage", "Nage (en cases)", 0, 99)}
        {nombre("vitesse_vol", "Vol (en cases)", 0, 99)}
        <fieldset className="field creature-vol-type" disabled={!(Number(form.vitesse_vol) > 0)}>
          <legend>Vol : précision</legend>
          {TYPES_VOL.map(([code, libelle]) => (
            <label key={code}>
              <input
                type="checkbox"
                checked={form.vol_type === code}
                onChange={() => setForm({ ...form, vol_type: form.vol_type === code ? "" : code })}
              />{" "}
              {libelle}
            </label>
          ))}
        </fieldset>
        {nombre("fp", "FP", 0, 99)}
        {nombre("puissance", "Puissance", 0, 99)}
        {nombre("velocite", "Vélocité", 0, 99)}
        {nombre("mental", "Mental", 0, 99)}
        {texteCourt("esquive", "Esquive (auto)")}
        {texteCourt("parade", "Parade (ex. II)")}
        {texteCourt("armure", "Armure (ex. 2/3/3)")}
      </div>
      <p className="muted">
        Santé max (3 + 2 × Puissance), Énergie max (2 × Mental) et Esquive (Vélocité ÷ 3, minimum 1) se calculent seules
        dès que vous saisissez Puissance, Mental et Vélocité, comme pour les mercenaires ; vous pouvez les corriger à la
        main. Parade et Armure se saisissent toujours à la main.
      </p>
      <div className="creature-multis">
        <MultiChoix libelle="Vulnérabilités" options={TYPES_VULNERABILITES} valeur={form.vulnerabilites} onChange={(v) => setForm({ ...form, vulnerabilites: v })} />
        <MultiChoix libelle="Résistances" options={TYPES_DEGATS} valeur={form.resistances} onChange={(v) => setForm({ ...form, resistances: v })} />
        <MultiChoix libelle="Immunités aux dégâts" options={TYPES_DEGATS} valeur={form.immunites_degats} onChange={(v) => setForm({ ...form, immunites_degats: v })} />
        <MultiChoix libelle="Immunités aux états" options={[...ETATS_JEU.map((e) => e.nom), ...IMMUNITES_SUPPLEMENTAIRES]} valeur={form.immunites_etats} onChange={(v) => setForm({ ...form, immunites_etats: v })} />
        <MultiChoix libelle="Sens" options={SENS_CREATURE} valeur={form.sens} onChange={(v) => setForm({ ...form, sens: v })} />
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
                  {/* Emplacement d'icône de cette entrée (icône cliquable en jeu) : une compétence des mercenaires
                      ou une image téléversée. */}
                  <button
                    type="button"
                    className={"creature-slot-cell" + (slotOuvert === cat.id + ":" + i ? " ouvert" : "") + (e.fichier || e.icone ? "" : " vide")}
                    onClick={() => setSlotOuvert(slotOuvert === cat.id + ":" + i ? null : cat.id + ":" + i)}
                    title="Icône de cette entrée : cliquez pour choisir"
                    aria-label={`Icône, ${cat.singulier} ${i + 1}`}
                  >
                    {e.fichier || e.icone ? (
                      <img src={e.fichier ? URL.createObjectURL(e.fichier) : e.icone} alt="" />
                    ) : (
                      <small>Icône</small>
                    )}
                  </button>
                  <button
                    type="button"
                    className="text-button"
                    onClick={() => setListes((prev) => ({ ...prev, [cat.id]: prev[cat.id].filter((_, k) => k !== i) }))}
                  >
                    Supprimer
                  </button>
                </div>
                {slotOuvert === cat.id + ":" + i && (
                  <div className="creature-slot-choix">
                    <SearchableSelect
                      value={competences.find((c) => c.icone && c.icone === e.icone)?.id || ""}
                      onChange={(v) => {
                        const c = competences.find((x) => x.id === v);
                        majEntree(cat.id, i, { icone: c?.icone || "", fichier: null });
                        setSlotOuvert(null);
                      }}
                      options={competences.map((c) => ({ value: c.id, label: c.nom, group: c.racine }))}
                      emptyLabel="— Aucune icône —"
                      ariaLabel={`Compétence dont reprendre l’icône, ${cat.singulier} ${i + 1}`}
                    />
                    <label className="text-button">
                      ou téléverser une image{" "}
                      <input
                        type="file"
                        accept="image/*"
                        onChange={(ev) => {
                          majEntree(cat.id, i, { fichier: ev.target.files[0] || null });
                          setSlotOuvert(null);
                        }}
                      />
                    </label>
                    <button type="button" className="text-button" onClick={() => setSlotOuvert(null)}>
                      Fermer
                    </button>
                  </div>
                )}
                <RichTextarea
                  id={`cr-${cat.id}-${i}`}
                  rows={2}
                  grow
                  value={e.texte}
                  onChange={(v) => majEntree(cat.id, i, { texte: v })}
                />
                {connue && e.texte === (connue.texte || "") && (
                  <p className="muted creature-capacite-note">
                    Texte commun repris du titre « {connue.titre} » (partagé avec{" "}
                    {Math.max(0, nbUtilisations(connue.id) - (editing && liens.some((l) => l.creature_id === editing && l.capacite_id === connue.id) ? 1 : 0))}{" "}
                    autre(s) créature(s)). Vous pouvez l’adapter pour cette créature seulement.
                  </p>
                )}
                {connue && e.texte !== (connue.texte || "") && (
                  <p className="muted creature-capacite-note">
                    Texte adapté pour cette créature seulement.{" "}
                    <label>
                      <input
                        type="checkbox"
                        checked={e.majBase}
                        onChange={(ev) => majEntree(cat.id, i, { majBase: ev.target.checked })}
                      />{" "}
                      Appliquer ce texte à toutes les créatures qui portent ce titre
                    </label>
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
                [cat.id]: [...prev[cat.id], { titre: "", texte: "", icone: "", fichier: null, auto: "", majBase: false }],
              }))
            }
          >
            + Ajouter une {cat.singulier}
          </button>
        </div>
      ))}
      <div className="admin-recette-block">
        <p className="eyebrow admin-section-label">Armes (3 au plus)</p>
        {armes.map((objetId, i) => (
          <div className="creature-capacite-tete" key={i}>
            <SearchableSelect
              value={objetId}
              onChange={(v) => setArmes((prev) => prev.map((x, k) => (k === i ? v : x)))}
              options={armesCatalogue.map((o) => ({ value: o.id, label: o.nom }))}
              emptyLabel="— Choisir une arme —"
              ariaLabel={`Arme ${i + 1}`}
            />
            <button type="button" className="text-button" onClick={() => setArmes((prev) => prev.filter((_, k) => k !== i))}>
              Supprimer
            </button>
          </div>
        ))}
        {armes.length < 3 && (
          <button type="button" className="text-button" onClick={() => setArmes((prev) => [...prev, ""])}>
            + Ajouter une arme
          </button>
        )}
      </div>
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
      <div className="admin-catalogue-filter field">
        <label htmlFor="cr-filtre-type">Afficher</label>
        <select id="cr-filtre-type" value={filtreType} onChange={(e) => setFiltreType(e.target.value)}>
          <option value="">Toutes les catégories ({creatures.length} créatures)</option>
          {groupesType.map((g) => (
            <option key={g} value={g}>
              {g.charAt(0).toUpperCase() + g.slice(1)} ({creatures.filter((c) => motType(c) === g).length})
            </option>
          ))}
        </select>
      </div>
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
            {creaturesAffichees.map((c) => (
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
