import { useEffect, useState } from "react";
import { supabase } from "./supabaseClient";
import { VetBadge } from "./VetBadge.jsx";
import { Modal } from "./Modal.jsx";
import { ITEMS } from "./data.js";

const REWARD_SLOTS = [0, 1, 2, 3, 4];
// Jusqu’à 6 mercenaires engagés par quête (positions 0 à 5).
const MERC_SLOTS = [0, 1, 2, 3, 4, 5];

// Charge les quêtes, leurs récompenses en objets et le catalogue (pour les
// icônes/noms des récompenses), puis se tient à jour en direct : la sélection
// d'une quête par un joueur, ou sa résolution par l'administrateur au +1
// Instance, doit se refléter chez tout le monde sans recharger la page.
function useQuetes() {
  const [quetes, setQuetes] = useState(null);
  const [recompenses, setRecompenses] = useState(null);
  const [objets, setObjets] = useState(null);
  const [engages, setEngages] = useState([]);
  const [error, setError] = useState("");
  async function reload() {
    const [q, r, o, e] = await Promise.all([
      supabase.from("quete").select("*").order("nom"),
      supabase.from("quete_recompense").select("*"),
      supabase.from("objet_catalogue").select("id, nom, icone, description"),
      supabase.from("quete_mercenaire").select("quete_id, position, mercenaire_id"),
    ]);
    const err = q.error || r.error || o.error || e.error;
    if (err) {
      setError(err.message);
      return;
    }
    setError("");
    setQuetes(q.data);
    setRecompenses(r.data);
    setObjets(o.data);
    setEngages(e.data);
  }
  useEffect(() => {
    reload();
    const canal = supabase
      .channel("quetes-live")
      .on("postgres_changes", { event: "*", schema: "public", table: "quete" }, reload)
      .on("postgres_changes", { event: "*", schema: "public", table: "quete_recompense" }, reload)
      .on("postgres_changes", { event: "*", schema: "public", table: "quete_mercenaire" }, reload)
      .subscribe();
    return () => supabase.removeChannel(canal);
  }, []);
  return { quetes, recompenses, objets, engages, error, reload };
}

// Une case libre de « Mercenaires engagés » ouvre le Dortoir (`onChoisirMercenaire`) :
// on y choisit un mercenaire, puis le bouton « Quête » de sa fiche l'engage.
// `personnes` : tous les mercenaires recrutés, pour afficher ceux qui sont engagés. `mesIds` : ceux que le joueur
// peut retirer de la quête. `onChanged` relit l'état partagé (Dortoir grisé).
export function Quests({
  notify = () => {},
  onChoisirMercenaire = () => {},
  personnes = [],
  mesIds = new Set(),
  estAdmin = false,
  onChanged = () => {},
}) {
  const { quetes, recompenses, objets, engages, error, reload } = useQuetes();
  const [busy, setBusy] = useState(false);
  // Objet dont la fiche (icône, nom, descriptif) est affichée après un clic
  // sur son emplacement de récompense ; null = aucune fiche ouverte.
  const [ficheObjet, setFicheObjet] = useState(null);
  // Fenêtre d'un mercenaire déjà engagé : { queteId, position, mercId } (bouton
  // « Retirer de la quête » = annuler l'ordre).
  const [choixMerc, setChoixMerc] = useState(null);

  function objet(id) {
    return objets?.find((o) => o.id === id);
  }
  function recompensesDe(queteId) {
    return (recompenses || [])
      .filter((r) => r.quete_id === queteId)
      .sort((a, b) => a.position - b.position);
  }
  async function choisir(id) {
    if (busy) return;
    setBusy(true);
    const { error } = await supabase.rpc("quete_choisir", { p_quete: id });
    setBusy(false);
    if (error) notify(error.message);
  }
  async function annuler() {
    if (busy) return;
    setBusy(true);
    const { error } = await supabase.rpc("quete_annuler_choix");
    setBusy(false);
    if (error) notify(error.message);
    else onChanged();
  }
  function engagesDe(queteId) {
    return engages.filter((e) => e.quete_id === queteId);
  }
  function personne(id) {
    return personnes.find((p) => p.id === id);
  }
  async function retirer(mercId) {
    if (busy) return;
    setBusy(true);
    const { error } = await supabase.rpc("quete_retirer", { p_mercenaire: mercId });
    setBusy(false);
    setChoixMerc(null);
    if (error) notify(error.message);
    else {
      await reload();
      onChanged();
    }
  }

  const visibles = (quetes || []).filter((q) => !q.terminee_le && q.actif !== false);
  const uneEnCours = visibles.some((q) => q.en_cours);

  return (
    <section className="quests-workspace">
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      {!quetes ? (
        <p>Chargement…</p>
      ) : (
        <div className="quest-grid">
          {visibles.map((q) => {
            const indisponible = uneEnCours && !q.en_cours;
            const rewards = recompensesDe(q.id);
            const engagesQuete = engagesDe(q.id);
            // Le compteur se décompte une fois la quête choisie (« +1 Instance »).
            const restantes = q.en_cours
              ? (q.instances_restantes ?? q.instances_requises ?? 1)
              : (q.instances_requises ?? 1);
            return (
              <article
                key={q.id}
                className={`quest-card${indisponible ? " quest-indisponible" : ""}${q.en_cours ? " quest-en-cours" : ""}`}
              >
                <header>
                  {q.icone ? (
                    <img className="quest-type-icon" src={q.icone} alt="" />
                  ) : (
                    <span className="quest-type-icon quest-type-icon-vide" aria-hidden="true" />
                  )}
                  <h2>{q.nom}</h2>
                  {/* Nombre d'instances requises : décompté par le bouton
                      « +1 Instance » une fois la quête choisie. */}
                  <div
                    className="quest-instances"
                    role="status"
                    aria-label={`Instances requises : ${restantes}`}
                  >
                    <small>Instances requises</small>
                    <strong>{restantes}</strong>
                  </div>
                </header>
                <VetBadge
                  className="quest-vet"
                  value={q.veterance_requise}
                  aria-label={`Vétérance moyenne requise : ${q.veterance_requise}`}
                />
                <p>{q.description}</p>
                <h3 className="quest-section-title">Récompenses attendues</h3>
                <div className="quest-rewards" aria-label="Récompenses attendues">
                  {REWARD_SLOTS.map((i) => {
                    const r = rewards.find((x) => x.position === i + 1);
                    const o = r && objet(r.objet_id);
                    return (
                      <button
                        type="button"
                        key={i}
                        className="quest-reward-slot"
                        disabled={!o}
                        onClick={() => o && setFicheObjet({ ...o, quantite: r.quantite })}
                        aria-label={o ? `${o.nom}, quantité ${r.quantite} : voir le descriptif` : "Emplacement vide"}
                      >
                        {o?.icone && <img src={o.icone} alt="" />}
                        {r && <span className="quest-reward-qty">×{r.quantite}</span>}
                      </button>
                    );
                  })}
                  <button
                    type="button"
                    className="quest-reward-slot quest-reward-or"
                    disabled={!q.recompense_or}
                    onClick={() => q.recompense_or && notify(`Récompense : ${q.recompense_or} Po.`)}
                    aria-label={q.recompense_or ? `${q.recompense_or} pièces d’or` : "Pas de récompense en or"}
                  >
                    {q.recompense_or ? <span>{q.recompense_or} Po</span> : null}
                  </button>
                </div>
                <h3 className="quest-section-title">
                  Mercenaires engagés pour cette quête
                </h3>
                <div className="quest-mercs" aria-label="Mercenaires engagés pour cette quête">
                  {MERC_SLOTS.map((i) => {
                    const e = engagesQuete.find((x) => x.position === i);
                    const p = e && personne(e.mercenaire_id);
                    return (
                      <button
                        type="button"
                        key={i}
                        className={`quest-merc-slot${e ? " quest-merc-pris" : ""}`}
                        disabled={!q.en_cours}
                        title={
                          q.en_cours
                            ? undefined
                            : "Choisissez d’abord cette quête pour y engager des mercenaires."
                        }
                        onClick={() =>
                          e
                            ? setChoixMerc({ queteId: q.id, position: i, mercId: e.mercenaire_id })
                            : onChoisirMercenaire()
                        }
                        aria-label={
                          e
                            ? `${p?.name || "Mercenaire"} engagé : voir`
                            : `Emplacement ${i + 1} libre : choisir un mercenaire au dortoir`
                        }
                      >
                        {e ? (
                          <>
                            <img src={p?.portrait || "/assets/icons/lock.webp"} alt="" />
                            <span className="quest-merc-nom">{p?.name || "?"}</span>
                          </>
                        ) : (
                          <span className="quest-merc-plus" aria-hidden="true">
                            +
                          </span>
                        )}
                      </button>
                    );
                  })}
                </div>
                {q.en_cours ? (
                  <button type="button" className="wood-button quest-choix" onClick={annuler} disabled={busy}>
                    Annuler le choix
                  </button>
                ) : (
                  <button
                    type="button"
                    className="wood-button quest-choix"
                    onClick={() => choisir(q.id)}
                    disabled={busy || indisponible}
                  >
                    Choisir cette quête
                  </button>
                )}
              </article>
            );
          })}
        </div>
      )}
      {choixMerc && (
        <Modal
          title={personne(choixMerc.mercId)?.name || "Mercenaire engagé"}
          onClose={() => setChoixMerc(null)}
        >
          <p>
            Ce mercenaire est engagé dans cette quête. Il retournera au dortoir à la
            fin de la quête (ou si vous le retirez).
          </p>
          {mesIds.has(choixMerc.mercId) || estAdmin ? (
            <button
              type="button"
              className="primary"
              disabled={busy}
              onClick={() => retirer(choixMerc.mercId)}
            >
              Retirer de la quête
            </button>
          ) : (
            <p className="muted">Seul son recruteur peut le retirer de la quête.</p>
          )}
        </Modal>
      )}
      {ficheObjet && (
        <Modal title={ficheObjet.nom} onClose={() => setFicheObjet(null)}>
          {ficheObjet.icone && <img className="db-item-art" src={ficheObjet.icone} alt={ficheObjet.nom} />}
          <p>{ficheObjet.description || "Description à définir."}</p>
          <p className="muted">Récompense de la quête : ×{ficheObjet.quantite}.</p>
        </Modal>
      )}
    </section>
  );
}
export function CampaignInventory({
  warriors,
  campaign,
  stock,
  onTransfer,
  ItemArt,
}) {
  const [heroId, setHeroId] = useState(warriors[0]?.id || "");
  const [error, setError] = useState("");
  const own = campaign[heroId] || [];
  function transfer(id, direction) {
    const result = onTransfer(heroId, id, direction);
    setError(result?.error || "");
  }
  return (
    <section className="campaign-inventory">
      <label htmlFor="campaign-hero">Mercenaire en campagne</label>
      <select
        id="campaign-hero"
        value={heroId}
        onChange={(e) => {
          setHeroId(e.target.value);
          setError("");
        }}
      >
        {warriors.map((w) => (
          <option key={w.id} value={w.id}>
            {w.name}
          </option>
        ))}
      </select>
      <h3>Inventaire du mercenaire</h3>
      {own.length ? (
        own.map((o) => (
          <div className="inventory-row" key={o.id}>
            <ItemArt item={ITEMS.find((i) => i.id === o.id)} />
            <div>
              <h3>{ITEMS.find((i) => i.id === o.id).name}</h3>
              <small>Quantité : {o.quantity}</small>
            </div>
            <button
              className="wood-button"
              onClick={() => transfer(o.id, "return")}
            >
              Rendre 1
            </button>
          </div>
        ))
      ) : (
        <p>Aucun objet emporté par ce mercenaire.</p>
      )}
      <h3 className="campaign-stock-title">
        Prélever dans l’arsenal de la forteresse
      </h3>
      {stock.length ? (
        stock.map((o) => (
          <div className="inventory-row" key={o.id}>
            <ItemArt item={ITEMS.find((i) => i.id === o.id)} />
            <div>
              <h3>{ITEMS.find((i) => i.id === o.id).name}</h3>
              <small>{o.quantity} disponibles</small>
            </div>
            <button
              className="wood-button"
              onClick={() => transfer(o.id, "take")}
            >
              Emporter 1
            </button>
          </div>
        ))
      ) : (
        <p>L’arsenal de la forteresse est vide.</p>
      )}
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
      <p className="muted">
        Les objets emportés quittent l’arsenal de la forteresse. Les règles de
        vente restent à préciser.
      </p>
    </section>
  );
}
