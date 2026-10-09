import { useEffect, useState } from "react";
import { supabase } from "./supabaseClient";
import { Modal } from "./Modal.jsx";
import { RichText } from "./RichText.jsx";
import { FicheCreatureJeu, chargerArmes } from "./CreaturesQuete.jsx";

// Compagnon animal (Rôdeur Maître des Bêtes) et familier (Incantateur), dès la vétérance 3. Les fiches viennent du
// catalogue des créatures (créées par le MJ dans l'administration, repérées par `creature.compagnon`). Le joueur
// choisit un animal, voit sa fiche, puis la valide : elle devient l'onglet « Compagnon » / « Familier » de la fiche
// du mercenaire. Le choix est définitif (seul le MJ peut le retirer).
export const ANIMAUX_COMPAGNON = [
  ["faucon", "Faucon"],
  ["chien", "Chien"],
  ["panthere", "Panthère"],
];
export const LIBELLE_ROLE = { compagnon: "Compagnon", familier: "Familier" };

// Fiche complète (créature, capacités, icônes de capacités, armes) d'une créature du catalogue.
function useFicheCreature(creatureId) {
  const [donnees, setDonnees] = useState(undefined);
  useEffect(() => {
    if (!creatureId) {
      setDonnees(undefined);
      return undefined;
    }
    let annule = false;
    setDonnees(undefined);
    (async () => {
      const [c, li, cap, ar] = await Promise.all([
        supabase.from("creature").select("*").eq("id", creatureId).maybeSingle(),
        supabase.from("creature_capacite").select("*").eq("creature_id", creatureId).order("position"),
        supabase.from("capacite_creature").select("*"),
        chargerArmes([creatureId]),
      ]);
      if (annule) return;
      const err = c.error || li.error || cap.error || ar.error;
      if (err) return setDonnees({ erreur: err.message });
      if (!c.data) return setDonnees({ erreur: "Cette fiche n’est pas disponible." });
      setDonnees({ fiche: c.data, liens: li.data, capacites: cap.data, armes: ar.data.filter((x) => x.objet) });
    })();
    return () => {
      annule = true;
    };
  }, [creatureId]);
  return donnees;
}

function FicheLue({ creatureId, ligne, sauver, apercu = false }) {
  const d = useFicheCreature(creatureId);
  const [fenetre, setFenetre] = useState(null);
  if (d === undefined) return <p>Chargement de la fiche…</p>;
  if (d.erreur) return <p className="error">{d.erreur}</p>;
  return (
    <>
      <FicheCreatureJeu
        apercu={apercu}
        ligne={ligne}
        fiche={d.fiche}
        liens={d.liens}
        armes={d.armes}
        capDe={(id) => d.capacites.find((c) => c.id === id)}
        sauver={sauver}
        ouvrirIcone={setFenetre}
        sansNomOnglet
      />
      {fenetre && (
        <Modal title={fenetre.titre} onClose={() => setFenetre(null)}>
          <div className="comp-detail">
            {fenetre.icone && <img className="comp-detail-icone" src={fenetre.icone} alt="" />}
            <p>
              <RichText text={fenetre.texte || "Aucune description pour le moment."} />
            </p>
          </div>
        </Modal>
      )}
    </>
  );
}

// Fenêtre de choix : l'animal (ou le familier), sa fiche, puis « Valider ».
export function ChoixCompagnon({ merc, onChoisir, onClose }) {
  const role = merc.compagnonRole;
  const [creatures, setCreatures] = useState(undefined);
  const [tag, setTag] = useState(null);
  const [creatureId, setCreatureId] = useState(null);
  const [busy, setBusy] = useState(false);
  const [erreur, setErreur] = useState("");
  useEffect(() => {
    supabase
      .from("creature")
      .select("id, nom, compagnon")
      .not("compagnon", "is", null)
      .order("nom")
      .then(({ data, error }) => {
        if (error) setErreur(error.message);
        setCreatures(data || []);
      });
  }, []);
  const candidats = creatures && tag ? creatures.filter((c) => c.compagnon === tag) : [];
  const choisi = candidats.find((c) => c.id === creatureId) || candidats[0] || null;
  const libelleTag = ANIMAUX_COMPAGNON.find(([t]) => t === tag)?.[1];
  async function valider() {
    if (!choisi || busy) return;
    setBusy(true);
    const r = await onChoisir(merc.id, choisi.id);
    setBusy(false);
    if (r?.error) setErreur(r.error);
    else onClose();
  }
  const titre = role === "familier" ? `${merc.nom} : choisir un familier` : `${merc.nom} : choisir un compagnon animal`;
  return (
    <Modal title={titre} onClose={onClose}>
      {creatures === undefined ? (
        <p>Chargement…</p>
      ) : !tag ? (
        <>
          <p>
            {role === "familier" ? (
              <>Choisissez le <strong>familier</strong> de {merc.nom}.</>
            ) : (
              <>Choisissez le <strong>compagnon animal</strong> de {merc.nom}.</>
            )}{" "}
            Vous verrez sa fiche avant de valider ; le choix est définitif.
          </p>
          <div className="humain-choix ennemi-jure-choix">
            {role === "familier" ? (
              <button type="button" className="wood-button" onClick={() => setTag("familier")}>
                Voir les familiers
              </button>
            ) : (
              ANIMAUX_COMPAGNON.map(([t, l]) => (
                <button type="button" key={t} className="wood-button" onClick={() => setTag(t)}>
                  {l}
                </button>
              ))
            )}
          </div>
        </>
      ) : (
        <>
          {candidats.length > 1 && (
            <label className="creature-nom-onglet">
              Fiche
              <select value={choisi?.id || ""} onChange={(e) => setCreatureId(e.target.value)}>
                {candidats.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.nom}
                  </option>
                ))}
              </select>
            </label>
          )}
          {choisi ? (
            <FicheLue creatureId={choisi.id} apercu ligne={{ id: "apercu", nom_onglet: choisi.nom, etat_niveau: 1, etat_rounds: 0 }} sauver={() => {}} />
          ) : (
            <p className="muted">
              {role === "familier" ? "Aucune fiche de familier" : `La fiche du ${libelleTag?.toLowerCase()}`} n’est pas encore créée.
              Le MJ doit la créer dans l’administration (Créatures).
            </p>
          )}
          <p>
            <button type="button" className="text-button" onClick={() => { setTag(null); setCreatureId(null); setErreur(""); }}>
              ← Retour
            </button>{" "}
            <button type="button" className="wood-button" disabled={!choisi || busy} onClick={valider}>
              Valider ce choix
            </button>
          </p>
        </>
      )}
      {erreur && (
        <p className="error" role="alert">
          {erreur}
        </p>
      )}
    </Modal>
  );
}

// Contenu de l'onglet « Compagnon » / « Familier » de la fiche du mercenaire.
export function OngletCompagnon({ merc, titreMerc, peutModifier, onMaj }) {
  const ligne = merc.compagnon;
  return (
    <section
      className="merc-bloc parchment"
      id={`merc-rubrique-${ligne.role}`}
      role="tabpanel"
      aria-labelledby={`merc-onglet-${ligne.role}`}
    >
      {titreMerc}
      <h2>{LIBELLE_ROLE[ligne.role]}</h2>
      <FicheLue
        creatureId={ligne.creature_id}
        ligne={{ ...ligne, nom_onglet: LIBELLE_ROLE[ligne.role] }}
        sauver={(patch) => peutModifier && onMaj(merc.id, patch)}
      />
    </section>
  );
}
