import { useEffect, useState } from "react";
import { supabase } from "./supabaseClient";
import { VetBadge } from "./VetBadge.jsx";
import { ReferenceCrop } from "./Characters.jsx";
import { ITEMS } from "./data.js";

const REWARD_SLOTS = [0, 1, 2, 3, 4];

// Charge les quêtes, leurs récompenses en objets et le catalogue (pour les
// icônes/noms des récompenses), puis se tient à jour en direct : la sélection
// d'une quête par un joueur, ou sa résolution par l'administrateur au +1
// Instance, doit se refléter chez tout le monde sans recharger la page.
function useQuetes() {
  const [quetes, setQuetes] = useState(null);
  const [recompenses, setRecompenses] = useState(null);
  const [objets, setObjets] = useState(null);
  const [error, setError] = useState("");
  async function reload() {
    const [q, r, o] = await Promise.all([
      supabase.from("quete").select("*").order("nom"),
      supabase.from("quete_recompense").select("*"),
      supabase.from("objet_catalogue").select("id, nom, icone"),
    ]);
    const err = q.error || r.error || o.error;
    if (err) {
      setError(err.message);
      return;
    }
    setError("");
    setQuetes(q.data);
    setRecompenses(r.data);
    setObjets(o.data);
  }
  useEffect(() => {
    reload();
    const canal = supabase
      .channel("quetes-live")
      .on("postgres_changes", { event: "*", schema: "public", table: "quete" }, reload)
      .on("postgres_changes", { event: "*", schema: "public", table: "quete_recompense" }, reload)
      .subscribe();
    return () => supabase.removeChannel(canal);
  }, []);
  return { quetes, recompenses, objets, error };
}

export function Quests({ onInventory, onCampaign, notify = () => {} }) {
  const { quetes, recompenses, objets, error } = useQuetes();
  const [busy, setBusy] = useState(false);

  function objet(id) {
    return objets?.find((o) => o.id === id);
  }
  function recompensesDe(queteId) {
    return (recompenses || [])
      .filter((r) => r.quete_id === queteId)
      .sort((a, b) => a.position - b.position);
  }
  // Une icône de récompense cliquée rappelle simplement ce qu'elle rapporte
  // (les objets/l'or ne rejoignent l'arsenal/la trésorerie qu'au +1 Instance,
  // sur décision de l'administrateur : ce n'est pas une action du joueur).
  function voirRecompense(libelle) {
    notify(libelle);
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
  }

  const visibles = (quetes || []).filter((q) => !q.terminee_le && q.actif !== false);
  const uneEnCours = visibles.some((q) => q.en_cours);

  return (
    <section className="quests-workspace">
      <div className="quest-actions">
        <button onClick={onInventory}>
          <ReferenceCrop crop={[473, 50, 70, 63]} source="quests-page" sourceWidth={604} />
          <span>Arsenal</span>
        </button>
        <button onClick={onCampaign}>
          <ReferenceCrop crop={[551, 49, 49, 64]} source="quests-page" sourceWidth={604} />
          <span>Inventaires de campagne</span>
        </button>
      </div>
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
                </header>
                <VetBadge
                  className="quest-vet"
                  value={q.veterance_requise}
                  aria-label={`Vétérance moyenne requise : ${q.veterance_requise}`}
                />
                <p>{q.description}</p>
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
                        onClick={() => o && voirRecompense(`Récompense : ${o.nom} ×${r.quantite}.`)}
                        aria-label={o ? `${o.nom}, quantité ${r.quantite}` : "Emplacement vide"}
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
                    onClick={() => q.recompense_or && voirRecompense(`Récompense : ${q.recompense_or} Po.`)}
                    aria-label={q.recompense_or ? `${q.recompense_or} pièces d’or` : "Pas de récompense en or"}
                  >
                    {q.recompense_or ? <span>{q.recompense_or} Po</span> : null}
                  </button>
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
