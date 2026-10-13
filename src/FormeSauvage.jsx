import { useEffect, useState } from "react";
import { supabase } from "./supabaseClient";
import { Modal } from "./Modal.jsx";
import { FicheLue } from "./Compagnon.jsx";

// Forme Sauvage (Druide) : coût 2 Énergies, deux fois par instance, pendant 2 × Mental rounds. Le choix de la bête
// dépend de la vétérance (cumulatif). La fiche vient du catalogue des créatures : le MJ la crée dans
// l'administration et la repère par « Forme sauvage (vétérance 2 / 5 / 8) » ; tant qu'elle n'existe pas, la bête
// reste visible dans la liste mais ne peut pas être choisie.
export const BETES_FORME_SAUVAGE = [
  [2, ["Loup", "Panthère", "Lézard Géant"]],
  [5, ["Ours Noir", "Crocodile", "Grand Singe"]],
  [8, ["Aigle géant", "Ours Brun", "Pieuvre Géante"]],
];
const norm = (t) =>
  (t || "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();

// Fenêtre de choix, ouverte depuis la compétence Forme Sauvage : liste des bêtes de la vétérance, fiche de la bête
// choisie (lecture seule), puis « Valider » qui dépense l'énergie et prend la forme.
export function ChoixFormeSauvage({ merc, mental, onChoisir, onClose }) {
  const vet = merc.veterance ?? 1;
  const [creatures, setCreatures] = useState(undefined);
  const [nomChoisi, setNomChoisi] = useState(null);
  const [busy, setBusy] = useState(false);
  const [erreur, setErreur] = useState("");
  useEffect(() => {
    supabase
      .from("creature")
      .select("id, nom, forme_sauvage")
      .not("forme_sauvage", "is", null)
      .order("nom")
      .then(({ data, error }) => {
        if (error) setErreur(error.message);
        setCreatures(data || []);
      });
  }, []);
  const palierDe = (c) => Number(c.forme_sauvage);
  const betes = BETES_FORME_SAUVAGE.filter(([palier]) => palier <= vet).flatMap(([palier, noms]) =>
    noms.map((nom) => ({
      nom,
      palier,
      // Le nom d'une fiche est unique : une bête déjà prise comme compagnon (Panthère) s'écrit par exemple
      // « Panthère (forme sauvage) » ; on accepte le nom exact ou le nom suivi d'un complément.
      creature:
        (creatures || []).find(
          (c) => (norm(c.nom) === norm(nom) || norm(c.nom).startsWith(norm(nom) + " ")) && palierDe(c) <= vet,
        ) || null,
    })),
  );
  const choisie = betes.find((b) => b.nom === nomChoisi) || null;
  async function valider() {
    if (!choisie?.creature || busy) return;
    setBusy(true);
    const r = await onChoisir(choisie.creature.id);
    setBusy(false);
    if (r?.error) setErreur(r.error);
    else onClose();
  }
  return (
    <Modal title={`${merc.nom} : Forme sauvage`} onClose={onClose}>
      {creatures === undefined ? (
        <p>Chargement…</p>
      ) : (
        <>
          <p>
            Choisissez la bête dont {merc.nom} prend la forme (vétérance {vet}). Vous verrez sa fiche avant de valider ;
            la validation dépense <strong>2 Énergies</strong>.
          </p>
          <div className="humain-choix ennemi-jure-choix">
            {betes.map((b) => (
              <button
                type="button"
                key={b.nom}
                className="wood-button"
                aria-pressed={nomChoisi === b.nom}
                title={b.creature ? `Vétérance ${b.palier}` : "Fiche pas encore créée"}
                onClick={() => {
                  setNomChoisi(b.nom);
                  setErreur("");
                }}
              >
                {b.nom}
                {b.creature ? "" : " (à venir)"}
              </button>
            ))}
          </div>
          {choisie &&
            (choisie.creature ? (
              <FicheLue
                creatureId={choisie.creature.id}
                apercu
                ligne={{ id: "apercu", nom_onglet: choisie.nom, etat_niveau: 1, etat_rounds: 0 }}
                sauver={() => {}}
                mentalForce={mental}
              />
            ) : (
              <p className="muted">
                La fiche de la bête « {choisie.nom} » n’est pas encore créée. Le MJ doit la créer dans l’administration
                (Créatures) avec « Forme sauvage » (vétérance {choisie.palier}).
              </p>
            ))}
          <p>
            <button type="button" className="text-button" onClick={onClose}>
              Annuler
            </button>{" "}
            <button type="button" className="wood-button" disabled={!choisie?.creature || busy} onClick={valider}>
              Valider : prendre la forme (2 Énergies)
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

// Contenu de l'onglet « Forme sauvage » : fiche de la bête, rounds restants, retour à la forme originale.
export function OngletFormeSauvage({ merc, mental, titreMerc, peutModifier, onMaj, onTerminer }) {
  const ligne = merc.formeSauvage;
  const [confirmer, setConfirmer] = useState(false);
  const [busy, setBusy] = useState(false);
  const [erreur, setErreur] = useState("");
  async function terminer() {
    setBusy(true);
    const r = await onTerminer(merc.id);
    setBusy(false);
    if (r?.error) setErreur(r.error);
  }
  return (
    <section
      className="merc-bloc parchment"
      id="merc-rubrique-forme-sauvage"
      role="tabpanel"
      aria-labelledby="merc-onglet-forme-sauvage"
    >
      {titreMerc}
      <h2>Forme sauvage</h2>
      <p>
        <strong>Rounds restants : {ligne.rounds_restants}</strong>{" "}
        <span className="muted">(sur {ligne.rounds_total}, décomptés à chaque clic sur Rd)</span>
      </p>
      <p className="muted">
        Les statistiques et compétences de la bête remplacent celles de {merc.nom}, sauf la Carac. Mental. Les PV de la
        bête sont endossés : à 0 PV, {merc.nom} retrouve sa forme et ses PV. L’équipement fusionne avec lui et ne peut pas
        être utilisé ; aucun sort ne peut être lancé.
      </p>
      <FicheLue
        creatureId={ligne.creature_id}
        ligne={{ ...ligne, nom_onglet: "Forme sauvage" }}
        sauver={(patch) => peutModifier && onMaj(merc.id, patch)}
        mentalForce={mental}
      />
      {peutModifier && (
        <p>
          {confirmer ? (
            <>
              <button type="button" className="wood-button" disabled={busy} onClick={terminer}>
                Valider : retour à la forme originale
              </button>{" "}
              <button type="button" className="text-button" disabled={busy} onClick={() => setConfirmer(false)}>
                Annuler
              </button>
            </>
          ) : (
            <button type="button" className="wood-button" onClick={() => setConfirmer(true)}>
              Retour forme originale
            </button>
          )}
        </p>
      )}
      {erreur && (
        <p className="error" role="alert">
          {erreur}
        </p>
      )}
    </section>
  );
}
