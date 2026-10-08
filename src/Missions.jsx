import { useState } from "react";
import { Modal } from "./Modal.jsx";
import { libelleEffet } from "./effets.js";

const fmt = (n) => new Intl.NumberFormat("fr-FR").format(n);

// Texte de récompense d'une mission : « 100 Po », « Potion de vie mineure ×1 », ou les deux.
export function texteRecompense(or, objetNom, quantite, effet = null) {
  const parts = [];
  if (or > 0) parts.push(`${fmt(or)} Po`);
  if (objetNom) parts.push(`${objetNom}${quantite > 1 ? ` ×${quantite}` : ""}`);
  if (effet) parts.push(effet);
  return parts.join(" et ") || "—";
}

// Page des missions : deux rubriques (individuelles = pour le joueur, collectives = pour la compagnie).
// Une récompense « cachée » reste en « ? » tant que la mission n'est pas accomplie.
export function Missions({ missions, attributions, compteurs, objets, userId, onReclamer }) {
  const parRubrique = (r) => missions.filter((m) => m.rubrique === r);
  const attribution = (m) =>
    attributions.find(
      (a) => a.mission_id === m.id && (m.rubrique === "collective" ? a.user_id == null : a.user_id === userId),
    );
  const progression = (m) =>
    compteurs.get(`${m.evenement}:${m.rubrique === "collective" ? "collectif" : userId}`) || 0;
  const carte = (m) => {
    const a = attribution(m);
    const objet = m.recompense_objet_id ? objets.get(m.recompense_objet_id) : null;
    const cachee = m.recompense_cachee && !a;
    const aReclamer = !!a && a.user_id === userId && (a.objet_id || a.effet_stat) && !a.reclamee_le;
    return (
      <li key={m.id} className={`mission-carte${a ? " accomplie" : ""}`}>
        <div className="mission-entete">
          <strong>{m.nom}</strong>
          <span className="mission-statut">
            {a
              ? "Accomplie ✓"
              : m.evenement === "a_brancher"
                ? "En préparation"
                : progression(m) >= m.seuil
                  ? "En attente : donnez d’abord une récompense"
                  : `${Math.min(progression(m), m.seuil)} / ${m.seuil}`}
          </span>
        </div>
        <p>{m.description}</p>
        <p className="mission-recompense">
          Récompense :{" "}
          {cachee ? (
            <em>? (secrète jusqu’à l’accomplissement)</em>
          ) : (
            texteRecompense(
              m.recompense_or,
              objet?.nom,
              m.recompense_quantite,
              m.recompense_effet_stat
                ? libelleEffet(m.recompense_effet_stat, m.recompense_effet_valeur, m.recompense_effet_quetes)
                : null,
            )
          )}
        </p>
        {aReclamer && (
          <button type="button" className="wood-button" onClick={() => onReclamer(a)}>
            Donner la récompense à un mercenaire
          </button>
        )}
      </li>
    );
  };
  return (
    <section className="journal-page parchment missions-page">
      <h2>Missions</h2>
      <p className="muted">
        Une mission s’accomplit toute seule quand l’événement se produit : la récompense arrive
        aussitôt et une fenêtre l’annonce. Vous pouvez avoir au plus 6 récompenses individuelles en attente d’être données à
        un mercenaire : au-delà, les nouvelles missions patientent jusqu’à ce que vous en donniez une.
      </p>
      <h3>Individuelles — un cadeau pour vous</h3>
      <ul className="mission-liste">{parRubrique("individuelle").map(carte)}</ul>
      {!parRubrique("individuelle").length && <p className="muted">Aucune mission pour le moment.</p>}
      <h3>Collectives — un cadeau pour la compagnie</h3>
      <ul className="mission-liste">{parRubrique("collective").map(carte)}</ul>
      {!parRubrique("collective").length && <p className="muted">Aucune mission pour le moment.</p>}
    </section>
  );
}

// Fenêtre « Mission accomplie » : annonce (collective ou or seul) ou remise d'un objet à l'un de SES mercenaires.
export function MissionPopup({ mission, attribution, objet, mercenaires, bloques = new Set(), onClaim, onLater, onClose }) {
  const [busy, setBusy] = useState(false);
  // Mercenaire choisi pour recevoir un effet temporaire : le don est définitif, il demande une confirmation.
  const [confirmer, setConfirmer] = useState(null);
  const aReclamer = !!(attribution.objet_id || attribution.effet_stat) && !attribution.reclamee_le && attribution.user_id;
  async function choisir(id) {
    if (busy) return;
    if (attribution.effet_stat && confirmer !== id) {
      setConfirmer(id);
      return;
    }
    setBusy(true);
    const ok = await onClaim(attribution, id);
    if (!ok) {
      setBusy(false);
      setConfirmer(null);
    }
  }
  return (
    <Modal title="Mission accomplie !" onClose={aReclamer ? onLater : onClose}>
      <p>
        <strong>{mission.nom}</strong>
      </p>
      <p className="muted">{mission.description}</p>
      <p>
        {attribution.user_id ? "Vous avez gagné" : "La compagnie a gagné"} :{" "}
        <strong>
          {texteRecompense(
            attribution.or_verse,
            objet?.nom,
            attribution.quantite,
            attribution.effet_stat
              ? libelleEffet(attribution.effet_stat, attribution.effet_valeur, attribution.effet_quetes)
              : null,
          )}
        </strong>
        {attribution.or_verse > 0 ? " — l’or est versé à la trésorerie" : ""}
        {!attribution.user_id && attribution.objet_id ? " — l’objet est ajouté à l’arsenal" : ""}
      </p>
      {objet?.icone && <img className="db-item-art" src={objet.icone} alt={objet.nom} />}
      {aReclamer && confirmer ? (
        <>
          <p role="alert">
            Donner {attribution.effet_stat ? libelleEffet(attribution.effet_stat, attribution.effet_valeur, attribution.effet_quetes) : ""}
            {attribution.objet_id ? ` et ${objet?.nom || "l’objet"}` : ""} à{" "}
            <strong>{mercenaires.find((m) => m.id === confirmer)?.name}</strong> ?
          </p>
          <p className="muted">
            Ce choix est définitif : l’effet est lié à ce mercenaire, il ne peut pas être transféré ni repris, et il
            disparaît si le mercenaire est renvoyé.
          </p>
          <div className="mission-mercs">
            <button type="button" className="wood-button" disabled={busy} onClick={() => choisir(confirmer)}>
              {busy ? "Envoi…" : "Confirmer"}
            </button>
            <button type="button" className="text-button" disabled={busy} onClick={() => setConfirmer(null)}>
              Choisir un autre mercenaire
            </button>
          </div>
        </>
      ) : aReclamer ? (
        <>
          <p>
            {attribution.effet_stat
              ? `Choisissez le mercenaire qui recevra ${attribution.objet_id ? "l’objet et " : ""}l’effet (utilisable uniquement pendant ${attribution.effet_quetes > 1 && attribution.effet_stat !== "pv_temp" ? `ses ${attribution.effet_quetes} prochaines quêtes` : "sa prochaine quête"}, qu’elle réussisse ou qu’elle échoue ; non transférable) :`
              : "Envoyez-le dans le sac à dos de l’un de vos mercenaires :"}
          </p>
          {mercenaires.length ? (
            <div className="mission-mercs">
              {mercenaires.map((m) => (
                <button
                  key={m.id}
                  type="button"
                  className="wood-button"
                  disabled={busy || (!!attribution.effet_stat && bloques.has(m.id))}
                  title={attribution.effet_stat && bloques.has(m.id) ? "Il a déjà un effet temporaire non dépensé" : undefined}
                  onClick={() => choisir(m.id)}
                >
                  {m.name}
                  {attribution.effet_stat && bloques.has(m.id) ? " (effet déjà en cours)" : ""}
                </button>
              ))}
            </div>
          ) : (
            <p className="muted">Vous n’avez aucun mercenaire pour le moment : revenez plus tard.</p>
          )}
          <button type="button" className="text-button" onClick={onLater}>
            Plus tard
          </button>
        </>
      ) : (
        <button type="button" className="wood-button" onClick={onClose}>
          Fermer
        </button>
      )}
    </Modal>
  );
}
