import { RichText } from "./RichText.jsx";
import { useEffect, useState } from "react";
import { supabase } from "./supabaseClient";
import { Modal } from "./Modal.jsx";
import { ITEMS } from "./data.js";
import { chargerQuetes } from "./etat.js";
import { EtatsBoutons } from "./CreaturesQuete.jsx";

const REWARD_SLOTS = [0, 1, 2, 3, 4];
// Jusqu’à 6 mercenaires engagés par quête (positions 0 à 5).
const MERC_SLOTS = [0, 1, 2, 3, 4, 5];

// Jauge de difficulté (informative, ne bloque rien : le MJ décide à la table). Ratio =
// (somme des vétérances des mercenaires engagés ÷ 4) ÷ FP de la quête ; 1 est le ratio optimal.
// Compteur interne de −10 à +10 (invisible), 0 = ratio 1 = centre de la zone blanche :
// compteur = (ratio − 1) × 10, borné. Rouge (< −3,5) : trop dure ; blanc : autorisée ; vert
// (> +3,33) : trop facile.
// Limites de la zone « adaptée » = les deux onglets fixes de la jauge, au tiers et aux deux tiers de la barre.
const ZONE_BLANCHE = 10 / 3;
export function compteurDifficulte(sommeVeterances, fp) {
  const ratio = sommeVeterances / 4 / Math.max(1, Number(fp) || 1);
  return Math.max(-10, Math.min(10, (ratio - 1) * 10));
}
function zoneDifficulte(compteur) {
  return compteur < -ZONE_BLANCHE ? "dure" : compteur > ZONE_BLANCHE ? "facile" : "equilibree";
}
const TEXTE_ZONE = {
  dure: "Quête trop difficile pour les mercenaires engagés",
  equilibree: "Difficulté adaptée aux mercenaires engagés",
  facile: "Quête trop facile pour les mercenaires engagés",
};
function JaugeDifficulte({ somme, fp }) {
  const compteur = compteurDifficulte(somme, fp);
  const zone = zoneDifficulte(compteur);
  const position = ((compteur + 10) / 20) * 100;
  return (
    <div className="quest-jauge" role="img" aria-label={TEXTE_ZONE[zone]} title={TEXTE_ZONE[zone]}>
      <div className="quest-jauge-barre">
        <span className="quest-jauge-onglet" style={{ left: "33.333%" }} aria-hidden="true" />
        <span className="quest-jauge-onglet" style={{ left: "66.667%" }} aria-hidden="true" />
        <span className="quest-jauge-marqueur" style={{ left: `${position}%` }} />
      </div>
    </div>
  );
}

// Charge les quêtes, leurs récompenses en objets et le catalogue (pour les
// icônes/noms des récompenses), puis se tient à jour en direct : la sélection
// d'une quête par un joueur, ou sa résolution par l'administrateur au +1
// Instance, doit se refléter chez tout le monde sans recharger la page.
function useQuetes(estAdmin) {
  const [scenarios, setScenarios] = useState([]);
  // Créatures en jeu (MJ seul) : onglet + santé, pour le résumé de la quête en cours.
  const [creaturesJeu, setCreaturesJeu] = useState([]);
  // Créatures prévues par quête (catalogue) : visibles du MJ même avant le choix de la quête.
  const [creaturesPrevues, setCreaturesPrevues] = useState([]);
  const [quetes, setQuetes] = useState(null);
  const [recompenses, setRecompenses] = useState(null);
  const [objets, setObjets] = useState(null);
  const [engages, setEngages] = useState([]);
  const [error, setError] = useState("");
  async function reload() {
    const [q, r, o, e] = await Promise.all([
      chargerQuetes(),
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
    // Scénarios (MJ) : table réservée à l'administrateur, jamais demandée pour un joueur.
    if (estAdmin) {
      const s = await supabase.from("quete_scenario").select("quete_id, texte");
      if (!s.error) setScenarios(s.data);
      const c = await supabase
        .from("creature_quete")
        .select("id, quete_id, nom_onglet, sante_actuelle, ordre, creature:creature_id(sante_max)")
        .order("ordre");
      if (!c.error) setCreaturesJeu(c.data);
      const p = await supabase.from("quete_creature").select("quete_id, quantite, creature:creature_id(nom)");
      if (!p.error) setCreaturesPrevues(p.data);
    } else {
      setScenarios([]);
      setCreaturesJeu([]);
      setCreaturesPrevues([]);
    }
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
      .on("postgres_changes", { event: "*", schema: "public", table: "quete_etat" }, reload)
      .on("postgres_changes", { event: "*", schema: "public", table: "quete_recompense" }, reload)
      .on("postgres_changes", { event: "*", schema: "public", table: "quete_mercenaire" }, reload)
      .on("postgres_changes", { event: "*", schema: "public", table: "creature_quete" }, reload)
      .subscribe();
    return () => supabase.removeChannel(canal);
  }, [estAdmin]);
  return { quetes, recompenses, objets, engages, scenarios, creaturesJeu, creaturesPrevues, error, reload };
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
  onDefinirEtat = async () => ({}),
  onIssue = () => {},
  issueBloquee = false,
}) {
  const { quetes, recompenses, objets, engages, scenarios, creaturesJeu, creaturesPrevues, error, reload } = useQuetes(estAdmin);
  const [busy, setBusy] = useState(false);
  // Objet dont la fiche (icône, nom, descriptif) est affichée après un clic
  // sur son emplacement de récompense ; null = aucune fiche ouverte.
  const [ficheObjet, setFicheObjet] = useState(null);
  // Fenêtre d'un mercenaire déjà engagé : { queteId, position, mercId } (bouton
  // « Retirer de la quête » = annuler l'ordre).
  const [choixMerc, setChoixMerc] = useState(null);
  const [etatErreur, setEtatErreur] = useState("");

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
    return !error;
  }
  // Clic sur une case libre de « Mercenaires engagés » : si la quête n'est pas
  // encore choisie elle l'est d'abord (« Annuler le choix » la libère), puis on
  // ouvre le Dortoir pour y choisir le mercenaire.
  async function ouvrirDortoir(q) {
    if (busy) return;
    if (!q.en_cours && !(await choisir(q.id))) return;
    await reload();
    onChanged();
    onChoisirMercenaire();
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
                {/* Facteur de puissance (FP) de la quête, sur la tuile de pierre. */}
                <span
                  className={`quest-fp${String(q.facteur_puissance ?? "").length > 2 ? " quest-fp-long" : ""}`}
                  role="img"
                  aria-label={`Facteur de puissance : ${q.facteur_puissance ?? 1}`}
                  title="Facteur de puissance"
                >
                  {q.facteur_puissance ?? 1}
                </span>
                <p><RichText text={q.description} /></p>
                {estAdmin && scenarios.find((s) => s.quete_id === q.id)?.texte && (
                  <>
                    <h3 className="quest-section-title">Scénario (MJ)</h3>
                    <p className="quest-scenario">
                      <RichText text={scenarios.find((s) => s.quete_id === q.id).texte} />
                    </p>
                  </>
                )}
                {estAdmin && q.en_cours && creaturesJeu.some((c) => c.quete_id === q.id) && (
                  <>
                    <h3 className="quest-section-title">Créatures (MJ)</h3>
                    <div className="quest-creatures-bloc">
                    <ul className="quest-creatures">
                      {creaturesJeu
                        .filter((c) => c.quete_id === q.id)
                        .map((c) => (
                          <li key={c.id}>
                            <a href={`#creatures/${c.id}`}>{c.nom_onglet}</a>
                            <span className={c.sante_actuelle === 0 ? "quest-creature-detruite" : undefined}>
                              {c.sante_actuelle ?? c.creature?.sante_max ?? "?"} / {c.creature?.sante_max ?? "?"} PV
                            </span>
                          </li>
                        ))}
                    </ul>
                    <a className="wood-button quest-creatures-bouton" href="#creatures">
                      Ouvrir les fiches
                    </a>
                    </div>
                  </>
                )}
                {estAdmin &&
                  !(q.en_cours && creaturesJeu.some((c) => c.quete_id === q.id)) &&
                  creaturesPrevues.some((c) => c.quete_id === q.id) && (
                    <>
                      <h3 className="quest-section-title">Créatures prévues (MJ)</h3>
                      <div className="quest-creatures-bloc">
                      <ul className="quest-creatures">
                        {creaturesPrevues
                          .filter((c) => c.quete_id === q.id)
                          .map((c, i) => (
                            <li key={i}>
                              <span>{c.creature?.nom || "?"}</span>
                              <span>×{c.quantite}</span>
                            </li>
                          ))}
                      </ul>
                      <a className="wood-button quest-creatures-bouton" href={"#creatures/quete/" + q.id}>
                        Voir les fiches
                      </a>
                      </div>
                    </>
                  )}
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
                        onClick={() => o && setFicheObjet({ ...o, quantite: r.quantite, materiau: r.materiau })}
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
                        disabled={indisponible}
                        title={
                          indisponible
                            ? "Une autre quête est en cours : annulez-la d’abord."
                            : e || q.en_cours
                              ? undefined
                              : "Choisit cette quête et ouvre la caserne."
                        }
                        onClick={() =>
                          e
                            ? setChoixMerc({ queteId: q.id, position: i, mercId: e.mercenaire_id })
                            : ouvrirDortoir(q)
                        }
                        aria-label={
                          e
                            ? `${p?.name || "Mercenaire"} engagé : voir`
                            : `Emplacement ${i + 1} libre : choisir un mercenaire à la caserne`
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
                {q.en_cours && (
                  <JaugeDifficulte
                    fp={q.facteur_puissance}
                    somme={engagesQuete.reduce((t, e) => t + (personne(e.mercenaire_id)?.veterancy ?? 0), 0)}
                  />
                )}
                {q.en_cours && estAdmin && (
                  <div className="quest-issue" role="group" aria-label="Issue de la quête (MJ)">
                    <button type="button" className="quest-issue-btn quest-issue-echec" onClick={() => onIssue("echec")} disabled={busy || issueBloquee}
                      title="La quête échoue : l’instance avance de 1, aucune récompense, la quête redevient disponible.">
                      Échec
                    </button>
                    <button type="button" className="quest-issue-btn quest-issue-reussite" onClick={() => onIssue("reussite")} disabled={busy || issueBloquee}
                      title="+1 Instance : la quête avance, et est accomplie quand le compteur arrive à 0.">
                      Réussite
                    </button>
                  </div>
                )}
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
            Ce mercenaire est engagé dans cette quête. Il retournera à la caserne à la
            fin de la quête (ou si vous le retirez).
          </p>
          {(() => {
            const p = personne(choixMerc.mercId);
            const peutModifier = mesIds.has(choixMerc.mercId) || estAdmin;
            const appliquer = async (...args) => {
              const r = await onDefinirEtat(choixMerc.mercId, ...args);
              setEtatErreur(r?.error || "");
            };
            return (
              <div className="merc-etats">
                <h4 className="creature-section">État en quête</h4>
                <EtatsBoutons
                  etat={p?.etat ?? null}
                  niveau={p?.etatNiveau ?? 1}
                  rounds={p?.etatRounds ?? 0}
                  desactive={!peutModifier}
                  onEtat={(e) => (p?.etat === e.id ? appliquer(null) : appliquer(e.id, 1, 0))}
                  onNiveau={(n) => appliquer("epuise", n, p?.etatRounds ?? 0)}
                  onRounds={(n) => appliquer(p?.etat, p?.etat === "epuise" ? p?.etatNiveau ?? 1 : 1, n)}
                />
                {etatErreur && (
                  <p className="error" role="alert">
                    {etatErreur}
                  </p>
                )}
              </div>
            );
          })()}
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
          <p><RichText text={ficheObjet.description || "Description à définir."} /></p>
          {ficheObjet.materiau && (
            <p>
              <strong>Matériau concerné : {{ bois: "Bois", fer: "Fer", cuir: "Cuir" }[ficheObjet.materiau] || ficheObjet.materiau}</strong>
            </p>
          )}
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
