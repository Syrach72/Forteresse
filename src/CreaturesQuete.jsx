import { useEffect, useState } from "react";
import { supabase } from "./supabaseClient";
import { RichText } from "./RichText.jsx";
import { Modal } from "./Modal.jsx";
import { Orbe } from "./MercFiche.jsx";
import { CATEGORIES_CAPACITES, DETAIL_ETATS, ETATS_JEU, TAILLES_CREATURE, TYPES_VOL, entier, nomEtat } from "./creatures-data.js";

// Page MJ des créatures en jeu (route #creatures), visible et modifiable du MJ seul. Une fiche par
// créature de la quête en cours, avec un onglet renommable. La fiche est lue dans le catalogue (une
// correction du catalogue s'y répercute aussitôt) ; seul l'état de jeu (santé, énergie, état, rounds,
// nom d'onglet, commentaires) se modifie ici, par créature. Santé/énergie vides = maximum.
const CHIFFRES_ENERGIE = Array.from({ length: 10 }, (_, i) => i + 1);

// Routes : #creatures (quête en cours), #creatures/<id> (une créature), et en APERÇU, avant que la quête soit
// choisie : #creatures/quete/<idQuête>[/<clé>] (fiches lues dans le catalogue, rien à modifier).
export function CreaturesQuete({ estAdmin, roundCourant, route = "creatures", notify = () => {} }) {
  const parts = route.split("/");
  const apercuQuete = parts[1] === "quete" ? parts[2] : null;
  const routeId = apercuQuete ? parts[3] : parts[1];
  const [donnees, setDonnees] = useState(undefined);
  const [erreur, setErreur] = useState("");
  const [fenetre, setFenetre] = useState(null); // { ligneId, capacite }

  async function charger() {
    const qe = await supabase.from("quete_etat").select("quete_id").eq("en_cours", true).maybeSingle();
    if (qe.error) return setErreur(qe.error.message);
    // Aperçu : la quête demandée n'est pas (ou plus) la quête en cours -> créatures prévues, lues au catalogue.
    if (apercuQuete && qe.data?.quete_id !== apercuQuete) return chargerApercu();
    if (!qe.data) return setDonnees({ quete: null, lignes: [] });
    const [q, l] = await Promise.all([
      supabase.from("quete").select("id, nom").eq("id", qe.data.quete_id).single(),
      supabase.from("creature_quete").select("*").eq("quete_id", qe.data.quete_id).order("ordre"),
    ]);
    if (q.error || l.error) return setErreur((q.error || l.error).message);
    // Quête déjà choisie mais sans créature en jeu (créatures ajoutées après le choix) : on montre l'aperçu.
    if (apercuQuete === qe.data.quete_id && !l.data.length) return chargerApercu(true);
    const ids = [...new Set(l.data.map((x) => x.creature_id))];
    let creatures = [];
    let liens = [];
    let icones = [];
    let capacites = [];
    let competences = [];
    if (ids.length) {
      const [c, li, ic, cap] = await Promise.all([
        supabase.from("creature").select("*").in("id", ids),
        supabase.from("creature_capacite").select("*").in("creature_id", ids).order("position"),
        supabase.from("creature_icone").select("*").in("creature_id", ids).order("position"),
        supabase.from("capacite_creature").select("*"),
      ]);
      const err = c.error || li.error || ic.error || cap.error;
      if (err) return setErreur(err.message);
      creatures = c.data;
      liens = li.data;
      icones = ic.data;
      capacites = cap.data;
      const compIds = [...new Set(ic.data.map((x) => x.competence_id))];
      if (compIds.length) {
        const comp = await supabase.from("objet_catalogue").select("id, nom, description, icone").in("id", compIds);
        if (comp.error) return setErreur(comp.error.message);
        competences = comp.data;
      }
    }
    setErreur("");
    setDonnees({ quete: q.data, lignes: l.data, creatures, liens, icones, capacites, competences });
  }
  // Aperçu d'une quête pas encore choisie : une entrée par exemplaire prévu (mêmes noms d'onglet qu'au choix).
  async function chargerApercu(dejaChoisie = false) {
    const [q, qc] = await Promise.all([
      supabase.from("quete").select("id, nom").eq("id", apercuQuete).single(),
      supabase.from("quete_creature").select("creature_id, quantite").eq("quete_id", apercuQuete),
    ]);
    if (q.error || qc.error) return setErreur((q.error || qc.error).message);
    const ids = [...new Set(qc.data.map((x) => x.creature_id))];
    let creatures = [];
    let liens = [];
    let icones = [];
    let capacites = [];
    let competences = [];
    if (ids.length) {
      const [c, li, ic, cap] = await Promise.all([
        supabase.from("creature").select("*").in("id", ids),
        supabase.from("creature_capacite").select("*").in("creature_id", ids).order("position"),
        supabase.from("creature_icone").select("*").in("creature_id", ids).order("position"),
        supabase.from("capacite_creature").select("*"),
      ]);
      const err = c.error || li.error || ic.error || cap.error;
      if (err) return setErreur(err.message);
      creatures = c.data;
      liens = li.data;
      icones = ic.data;
      capacites = cap.data;
      const compIds = [...new Set(ic.data.map((x) => x.competence_id))];
      if (compIds.length) {
        const comp = await supabase.from("objet_catalogue").select("id, nom, description, icone").in("id", compIds);
        if (comp.error) return setErreur(comp.error.message);
        competences = comp.data;
      }
    }
    const lignes = [];
    for (const x of [...qc.data].sort((a, b) =>
      (creatures.find((c) => c.id === a.creature_id)?.nom || "").localeCompare(creatures.find((c) => c.id === b.creature_id)?.nom || "", "fr"),
    )) {
      const f = creatures.find((c) => c.id === x.creature_id);
      for (let n = 1; n <= x.quantite; n++)
        lignes.push({
          id: "apercu-" + x.creature_id + "-" + n,
          creature_id: x.creature_id,
          nom_onglet: x.quantite > 1 ? f.nom + " " + n : f.nom,
          sante_actuelle: null,
          energie_actuelle: null,
          etat: null,
          etat_niveau: 1,
          etat_rounds: 0,
          commentaires: "",
        });
    }
    setErreur("");
    setDonnees({ apercu: true, dejaChoisie, quete: q.data, lignes, creatures, liens, icones, capacites, competences });
  }
  useEffect(() => {
    if (!estAdmin) return undefined;
    setDonnees(undefined);
    charger();
    const canal = supabase
      .channel("creatures-live")
      .on("postgres_changes", { event: "*", schema: "public", table: "creature_quete" }, charger)
      .on("postgres_changes", { event: "*", schema: "public", table: "quete_etat" }, charger)
      .subscribe();
    return () => supabase.removeChannel(canal);
  }, [estAdmin, apercuQuete]);
  // Un clic sur RD (ou son annulation) change l'énergie et les rounds d'état : on relit.
  useEffect(() => {
    if (estAdmin && donnees !== undefined) charger();
  }, [roundCourant]);

  if (!estAdmin) return <p className="muted">Cette page est réservée au MJ.</p>;
  if (erreur) return <p className="error">{erreur}</p>;
  if (donnees === undefined) return <p>Chargement…</p>;
  if (!donnees.quete)
    return (
      <section className="creature-page">
        <div className="parchment creature-vide">
          <h2>Créatures de la quête</h2>
          <p>Aucune quête n’est en cours. Choisissez une quête pour retrouver ses créatures ici.</p>
          <a href="#quetes">Aller aux quêtes</a>
        </div>
      </section>
    );
  const { quete, lignes, creatures, liens, icones, capacites, competences, apercu, dejaChoisie } = donnees;
  const base = apercu ? "#creatures/quete/" + quete.id + "/" : "#creatures/";
  if (!lignes.length)
    return (
      <section className="creature-page">
        <div className="parchment creature-vide">
          <h2>Créatures — {quete.nom}</h2>
          <p>
            Aucune créature n’a été prévue pour cette quête (onglet « Créatures » de l’administration, puis formulaire de
            la quête). Si vous venez de les ajouter à une quête déjà choisie, annulez son choix puis choisissez-la de nouveau : les créatures sont créées au choix.
          </p>
        </div>
      </section>
    );

  const courante = lignes.find((l) => l.id === routeId) || lignes[0];
  const fiche = creatures.find((c) => c.id === courante.creature_id);

  function majLocal(id, patch) {
    setDonnees((d) => ({ ...d, lignes: d.lignes.map((l) => (l.id === id ? { ...l, ...patch } : l)) }));
  }
  async function sauver(id, patch) {
    majLocal(id, patch);
    const { error } = await supabase.from("creature_quete").update(patch).eq("id", id);
    if (error) {
      notify(error.message);
      charger();
    }
  }
  const capDe = (id) => capacites.find((c) => c.id === id);
  // Navigation d'une créature à l'autre (flèches, en boucle) en plus des onglets.
  const indexCourant = lignes.findIndex((l) => l.id === courante.id);
  const aller = (delta) => {
    location.hash = base.slice(1) + lignes[(indexCourant + delta + lignes.length) % lignes.length].id;
  };

  return (
    <section className="creature-page">
      <h2 className="creature-titre-page">Créatures — {quete.nom}</h2>
      {apercu && (
        <p className="creature-apercu-bandeau" role="note">
          {dejaChoisie
            ? "Aperçu : cette quête est déjà choisie, mais ces créatures y ont été ajoutées après le choix. Annulez le choix puis choisissez-la de nouveau pour les créer ; d’ici là leur santé, leur énergie et leurs états ne peuvent pas être modifiés."
            : "Aperçu : cette quête n’est pas encore choisie. Les créatures seront créées au choix de la quête ; leur santé, leur énergie et leurs états ne peuvent pas encore être modifiés."}
        </p>
      )}
      <div className="creature-onglets" role="tablist" aria-label="Créatures de la quête">
        {lignes.length > 1 && (
          <button type="button" className="creature-fleche" onClick={() => aller(-1)} aria-label="Créature précédente" title="Créature précédente">
            ‹
          </button>
        )}
        {lignes.map((l) => {
          const f = creatures.find((c) => c.id === l.creature_id);
          const sante = l.sante_actuelle ?? f?.sante_max;
          return (
            <a
              key={l.id}
              role="tab"
              aria-selected={l.id === courante.id}
              className={`creature-onglet${l.id === courante.id ? " actif" : ""}${sante === 0 ? " detruite" : ""}`}
              href={base + l.id}
            >
              {l.nom_onglet} <small className="creature-onglet-pv">{sante ?? "?"}/{f?.sante_max ?? "?"}</small>
            </a>
          );
        })}
        {lignes.length > 1 && (
          <button type="button" className="creature-fleche" onClick={() => aller(1)} aria-label="Créature suivante" title="Créature suivante">
            ›
          </button>
        )}
      </div>
      {fiche && (
        <FicheCreatureJeu
          apercu={!!apercu}
          key={courante.id}
          ligne={courante}
          fiche={fiche}
          liens={liens.filter((x) => x.creature_id === fiche.id)}
          icones={icones.filter((x) => x.creature_id === fiche.id)}
          capDe={capDe}
          competences={competences}
          sauver={(patch) => sauver(courante.id, patch)}
          ouvrirIcone={(capacite) => setFenetre({ ligneId: courante.id, capacite })}
        />
      )}
      {fenetre && (
        <FenetreCapacite
          capacite={fenetre.capacite}
          apercu={!!apercu}
          ligne={lignes.find((l) => l.id === fenetre.ligneId)}
          fiche={fiche}
          onClose={() => setFenetre(null)}
          onEnergie={(valeur) => majLocal(fenetre.ligneId, { energie_actuelle: valeur })}
        />
      )}
    </section>
  );
}

function FicheCreatureJeu({ ligne, fiche, liens, icones, capDe, competences, sauver, ouvrirIcone, apercu = false }) {
  const santeMax = fiche.sante_max;
  const energieMax = fiche.energie_max;
  const sante = ligne.sante_actuelle ?? santeMax;
  const energie = ligne.energie_actuelle ?? energieMax;
  const [santeSaisie, setSanteSaisie] = useState(String(sante));
  const [nomOnglet, setNomOnglet] = useState(ligne.nom_onglet);
  const [commentaires, setCommentaires] = useState(ligne.commentaires || "");
  useEffect(() => setSanteSaisie(String(sante)), [sante]);
  useEffect(() => setNomOnglet(ligne.nom_onglet), [ligne.nom_onglet]);

  // 0 = créature détruite ; jamais de valeur négative.
  const validerSante = (v) => {
    const n = entier(v, 0, 9999);
    setSanteSaisie(String(n));
    if (n !== sante) sauver({ sante_actuelle: n });
  };
  const choisirEtat = (e) =>
    ligne.etat === e.id
      ? sauver({ etat: null, etat_niveau: 1, etat_rounds: 0, etat_efface: null })
      : sauver({ etat: e.id, etat_niveau: 1 });
  const lignesPar = (cat) =>
    liens
      .filter((x) => x.categorie === cat)
      .sort((a, b) => a.position - b.position)
      .map((x) => {
        const cap = capDe(x.capacite_id);
        // Texte adapté à cette créature (s'il y en a un), sinon le texte commun du titre.
        return cap ? { ...cap, texte: x.texte ?? cap.texte } : null;
      })
      .filter(Boolean);
  const listeTexte = (libelle, valeurs) =>
    valeurs?.length ? (
      <div className="stat-line">
        <span>{libelle}</span>
        <strong>{valeurs.join(", ")}</strong>
      </div>
    ) : null;

  return (
    <article className={`creature-fiche parchment${sante === 0 ? " creature-detruite" : ""}${apercu ? " creature-apercu" : ""}`}>
      <header className="creature-fiche-tete">
        <div>
          <h3>{fiche.nom}</h3>
          <p className="muted">
            {[fiche.type, fiche.sous_type, TAILLES_CREATURE.find(([c]) => c === fiche.taille)?.[1]]
              .filter(Boolean)
              .join(" · ") || "—"}
          </p>
        </div>
        <label className="creature-nom-onglet">
          Nom de l’onglet
          <input
            value={nomOnglet}
            onChange={(e) => setNomOnglet(e.target.value)}
            onBlur={() =>
              nomOnglet.trim()
                ? nomOnglet.trim() !== ligne.nom_onglet && sauver({ nom_onglet: nomOnglet.trim() })
                : setNomOnglet(ligne.nom_onglet)
            }
            onKeyDown={(e) => e.key === "Enter" && e.currentTarget.blur()}
          />
        </label>
      </header>

      <div className="creature-jauges">
        <div className="creature-sante">
          <Orbe
            type="sante"
            libelle="Santé"
            id="creature-sante"
            max={santeMax}
            actuelle={sante}
            editable
            valeur={santeSaisie}
            onChange={setSanteSaisie}
          />
          <div className="creature-sante-boutons">
            <button type="button" className="wood-button" onClick={() => validerSante(sante - 1)} aria-label="Retirer 1 de santé">
              −1
            </button>
            <button
              type="button"
              className="wood-button"
              onClick={() => validerSante(santeSaisie)}
              disabled={Number(santeSaisie) === sante}
            >
              Valider
            </button>
            <button type="button" className="wood-button" onClick={() => validerSante(sante + 1)} aria-label="Ajouter 1 de santé">
              +1
            </button>
          </div>
          {sante === 0 && <p className="creature-detruite-texte">Détruite (0 PV)</p>}
        </div>
        <Orbe type="energie" libelle="Énergie" id="creature-energie" max={energieMax} actuelle={energie} />
      </div>

      <div className="merc-defense creature-defense">
        {[
          ["Esquive", "/assets/icons/esquive.webp", fiche.esquive],
          ["Parade", "/assets/icons/parade.webp", fiche.parade],
          ["Armure", "/assets/icons/armure.webp", fiche.armure],
        ].map(([libelle, icone, valeur]) => (
          <div className="merc-defense-ligne" key={libelle}>
            <img className="merc-defense-icone" src={icone} alt={libelle} title={libelle} />
            <strong className="merc-defense-valeur">{valeur || "—"}</strong>
          </div>
        ))}
      </div>

      <div className="creature-stats">
        <div className="stat-line">
          <span>FP</span>
          <strong>{fiche.fp}</strong>
        </div>
        <div className="stat-line">
          <span>Vitesse</span>
          <strong>{fiche.vitesse} case(s)</strong>
        </div>
        {fiche.vitesse_escalade > 0 && (
          <div className="stat-line">
            <span>Escalade</span>
            <strong>{fiche.vitesse_escalade} case(s)</strong>
          </div>
        )}
        {fiche.vitesse_nage > 0 && (
          <div className="stat-line">
            <span>Nage</span>
            <strong>{fiche.vitesse_nage} case(s)</strong>
          </div>
        )}
        {fiche.vitesse_vol > 0 && (
          <div className="stat-line">
            <span>Vol</span>
            <strong>
              {fiche.vitesse_vol} case(s)
              {fiche.vol_type ? ` (${TYPES_VOL.find(([c]) => c === fiche.vol_type)?.[1] || fiche.vol_type})` : ""}
            </strong>
          </div>
        )}
        <div className="stat-line">
          <span>Puissance</span>
          <strong>{fiche.puissance}</strong>
        </div>
        <div className="stat-line">
          <span>Vélocité</span>
          <strong>{fiche.velocite}</strong>
        </div>
        <div className="stat-line">
          <span>Mental</span>
          <strong>{fiche.mental}</strong>
        </div>
        {listeTexte("Vulnérabilités", fiche.vulnerabilites)}
        {listeTexte("Résistances", fiche.resistances)}
        {listeTexte("Immunités aux dégâts", fiche.immunites_degats)}
        {listeTexte("Immunités aux états", fiche.immunites_etats)}
        {listeTexte("Sens", fiche.sens)}
      </div>

      <h4 className="creature-section">État</h4>
      <EtatsBoutons
        etat={ligne.etat}
        niveau={ligne.etat_niveau}
        rounds={ligne.etat_rounds}
        onEtat={choisirEtat}
        onNiveau={(n) => sauver({ etat: "epuise", etat_niveau: n })}
        onRounds={(n) => sauver({ etat_rounds: n })}
      />

      {CATEGORIES_CAPACITES.map((cat) => {
        const entrees = lignesPar(cat.id);
        return entrees.length ? (
          <div key={cat.id}>
            <h4 className="creature-section">{cat.label}</h4>
            {entrees.map((c) => (
              <div className="creature-entree creature-entree-icone" key={c.id}>
                {c.icone && (
                  <button
                    type="button"
                    className="creature-icone-bouton"
                    onClick={() => ouvrirIcone({ id: c.id, titre: c.titre, texte: c.texte, icone: c.icone })}
                    title={c.titre}
                  >
                    <img src={c.icone} alt={c.titre} />
                  </button>
                )}
                <p>
                  <strong>{c.titre}.</strong> <RichText text={c.texte} />
                </p>
              </div>
            ))}
          </div>
        ) : null;
      })}

      {fiche.description && (
        <>
          <h4 className="creature-section">Description</h4>
          <p>
            <RichText text={fiche.description} />
          </p>
        </>
      )}

      <h4 className="creature-section">Commentaires</h4>
      <textarea
        className="creature-commentaires"
        rows={3}
        value={commentaires}
        onChange={(e) => setCommentaires(e.target.value)}
        onBlur={() => commentaires !== (ligne.commentaires || "") && sauver({ commentaires })}
        aria-label="Commentaires sur cette créature"
        placeholder="Notes de partie…"
      />
    </article>
  );
}

// Les quinze états du jeu : un seul actif à la fois, les autres grisés. « Épuisé » a trois niveaux.
// Un seul sélecteur de rounds (— = sans durée, 1 à 9) : chaque clic sur RD en retire 1 ; à 0 l'état
// disparaît. Utilisé aussi sur la fiche d'un mercenaire en quête.
export function EtatsBoutons({ etat, niveau, rounds, onEtat, onNiveau, onRounds, desactive = false }) {
  // État dont la fenêtre de détail (badge « ? ») est ouverte.
  const [detail, setDetail] = useState(null);
  return (
    <div className="creature-etats">
      <div className="creature-etats-boutons" role="group" aria-label="États">
        {ETATS_JEU.map((e) => (
          <span className="creature-etat-case" key={e.id}>
            {etat === e.id && (
              <button
                type="button"
                className="creature-etat-aide"
                aria-label={`Détail de l’état ${e.nom}`}
                title="Détail de l’état"
                onClick={() => setDetail(e)}
              >
                ?
              </button>
            )}
            <button
              type="button"
              className={`creature-etat${etat === e.id ? " actif" : ""}${e.positif ? " positif" : ""}${e.bleu ? " bleu" : ""}`}
              aria-pressed={etat === e.id}
              disabled={desactive}
              onClick={() => onEtat(e)}
            >
              {e.nom}
              {e.id === "epuise" && etat === "epuise" ? ` ${niveau}` : ""}
            </button>
          </span>
        ))}
      </div>
      {etat === "epuise" && (
        <div className="creature-etat-niveaux" role="group" aria-label="Niveau d’épuisement">
          {[1, 2, 3].map((n) => (
            <button
              type="button"
              key={n}
              className={`creature-etat${niveau === n ? " actif" : ""}`}
              aria-pressed={niveau === n}
              disabled={desactive}
              onClick={() => onNiveau(n)}
            >
              Niveau {n}
            </button>
          ))}
        </div>
      )}
      <label className="creature-rounds">
        Rounds restants
        <select
          value={rounds}
          disabled={desactive || !etat}
          onChange={(e) => onRounds(Number(e.target.value))}
          aria-label="Rounds restants pour l’état"
        >
          <option value={0}>—</option>
          {[1, 2, 3, 4, 5, 6, 7, 8, 9].map((n) => (
            <option key={n} value={n}>
              {n}
            </option>
          ))}
        </select>
      </label>
      {detail && (
        <Modal title={detail.nom} onClose={() => setDetail(null)}>
          <p><RichText text={DETAIL_ETATS[detail.id] || "Description à rédiger."} /></p>
        </Modal>
      )}
      {etat && (
        <p className="muted creature-etat-resume">
          {nomEtat(etat)}
          {etat === "epuise" ? ` (niveau ${niveau})` : ""}
          {rounds ? ` — encore ${rounds} round${rounds > 1 ? "s" : ""}` : " — sans durée"}
        </p>
      )}
    </div>
  );
}

// Fenêtre d'une icône : texte de la capacité, puis tableau 1 à 10 pour choisir l'énergie à dépenser
// (comme pour les mercenaires). Un montant supérieur à l'énergie actuelle est bloqué.
function FenetreCapacite({ capacite, ligne, fiche, onClose, onEnergie, apercu = false }) {
  const energie = ligne.energie_actuelle ?? fiche.energie_max;
  const [choix, setChoix] = useState(null);
  const [enCours, setEnCours] = useState(false);
  const [erreur, setErreur] = useState("");
  const [depense, setDepense] = useState(null);
  async function valider() {
    setEnCours(true);
    const { data, error } = await supabase.rpc("creature_depenser_energie", {
      p_creature_quete: ligne.id,
      p_montant: choix,
    });
    setEnCours(false);
    if (error) {
      setErreur(error.message);
      return;
    }
    setErreur("");
    setDepense(choix);
    setChoix(null);
    onEnergie(data);
  }
  return (
    <Modal title={capacite.titre} onClose={onClose}>
      <div className="comp-detail">
        {capacite.icone && <img className="comp-detail-icone" src={capacite.icone} alt="" />}
        <p>
          <RichText text={capacite.texte || "Aucune description pour le moment."} />
        </p>
        {apercu ? (
          <p className="muted">L’énergie se dépense une fois la quête choisie.</p>
        ) : (
        <div className="energie-compteur">
          <p className="energie-compteur-titre">
            Dépenser de l’énergie <span className="muted">(disponible : {energie})</span>
          </p>
          <div className="energie-compteur-chiffres" role="group" aria-label="Énergie à dépenser">
            {CHIFFRES_ENERGIE.map((n) => (
              <button
                key={n}
                type="button"
                className="energie-chiffre"
                aria-pressed={choix === n}
                disabled={enCours || n > energie}
                onClick={() => {
                  setChoix(n);
                  setErreur("");
                  setDepense(null);
                }}
              >
                {n}
              </button>
            ))}
          </div>
          {choix !== null && (
            <p className="energie-compteur-valider">
              <button type="button" className="wood-button" disabled={enCours} onClick={valider}>
                Valider : dépenser {choix} énergie{choix > 1 ? "s" : ""}
              </button>{" "}
              <button type="button" className="text-button" disabled={enCours} onClick={() => setChoix(null)}>
                Annuler
              </button>
            </p>
          )}
          {depense !== null && (
            <p className="comp-detail-ok" role="status">
              {depense} énergie{depense > 1 ? "s" : ""} dépensée{depense > 1 ? "s" : ""}.
            </p>
          )}
          {erreur && (
            <p className="error" role="alert">
              {erreur}
            </p>
          )}
        </div>
        )}
      </div>
    </Modal>
  );
}
