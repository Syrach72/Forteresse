import { useState, useEffect, useRef, useMemo } from "react";
import { ASSETS, LOCATIONS, CLASSES, ITEMS } from "./data";
import { initialGame, transact, undoLast, RESOURCE_ALIASES, materialQuantity, ingredientQuantity, sellableValue } from "./game";
import { Market } from "./Market.jsx";
import { Quests, CampaignInventory } from "./Quests.jsx";
import { Treasury } from "./Treasury.jsx";
import { INITIAL_TREASURY, changeTreasury } from "./treasury-data.js";
import { Training } from "./Training.jsx";
import {
  INITIAL_TRAINING,
  buildTraining,
  trainingIds,
} from "./training-data.js";
import { Characters } from "./Characters.jsx";
import { Infirmary } from "./Infirmary.jsx";
import { Dortoir } from "./Dortoir.jsx";
import {
  INITIAL_DORMITORY,
  INITIAL_INFIRMARY,
  SOINS_INSTANCES,
  buildInfirmary,
  firstFreeBed,
  syncRecruits,
} from "./dormitory";
import { CHARACTER_CLASSES } from "./characters";
import { Admin } from "./Admin.jsx";
import { supabase } from "./supabaseClient";
const money = (n) => new Intl.NumberFormat("fr-FR").format(n);
const BACKDROP_VIDEO = {
  alchimie: "/assets/video/alchimiste-anime2.mp4",
  mage: "/assets/video/mage-test.mp4",
  forge: "/assets/video/forge-anim.mp4",
  armurerie: "/assets/video/armurerie-animee.mp4",
  infirmerie: "/assets/video/infirmerie-animee.mp4",
  entrainement: "/assets/video/entrainement-anime.mp4",
  marche: "/assets/video/marche-anime.mp4",
  tresorerie: "/assets/video/tresorerie-anime.mp4",
  dortoirs: "/assets/video/dortoir-anime.mp4",
};
const BACKDROP_VIDEO_RATIO = {
  forge: "1 / 1",
  armurerie: "1 / 1",
  infirmerie: "1 / 1",
  dortoirs: "1 / 1",
  entrainement: "1 / 1",
  tresorerie: "1 / 1",
};
const WORKSHOP_TEXT = {
  forge: {
    eyebrow: "Le feu donne forme",
    destination: "à la forge",
    catalogue: "Catalogue des armes",
  },
  armurerie: {
    eyebrow: "À l’abri de l’acier",
    destination: "à l’armurerie",
    catalogue: "Catalogue des armures",
  },
  alchimie: {
    eyebrow: "Les alambics s’éveillent",
    destination: "au laboratoire",
    catalogue: "Catalogue des produits alchimiques",
  },
  mage: {
    eyebrow: "L’arcane prend forme",
    destination: "à la tour du mage",
    catalogue: "Catalogue des gemmes",
  },
};
const BACKDROP_LOOP_FADE = 1.1;
// Vidéos qui ne bouclent pas (la caméra recule : première et dernière image
// très différentes). Un fondu enchaîné y superpose deux capuches ; on fait donc
// un fondu par le noir (sortie puis entrée, en secondes) : aucun dédoublement.
const BACKDROP_VIDEO_DIP = { alchimie: 0.4 };
// Vitesse de lecture (1 = normale) : le Laboratoire est ralenti.
const BACKDROP_VIDEO_RATE = { alchimie: 0.6 };
function BackdropVideo({ src, ratio, dip, rate = 1 }) {
  const ref1 = useRef(null);
  const ref2 = useRef(null);
  useEffect(() => {
    const a = ref1.current;
    const b = ref2.current;
    if (!a || !b) return;
    if (dip) {
      // Une seule vidéo (lecture en boucle native) ; son opacité descend à 0
      // avant la fin et remonte après le redémarrage, sur le fond noir de la page.
      b.pause();
      b.style.opacity = 0;
      a.loop = true;
      a.defaultPlaybackRate = rate;
      a.playbackRate = rate;
      // Durée du fondu en secondes réelles : le temps média passe `rate` fois
      // moins vite quand la lecture est ralentie.
      const dipMedia = dip * rate;
      a.style.opacity = 0;
      a.play().catch(() => {});
      let rafDip;
      const tickDip = () => {
        if (a.paused) a.play().catch(() => {});
        if (a.duration) {
          const t = a.currentTime;
          a.style.opacity = Math.max(0, Math.min(1, t / dipMedia, (a.duration - t) / dipMedia));
        }
        rafDip = requestAnimationFrame(tickDip);
      };
      rafDip = requestAnimationFrame(tickDip);
      return () => {
        cancelAnimationFrame(rafDip);
        a.loop = false;
      };
    }
    // Fondu de boucle : "a" (dessous) reste toujours opaque, seul "b" (dessus)
    // change d'opacité. Fondre les deux en même temps les rendrait
    // semi-transparentes et laisserait transparaître le fond statique (autre
    // teinte, absent hors de la carte) : bande de teinte à chaque boucle. On ne
    // touche pas à l'ordre d'empilement (z-index) : un calque passé derrière le
    // fond de la carte disparaîtrait au profit de l'image fixe.
    //  - mode "in"  : "a" joue, "b" apparaît par-dessus (0 → 1) en fin de boucle ;
    //  - mode "out" : "b" joue, "a" repart de 0 dessous et "b" disparaît (1 → 0).
    a.style.opacity = 1;
    b.style.opacity = 0;
    let mode = "in";
    let crossfading = false;
    let raf;
    const safePlay = (video) => {
      video.play().catch(() => {});
    };
    safePlay(a);
    const tick = () => {
      const active = mode === "in" ? a : b;
      const next = mode === "in" ? b : a;
      if (active.paused) safePlay(active);
      if (active.duration) {
        const remaining = active.duration - active.currentTime;
        if (remaining <= BACKDROP_LOOP_FADE) {
          if (!crossfading) {
            crossfading = true;
            next.currentTime = 0;
            safePlay(next);
          }
          const t = Math.min(1, Math.max(0, 1 - remaining / BACKDROP_LOOP_FADE));
          b.style.opacity = mode === "in" ? t : 1 - t;
          if (remaining <= 0.02) {
            active.pause();
            mode = mode === "in" ? "out" : "in";
            b.style.opacity = mode === "out" ? 1 : 0;
            crossfading = false;
          }
        } else {
          b.style.opacity = mode === "in" ? 0 : 1;
        }
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [src, ratio, dip, rate]);
  const className = `interior-backdrop${ratio ? " interior-backdrop-boxed" : ""}`;
  const style = ratio ? { aspectRatio: ratio } : undefined;
  return (
    <>
      <video ref={ref1} className={className} style={style} src={src} muted playsInline />
      <video ref={ref2} className={className} style={style} src={src} muted playsInline />
    </>
  );
}
function Sprite({ location, className = "" }) {
  const l =
    typeof location === "string"
      ? LOCATIONS.find((x) => x.id === location)
      : location;
  if (l?.id === "quetes")
    return (
      <span className={`sprite asset-sprite ${className}`} aria-hidden="true">
        <img src="/assets/references/quests.png" alt="" />
      </span>
    );
  if (!l?.icon) return null;
  const assetId = l.id === "alchimie" ? "magic-items" : l.id;
  if (assetId !== "quetes") return (
    <span className={`sprite asset-sprite ${className}`} aria-hidden="true">
      <img src={`/assets/icons/${assetId}.png`} alt="" />
    </span>
  );
  const [x, y, w, h] = l.icon;
  return (
    <span
      className={`sprite ${className}`}
      aria-hidden="true"
      style={{ aspectRatio: `${w}/${h}` }}
    >
      <img
        src="/assets/references/castle.png"
        alt=""
        style={{
          width: `${(756 / w) * 100}%`,
          maxWidth: "none",
          left: `${(-x / w) * 100}%`,
          top: `${(-y / h) * 100}%`,
        }}
      />
    </span>
  );
}
function ItemArt({ item }) {
  if (!item.crop) return <Sprite location={item.icon} />;
  const [x, y, w, h] = item.crop;
  const dims = item.source === "armory" ? [719, 627] : [859, 571];
  return (
    <span className="item-art" style={{ aspectRatio: `${w}/${h}` }}>
      <img
        src={ASSETS[item.source]}
        alt={item.name}
        style={{
          width: `${(dims[0] / w) * 100}%`,
          maxWidth: "none",
          left: `${(-x / w) * 100}%`,
          top: `${(-y / h) * 100}%`,
        }}
      />
    </span>
  );
}
// Affichage d'une ligne d'inventaire (game.inventory), qu'elle vienne de la
// démo locale (ITEMS) ou d'un objet du catalogue Supabase fabriqué via
// craft-catalogue (id "catalogue:<uuid>", nom/icone stockés directement sur
// la ligne car absents de ITEMS) : une seule source pour l'Arsenal, la
// modale Inventaire et la fiche d'un objet, pour ne pas laisser l'un d'eux
// planter ou afficher un objet vide faute de correspondance dans ITEMS.
function inventoryItemInfo(own) {
  const legacy = ITEMS.find((x) => x.id === own.id);
  return {
    legacy,
    name: legacy?.name || own.nom || "Objet",
    art: legacy ? (
      <ItemArt item={legacy} />
    ) : (
      <span className="item-art">
        {own.icone && <img src={own.icone} alt="" />}
      </span>
    ),
  };
}
// Onglets de l'Arsenal : reprennent les categories racines du catalogue
// admin (Armes, Armures, Gemmes, Ingredients, Materiaux, Objet divers,
// Produits Alchimiques), avec les libelles demandes par Bruno. "Divers"
// recoit aussi tout objet dont la categorie n'est pas encore reconnue,
// plutot que de le faire disparaitre silencieusement d'un onglet.
const ARSENAL_TABS = [
  "Général",
  "Armes",
  "Armures",
  "Composants",
  "Matériaux",
  "Produits Alchimiques",
  "Gemmes",
  "Divers",
];
const CATEGORY_TAB_LABELS = {
  Armes: "Armes",
  Armures: "Armures",
  Gemmes: "Gemmes",
  Composants: "Composants",
  Ingrédients: "Composants",
  Matériaux: "Matériaux",
  "Objet divers": "Divers",
  "Produits Alchimiques": "Produits Alchimiques",
};
// Types du catalogue local de demonstration (data.js) : les « Formules »
// (sorts de demo, jamais reellement produites par le jeu actuel) n'ont pas
// d'equivalent parmi les categories du catalogue admin, d'ou Divers.
const LEGACY_TYPE_TAB_LABELS = {
  Armes: "Armes",
  Armures: "Armures",
  Potions: "Produits Alchimiques",
  Formules: "Divers",
};
function arsenalCategoryOf(own) {
  const legacy = ITEMS.find((x) => x.id === own.id);
  if (legacy) return LEGACY_TYPE_TAB_LABELS[legacy.type] || "Divers";
  return CATEGORY_TAB_LABELS[own.categorie] || "Divers";
}
// Fiche d'un objet de l'arsenal (bouton « Inventaire », ou case cliquée
// dans la grille Arsenal) : image, quantité, et les 3 actions à venir
// (équiper/vendre/détruire, cf. commentaire plus bas). Composant à part,
// avec son propre état de quantité à prélever, pour que ce champ reparte
// à 1 à chaque nouvel objet ouvert (clé = id de l'objet côté appelant).
function ItemActionPanel({ game, id, onSell, onDestroy, busy, error }) {
  const [qty, setQty] = useState(1);
  const [confirmDestroy, setConfirmDestroy] = useState(false);
  const own = game.inventory.find((i) => i.id === id);
  if (!own) return <p>Cet objet n’est plus dans l’arsenal.</p>;
  const { art } = inventoryItemInfo(own);
  const valeur = sellableValue(own);
  const gain = valeur === null ? null : Math.floor((valeur * qty) / 2);
  return (
    <>
      <div className="item-detail-art">{art}</div>
      <p>
        Quantité : {own.quantity}
        {own.equipped ? " · Équipé" : ""}
      </p>
      {/* Équiper reste inerte : Bruno donnera la règle d'emplacement
          d'équipement avant de le brancher. La vente au Marché (moitié de la
          valeur) et la destruction (avec confirmation Oui/Non) sont actives. */}
      <div className="item-detail-actions">
        <div className="item-detail-equip">
          <button className="wood-button" disabled title="Bientôt disponible">
            Équiper
          </button>
          <label className="item-detail-qty">
            Nombre à prélever
            <input
              type="number"
              min="1"
              max={own.quantity}
              value={qty}
              onChange={(e) => {
                const n = Math.round(Number(e.target.value));
                setQty(
                  Number.isFinite(n) ? Math.min(Math.max(n, 1), own.quantity) : 1,
                );
                setConfirmDestroy(false);
              }}
            />
          </label>
        </div>
        <button
          className="wood-button"
          disabled={busy || gain === null || own.equipped || confirmDestroy}
          title={
            gain === null
              ? "Valeur non définie : vente impossible"
              : `Vendre pour ${gain} Po (moitié de la valeur)`
          }
          onClick={() => onSell(own.id, qty)}
        >
          Vendre
        </button>
        <button
          className="wood-button"
          disabled={busy || own.equipped || confirmDestroy}
          title={own.equipped ? "Rangez d’abord cet objet équipé" : "Détruire définitivement"}
          onClick={() => setConfirmDestroy(true)}
        >
          Détruire
        </button>
      </div>
      {confirmDestroy && (
        <div className="item-destroy-confirm" role="alertdialog" aria-label="Confirmer la destruction">
          <p>
            Détruire définitivement {qty} × {inventoryItemInfo(own).name} ? Cette action est
            irréversible.
          </p>
          <div className="item-destroy-actions">
            <button
              className="wood-button"
              disabled={busy}
              onClick={() => onDestroy(own.id, qty)}
            >
              Oui
            </button>
            <button
              className="wood-button"
              disabled={busy}
              onClick={() => setConfirmDestroy(false)}
            >
              Non
            </button>
          </div>
        </div>
      )}
      <p className="muted">
        {gain === null
          ? "Valeur non définie : cet objet ne peut pas être vendu au Marché."
          : `Vente au Marché : ${gain} Po pour ${qty} (moitié de la valeur, ${valeur} Po pièce).`}
      </p>
      {error && (
        <p role="alert" className="error">
          {error}
        </p>
      )}
    </>
  );
}
// Statistiques de combat d'une fiche : vétérance (armes et armures
// seulement), puis portée (armes et produits alchimiques) ou protection, type
// et malus (armures, boucliers exclus, cf. loadCatalogue > estArmure) — mêmes
// règles que l'admin.
function CombatStats({ item }) {
  return (
    <>
      {/* Pas de vétérance sur un bouclier, un produit alchimique, un
          matériau, un composant ni une gemme. */}
      {(item.estArme || item.estArmure) && !item.estBouclier && (
        <div className="stat-line">
          <span>Vétérance requise</span>
          <strong>{item.veterance_requise ?? "à définir"}</strong>
        </div>
      )}
      {item.estArmure ? (
        <>
          <div className="stat-line">
            <span>Protection</span>
            <strong>{item.protection || "à définir"}</strong>
          </div>
          <div className="stat-line">
            <span>Type</span>
            <strong>{item.type_armure || "à définir"}</strong>
          </div>
          {/* Malus renseignés seulement : une armure sans malus n'affiche rien. */}
          {item.malus_discretion != null && (
            <div className="stat-line">
              <span>Discrétion</span>
              <strong>{item.malus_discretion}</strong>
            </div>
          )}
          {item.malus_vitesse != null && (
            <div className="stat-line">
              <span>Vitesse</span>
              <strong>{item.malus_vitesse}</strong>
            </div>
          )}
        </>
      ) : item.estBouclier ? (
        // Bouclier : pas de portée, mais une parade et des malus (ceux-ci
        // seulement s'ils sont renseignés).
        <>
          <div className="stat-line">
            <span>Parade</span>
            <strong>{item.parade || "à définir"}</strong>
          </div>
          {item.malus_discretion != null && (
            <div className="stat-line">
              <span>Discrétion</span>
              <strong>{item.malus_discretion}</strong>
            </div>
          )}
          {item.malus_vitesse != null && (
            <div className="stat-line">
              <span>Vitesse</span>
              <strong>{item.malus_vitesse}</strong>
            </div>
          )}
          {item.malus_esquive != null && (
            <div className="stat-line">
              <span>Esquive</span>
              <strong>{item.malus_esquive}</strong>
            </div>
          )}
        </>
      ) : (
        <>
          {/* Portée : armes et produits alchimiques seulement. */}
          {(item.estArme || item.estAlchimique) && (
            <div className="stat-line">
              <span>Portée</span>
              <strong>{item.portee || "à définir"}</strong>
            </div>
          )}
          {/* Armes : allonge et type de dégâts, seulement s'ils sont renseignés. */}
          {item.estArme && item.allonge && (
            <div className="stat-line">
              <span>Allonge</span>
              <strong>{item.allonge}</strong>
            </div>
          )}
          {item.estArme && item.type_degats && (
            <div className="stat-line">
              <span>Type de dégâts</span>
              <strong>{item.type_degats}</strong>
            </div>
          )}
        </>
      )}
    </>
  );
}
// Fiche d'un objet réel du catalogue Supabase, unique pour le Marché, les
// ateliers (Forge/Armurerie/Laboratoire/Tour du Mage) et le Catalogue global :
// image, description, statistiques, puis « Acheter » si l'objet a un coût
// d'achat et « Fabriquer » s'il a une recette (chaque bouton suit les
// données). Lecture seule : rien ne s'y modifie, seule l'administration
// écrit le catalogue. Chaque ingrédient est débité de game.inventory par son
// nom (voir ingredientQuantity, game.js) ; un stock, un solde ou un atelier
// indisponible désactive le bouton avec sa raison plutôt que d'agir.
// `context` : "market" (Marché : la fiche montre toujours Acheter, même sans
// coût défini), "atelier" (toujours Fabriquer, même sans recette), "global"
// (uniquement ce qui est réellement disponible). `undo` = dernière opération
// annulable faite sur cette fiche ; elle disparaît dès qu'on la quitte.
function CatalogueItemDetail({
  item,
  game,
  busy,
  context = "atelier",
  actionLabel = "Fabriquer",
  route,
  onBuy,
  onCraft,
  onCollect,
  undo,
  onUndo,
}) {
  const cout = item.cout_achat_or;
  const coutDefini = cout !== null && cout !== undefined;
  const needs = item.ingredientsList;
  const showBuy = coutDefini || context === "market";
  const showCraft = needs.length > 0 || context === "atelier";
  const soldeInsuffisant = coutDefini && game.gold < cout;
  const lacking = needs.some((ing) => ingredientQuantity(game.inventory, ing.nom) < ing.quantite);
  // Fabrication en attente dans l'atelier de cet objet : la Durée d'instance
  // décompte via le bouton +1 Instance. À 0, elle n'est PAS livrée toute
  // seule : « Envoyer à l'Arsenal » libère l'atelier. Un atelier occupé par
  // un AUTRE objet bloque la fabrication de celui-ci.
  const queued = route ? game.craftingQueue?.[route] : null;
  const queuedId = queued && typeof queued === "object" ? queued.id : queued;
  const queuedHere = !!queued && queuedId === item.id;
  const autreEnCours = !!queued && !queuedHere;
  const autreNom =
    queued && typeof queued === "object"
      ? queued.nom
      : ITEMS.find((i) => i.id === queued)?.name || "un autre objet";
  const remaining = game.durations?.[route] ?? item.duree_fabrication_instances ?? 0;
  const readyHere = queuedHere && remaining === 0;
  return (
    <>
      {item.icone && (
        <img className="db-item-art" src={item.icone} alt={item.nom} />
      )}
      <h2>{item.nom}</h2>
      <p>{item.description || "Description à définir."}</p>
      <CombatStats item={item} />
      {showBuy && (
        <div className="stat-line">
          <span>Coût d’achat</span>
          <strong>{coutDefini ? `${cout} Po` : "à définir"}</strong>
        </div>
      )}
      {showCraft && (
        <>
          <div className="workshop-duration">
            <label>Temps de fabrication (instances)</label>
            <strong>
              {queuedHere
                ? remaining
                : (item.duree_fabrication_instances ?? "à définir")}
            </strong>
          </div>
          <h3>{item.atelier === "alchimie" ? "Composants" : "Ressources nécessaires"}</h3>
          {needs.length ? (
            <div className="materials">
              {needs.map((ing) => (
                <div key={ing.nom}>
                  <span>{ing.nom}</span>
                  <strong>{ing.quantite}</strong>
                  <small>Stock : {ingredientQuantity(game.inventory, ing.nom)}</small>
                </div>
              ))}
            </div>
          ) : (
            <p className="muted">Recette à définir.</p>
          )}
        </>
      )}
      <div className="market-buy-actions">
        {showBuy && (
          <button
            className="primary"
            type="button"
            disabled={busy || !coutDefini || soldeInsuffisant}
            onClick={() => onBuy(item)}
          >
            {busy ? "Achat…" : coutDefini ? `Acheter · ${cout} Po` : "Acheter"}
          </button>
        )}
        {showCraft && (
          <button
            className="primary"
            type="button"
            disabled={
              busy ||
              autreEnCours ||
              (queuedHere && !readyHere) ||
              (!queuedHere && (!needs.length || lacking))
            }
            onClick={() => (readyHere ? onCollect() : onCraft(item))}
          >
            {busy
              ? "Fabrication…"
              : readyHere
                ? "Envoyer à l’Arsenal"
                : queuedHere
                  ? "Fabrication en cours…"
                  : autreEnCours
                    ? "Atelier occupé"
                    : actionLabel}
          </button>
        )}
      </div>
      {undo && (
        <div className="undo-banner" role="status">
          <p>{undo.message}</p>
          <button className="text-button" type="button" disabled={busy} onClick={onUndo}>
            {undo.kind === "buy" ? "Annuler l’achat" : "Annuler la fabrication"}
          </button>
          <small>Possible tant que vous n’avez pas quitté cette fiche.</small>
        </div>
      )}
      {showBuy && !coutDefini && (
        <p className="muted">Le coût d’achat n’est pas encore défini : achat impossible.</p>
      )}
      {soldeInsuffisant && (
        <p className="error">Solde insuffisant : {game.gold} Po en trésorerie.</p>
      )}
      {showCraft && lacking && !queuedHere && (
        <p className="error">
          Ressources insuffisantes pour cette fabrication (
          {needs
            .map((ing) => ({
              nom: ing.nom,
              manque: ing.quantite - ingredientQuantity(game.inventory, ing.nom),
            }))
            .filter((m) => m.manque > 0)
            .map((m) => `${m.nom} : ${m.manque} manquant${m.manque > 1 ? "s" : ""}`)
            .join(", ")}
          ).
        </p>
      )}
      {showCraft &&
        (readyHere ? (
          <p className="muted">
            Fabrication terminée : cliquez sur « Envoyer à l’Arsenal » pour
            libérer l’atelier.
          </p>
        ) : queuedHere ? (
          <p className="muted">
            Fabrication en cours : encore {remaining} instance(s) avant de
            pouvoir l’envoyer à l’arsenal.
          </p>
        ) : autreEnCours ? (
          <p className="muted">
            L’atelier est occupé par {autreNom}. Récupérez-le à l’atelier
            avant d’en lancer une autre.
          </p>
        ) : (
          <p className="muted">
            L’objet fabriqué rejoint votre inventaire une fois la durée
            d’instance à 0.
          </p>
        ))}
    </>
  );
}
function Modal({ title, children, onClose }) {
  const ref = useRef(null);
  useEffect(() => {
    const prev = document.activeElement;
    ref.current.showModal();
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prevOverflow;
      prev?.focus();
    };
  }, []);
  return (
    <dialog
      ref={ref}
      onCancel={(e) => {
        e.preventDefault();
        onClose();
      }}
      aria-labelledby="dialog-title"
      className="parchment modal"
    >
      <div className="modal-heading">
        <h2 id="dialog-title">{title}</h2>
        <button className="text-button" onClick={onClose}>
          Fermer
        </button>
      </div>
      {children}
    </dialog>
  );
}
function Auth({ signup, onEnter }) {
  const [errors, setErrors] = useState({});
  const [show, setShow] = useState(false);
  const [busy, setBusy] = useState(false);
  const [serverError, setServerError] = useState("");
  const [pendingConfirmation, setPendingConfirmation] = useState(false);
  async function submit(e) {
    e.preventDefault();
    const f = new FormData(e.currentTarget);
    const email = String(f.get("email")).trim();
    const password = String(f.get("password"));
    const pseudo = signup ? String(f.get("pseudo")).trim() : "";
    // Inscription sur invitation : code remis par l'administrateur (8 lettres
    // ou chiffres, tirets et casse sans importance).
    const invitation = signup
      ? String(f.get("invitation") || "").replace(/[^A-Za-z0-9]/g, "").toUpperCase()
      : "";
    const invalid = {};
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
      invalid.email = "Saisissez une adresse e-mail valide.";
    if (password.length < 8)
      invalid.password = "Utilisez au moins 8 caractères.";
    if (signup && pseudo.length < 2)
      invalid.pseudo = "Saisissez au moins 2 caractères.";
    if (signup && invitation.length !== 8)
      invalid.invitation = "Saisissez le code d’invitation reçu (8 caractères).";
    setErrors(invalid);
    setServerError("");
    if (Object.keys(invalid).length) {
      document.getElementById(Object.keys(invalid)[0]).focus();
      return;
    }
    setBusy(true);
    // Vérification préalable pour un message clair ; le contrôle réel est fait
    // par la base (déclencheur sur la création du compte).
    if (signup) {
      const { data: valide } = await supabase.rpc("invitation_valide", { p_code: invitation });
      if (!valide) {
        setBusy(false);
        setErrors({ invitation: "Code d’invitation invalide ou déjà utilisé." });
        document.getElementById("invitation").focus();
        return;
      }
    }
    const { data, error } = signup
      ? await supabase.auth.signUp({
          email,
          password,
          options: { data: { pseudo, invitation } },
        })
      : await supabase.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (error) {
      setServerError(
        error.message === "Invalid login credentials"
          ? "E-mail ou mot de passe incorrect."
          : error.message === "User already registered"
            ? "Un compte existe déjà avec cet e-mail."
            : /invitation/i.test(error.message)
              ? "Code d’invitation invalide ou déjà utilisé."
              : error.message,
      );
      return;
    }
    if (signup && !data.session) {
      setPendingConfirmation(true);
      return;
    }
    onEnter(
      data.user?.user_metadata?.pseudo ||
        data.user?.email?.split("@")[0] ||
        "Aventurier",
    );
  }
  if (pendingConfirmation) {
    return (
      <main
        className="auth-page"
        style={{ backgroundImage: `url(${ASSETS.login})` }}
      >
        <div className="auth-card parchment">
          <h1>Vérifiez vos e-mails</h1>
          <p className="auth-intro">
            Un lien de confirmation vient de vous être envoyé. Cliquez dessus
            pour activer votre compte, puis connectez-vous.
          </p>
          <a className="primary" href="#connexion">
            Retour à la connexion
          </a>
        </div>
      </main>
    );
  }
  return (
    <main
      className="auth-page"
      style={{ backgroundImage: `url(${ASSETS.login})` }}
    >
      <form className="auth-card parchment" onSubmit={submit} noValidate>
        <h1>{signup ? "Créer un compte" : "Connexion"}</h1>
        {["email", "password", ...(signup ? ["pseudo", "invitation"] : [])].map((name) => (
          <div className="field" key={name}>
            <label htmlFor={name}>
              {name === "email"
                ? "E-mail"
                : name === "password"
                  ? "Mot de passe"
                  : name === "invitation"
                    ? "Code d’invitation"
                    : "Pseudo"}
            </label>
            <div className="input-wrap">
              <input
                id={name}
                name={name}
                type={
                  name === "password"
                    ? show
                      ? "text"
                      : "password"
                    : name === "email"
                      ? "email"
                      : "text"
                }
                autoComplete={
                  name === "password"
                    ? signup
                      ? "new-password"
                      : "current-password"
                    : name === "email"
                      ? "email"
                      : name === "invitation"
                        ? "off"
                        : "nickname"
                }
                placeholder={name === "invitation" ? "XXXX-XXXX" : undefined}
                style={name === "invitation" ? { textTransform: "uppercase" } : undefined}
                aria-invalid={!!errors[name]}
                aria-describedby={
                  errors[name]
                    ? `${name}-error`
                    : name === "password"
                      ? "password-help"
                      : undefined
                }
              />
              {name === "password" && (
                <button
                  type="button"
                  className="reveal"
                  onClick={() => setShow(!show)}
                  aria-label={
                    show
                      ? "Masquer le mot de passe"
                      : "Afficher le mot de passe"
                  }
                >
                  {show ? "Masquer" : "Voir"}
                </button>
              )}
            </div>
            {name === "password" && !errors[name] && (
              <small id="password-help">8 caractères minimum.</small>
            )}
            {name === "invitation" && !errors[name] && (
              <small>Code remis par l’administrateur de la forteresse.</small>
            )}
            {errors[name] && (
              <small className="error" id={`${name}-error`}>
                {errors[name]}
              </small>
            )}
          </div>
        ))}
        {serverError && (
          <p className="admin-error" role="alert">
            {serverError}
          </p>
        )}
        <button className="primary" disabled={busy}>
          {busy
            ? "Entrée en cours…"
            : signup
              ? "Rejoindre la forteresse"
              : "Entrer dans la forteresse"}
        </button>
        <p className="auth-switch">
          {signup ? "Déjà un compte ?" : "Pas encore de compte ?"}{" "}
          <a href={signup ? "#connexion" : "#inscription"}>
            {signup ? "Se connecter" : "Créer un compte"}
          </a>
        </p>
      </form>
    </main>
  );
}
export function App() {
  const [campaign, setCampaign] = useState({});
  const campaignRef = useRef(campaign);
  const [treasury, setTreasury] = useState(() =>
    structuredClone(INITIAL_TREASURY),
  );
  const treasuryRef = useRef(treasury);
  const [training, setTraining] = useState(() =>
    structuredClone(INITIAL_TRAINING),
  );
  const trainingRef = useRef(training);
  const [instanceTicks, setInstanceTicks] = useState(0);
  const [instanceUndo, setInstanceUndo] = useState(null);
  const [infirm, setInfirm] = useState(() =>
    structuredClone(INITIAL_INFIRMARY),
  );
  const infirmRef = useRef(infirm);
  const [dorm, setDorm] = useState(() => structuredClone(INITIAL_DORMITORY));
  const dormRef = useRef(dorm);
  // Mercenaires créés dans Administration > Mercenaires (tables mercenaire et
  // classe) et recrutements (table recrutement). Seuls les mercenaires
  // recrutés par le joueur connecté sont embauchés (un lit au Dortoir) et
  // disponibles ailleurs (liste `warriors` ci-dessous).
  // `mesRecrutes` : identifiant du mercenaire -> nom du joueur saisi sur sa
  // fiche au moment du recrutement (persiste jusqu'au renvoi).
  const [mercenaires, setMercenaires] = useState([]);
  const [mesRecrutes, setMesRecrutes] = useState(() => new Map());
  const [recrutesServeur, setRecrutesServeur] = useState(() => new Set());
  const tousRecrutes = useMemo(
    () => new Set([...recrutesServeur, ...mesRecrutes.keys()]),
    [recrutesServeur, mesRecrutes],
  );
  const warriors = useMemo(
    () =>
      mercenaires
        .filter((m) => mesRecrutes.has(m.id))
        .map((m) => ({
          id: m.id,
          name: m.nom,
          role: m.classe,
          portrait: m.portrait || "/assets/icons/lock.png",
          veterancy: m.veterance ?? 0,
          player: mesRecrutes.get(m.id) || "",
          notes: "",
        })),
    [mercenaires, mesRecrutes],
  );
  // Mercenaires recrutés qui ne sont pas au dortoir (ils y gardent leur lit,
  // affiché grisé) : identifiant -> où ils sont. Renvoyer de la compagnie est
  // le seul cas où le lit se libère.
  const absences = useMemo(() => {
    const m = {};
    if (training.instructor) m[training.instructor.heroId] = "Instructeur";
    for (const s of training.students)
      if (s) m[s.heroId] = "À l’entraînement";
    for (const b of infirm.beds) if (b) m[b.heroId] = "À l’infirmerie";
    return m;
  }, [training, infirm]);
  // Un lit du Dortoir par mercenaire recruté : à chaque changement des
  // recrutements (chargement, recrutement, renvoi), les lits suivent.
  useEffect(() => {
    const next = syncRecruits(dormRef.current, [...mesRecrutes.keys()]);
    dormRef.current = next;
    setDorm(next);
  }, [mesRecrutes, dorm.capacity]);
  const [route, setRoute] = useState(location.hash.slice(1) || "forteresse");
  // Or, arsenal, journal et fabrications sont PARTAGÉS (base de données) : ils
  // arrivent par synchroniserEconomie() ; les valeurs de démonstration locales
  // (905 Po, matériaux, objets de démo) ne sont plus utilisées.
  const [game, setGame] = useState(() => ({
    ...initialGame(),
    gold: 0,
    inventory: [],
    log: [],
  }));
  const [name, setName] = useState("Aldric");
  const [modal, setModal] = useState(null);
  const [toast, setToast] = useState("");
  // null tant qu'aucun joueur n'a explicitement choisi de fabriquer l'objet
  // de demonstration local (Épée longue/Cotte de mailles) : ne se met plus
  // en place tout seul a la simple navigation vers Forge/Armurerie, pour
  // que la case reste vide jusqu'a une veritable commande (cf. actCollect
  // et le rendu du panneau Forge/Armurerie plus bas).
  const [selection, setSelection] = useState(null);
  // Catalogue chargé par atelier (forge/armurerie/alchimie/magie), pour ne
  // recharger qu'une fois par atelier consulté. { [atelier]: { items, error } }
  const [catalogueByAtelier, setCatalogueByAtelier] = useState({});
  const [catalogueTabByAtelier, setCatalogueTabByAtelier] = useState({});
  // Recherche du Catalogue global (bouton de l'en-tête, accessible partout).
  const [globalSearch, setGlobalSearch] = useState("");
  // Achats/fabrications faits depuis la fiche ouverte, annulables tant qu'on
  // ne la quitte pas (cf. undoLast, game.js). Vidée dès que la fiche se
  // ferme, change d'objet ou que la page change.
  const [undoStack, setUndoStack] = useState([]);
  // Objet visé depuis l'admin (bouton « Placer dans la forge » d'une
  // recette) : mémorise quel objet sélectionner une fois arrivé sur la
  // bonne page et son catalogue chargé, avant de s'effacer lui-même.
  const [pendingCraftTarget, setPendingCraftTarget] = useState(null);
  const [filter, setFilter] = useState("Tout");
  const [arsenalTab, setArsenalTab] = useState("Général");
  const [search, setSearch] = useState("");
  const [character, setCharacter] = useState("Guerrier");
  const [actionError, setActionError] = useState("");
  const [busy, setBusy] = useState(false);
  const gameRef = useRef(game);
  const busyRef = useRef(false);
  const timer = useRef();
  const toastTimer = useRef();
  const searchRef = useRef();
  const titleRef = useRef();
  const place = LOCATIONS.find((l) => l.id === route);
  const auth = route === "connexion" || route === "inscription";
  // undefined tant que la session n'a pas encore été vérifiée auprès de
  // Supabase ; null si personne n'est connecté ; l'objet session sinon.
  const [session, setSession] = useState(undefined);
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((_event, s) =>
      setSession(s),
    );
    return () => sub.subscription.unsubscribe();
  }, []);
  // Compte administrateur (affichage uniquement ; les droits réels sont
  // portés par la base, cf. is_admin()).
  const estAdmin = session?.user?.email?.toLowerCase() === "btestart@aol.com";
  // Recharge les mercenaires et les recrutements à la connexion, puis à chaque
  // ouverture d'une page Personnages (pour refléter une création ou un
  // recrutement fait entre-temps).
  const surPagePersonnages = route.startsWith("personnages/");
  useEffect(() => {
    if (!session?.user) return;
    let annule = false;
    (async () => {
      const [{ data: merc, error: e1 }, { data: classes, error: e2 }, rec, tous] =
        await Promise.all([
          supabase.from("mercenaire").select("*").order("nom"),
          supabase.from("classe").select("id, nom"),
          supabase
            .from("recrutement")
            .select("mercenaire_id, user_id, nom_joueur")
            .order("created_at"),
          supabase.rpc("mercenaires_recrutes"),
        ]);
      if (annule || e1 || e2) return;
      const nomClasse = new Map(classes.map((c) => [c.id, c.nom]));
      setMercenaires(
        merc.map((m) => ({
          id: m.id,
          nom: m.nom,
          classe: nomClasse.get(m.classe_id) || "",
          portrait: m.portrait || null,
          veterance: m.veterance ?? 0,
        })),
      );
      // Table absente (migration pas encore appliquée) : on garde les
      // recrutements locaux de la session sans les écraser. Sinon la base fait
      // foi (ordre de recrutement conservé : les lits restent stables).
      if (!rec.error) {
        setMesRecrutes(
          new Map(
            rec.data
              .filter((r) => r.user_id === session.user.id)
              .map((r) => [r.mercenaire_id, r.nom_joueur || ""]),
          ),
        );
      }
      if (!tous.error) setRecrutesServeur(new Set(tous.data));
    })();
    return () => {
      annule = true;
    };
  }, [session?.user?.id, surPagePersonnages]);
  // Recruter un mercenaire : enregistré pour le joueur connecté (un mercenaire
  // ne peut être recruté que par un seul joueur). Sans la table recrutement,
  // repli sur la session en cours. Le mercenaire arrive directement dans le
  // premier lit libre et débloqué du Dortoir ; sans lit disponible, il ne peut
  // pas être recruté.
  async function recruit(m, nomJoueur) {
    if (mesRecrutes.has(m.id)) return;
    const joueur = (nomJoueur || "").trim();
    if (!joueur) {
      notify("Inscrivez votre nom de joueur sur la fiche avant de recruter.");
      return;
    }
    if (firstFreeBed(dormRef.current) < 0) {
      notify(
        `Recrutement impossible : aucun lit libre au Dortoir pour ${m.nom}.`,
      );
      return;
    }
    const { error } = await supabase.from("recrutement").insert({
      mercenaire_id: m.id,
      user_id: session.user.id,
      nom_joueur: joueur,
    });
    const tableAbsente =
      error &&
      (error.code === "PGRST205" ||
        error.code === "42P01" ||
        /does not exist|schema cache/i.test(error.message || ""));
    if (error && error.code === "23505") {
      setRecrutesServeur((old) => new Set([...old, m.id]));
      notify(`${m.nom} a déjà été recruté par un autre joueur.`);
      return;
    }
    if (error && !tableAbsente) {
      notify(`Recrutement impossible : ${error.message}`);
      return;
    }
    // Le lit a pu être pris pendant l'enregistrement : on relit l'état courant
    // et, s'il n'y a plus de place, on annule le recrutement.
    const slot = firstFreeBed(dormRef.current);
    if (slot < 0) {
      if (!tableAbsente)
        await supabase
          .from("recrutement")
          .delete()
          .eq("mercenaire_id", m.id)
          .eq("user_id", session.user.id);
      notify(
        `Recrutement impossible : aucun lit libre au Dortoir pour ${m.nom}.`,
      );
      return;
    }
    // Le lit est attribué par l'effet `syncRecruits` ci-dessus.
    setMesRecrutes((old) => new Map(old).set(m.id, joueur));
    notify(
      `${m.nom} est recruté par ${joueur} et prend place au lit ${slot + 1} du Dortoir${tableAbsente ? " (pour cette session seulement : table de recrutement absente)" : ""}.`,
    );
    // Recrutement réussi : on va directement voir le mercenaire dans son lit.
    location.hash = "dortoirs";
  }
  // Vétérance d'un mercenaire, modifiable par l'administrateur depuis la fiche
  // (la base n'autorise l'écriture sur `mercenaire` qu'à l'admin : is_admin()).
  async function setVeterance(id, value) {
    const n = Number(value);
    if (String(value).trim() === "" || !Number.isInteger(n) || n < 0 || n > 999)
      return { error: "Saisissez un entier de 0 à 999." };
    const { data, error } = await supabase
      .from("mercenaire")
      .update({ veterance: n })
      .eq("id", id)
      .select("id");
    if (error) return { error: error.message };
    if (!data?.length)
      return { error: "Modification refusée : droits administrateur requis." };
    setMercenaires((old) =>
      old.map((m) => (m.id === id ? { ...m, veterance: n } : m)),
    );
    notify(`Vétérance enregistrée : ${n}.`);
    return {};
  }
  // Renvoyer un mercenaire recruté : supprime le recrutement (il redevient
  // recrutable, sa carte est dégrisée sur la page de sa classe) et libère son
  // lit au Dortoir. Sans la table recrutement, repli sur la session en cours.
  // Règle confirmée par Bruno : le mercenaire conserve sa vétérance et tout ce
  // qui est inscrit sur sa fiche. Seule la ligne `recrutement` est supprimée ;
  // la ligne `mercenaire` n'est jamais modifiée ici. Toute donnée de fiche
  // future doit vivre sur le mercenaire, pas sur le recrutement.
  async function dismiss(id) {
    const m = mercenaires.find((x) => x.id === id);
    if (!m || !mesRecrutes.has(id)) return;
    const { error } = await supabase
      .from("recrutement")
      .delete()
      .eq("mercenaire_id", id)
      .eq("user_id", session.user.id);
    const tableAbsente =
      error &&
      (error.code === "PGRST205" ||
        error.code === "42P01" ||
        /does not exist|schema cache/i.test(error.message || ""));
    if (error && !tableAbsente) {
      notify(`Renvoi impossible : ${error.message}`);
      return;
    }
    // Renvoyé de la compagnie, il quitte aussi l'entraînement (avec ses élèves
    // s'il en était l'instructeur) et l'infirmerie : la base s'en charge à la
    // suppression du recrutement.
    synchroniserPartage();
    // Le lit et le nom du joueur disparaissent avec le recrutement (l'effet
    // `syncRecruits` libère le lit).
    setMesRecrutes((old) => {
      const next = new Map(old);
      next.delete(id);
      return next;
    });
    setRecrutesServeur((old) => {
      const next = new Set(old);
      next.delete(id);
      return next;
    });
    notify(
      `${m.nom} est renvoyé : il est de nouveau disponible sur la page ${m.classe || "de sa classe"}.`,
    );
    // Renvoi depuis la fiche : retour au Dortoir, où son lit est maintenant vide.
    location.hash = "dortoirs";
  }
  useEffect(() => {
    if (session === undefined || route === "admin") return;
    if (!session && !auth) location.hash = "connexion";
    if (session && auth) location.hash = "forteresse";
  }, [session, auth, route]);
  useEffect(() => {
    if (session?.user) {
      const pseudo =
        session.user.user_metadata?.pseudo || session.user.email?.split("@")[0];
      if (pseudo) setName(pseudo);
    }
  }, [session]);
  useEffect(() => {
    const handler = () => {
      setRoute(location.hash.slice(1) || "forteresse");
      setModal(null);
      setActionError("");
      window.scrollTo(0, 0);
    };
    window.addEventListener("hashchange", handler);
    return () => window.removeEventListener("hashchange", handler);
  }, []);
  useEffect(() => {
    document.title = `${place?.name || (auth ? (route === "inscription" ? "Créer un compte" : "Connexion") : "Forteresse")} · La Compagnie`;
    titleRef.current?.focus({ preventScroll: true });
    if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      const main = document.querySelector("main");
      const animation = main?.animate(
        [{ opacity: 0.35, transform: "translateY(6px)" }, { opacity: 1, transform: "translateY(0)" }],
        { duration: 220, easing: "cubic-bezier(.2,.7,.2,1)" },
      );
      return () => animation?.cancel();
    }
  }, [route]);
  useEffect(
    () => () => {
      clearTimeout(timer.current);
      clearTimeout(toastTimer.current);
    },
    [],
  );
  // Route de jeu et catégorie racine du catalogue pour chaque atelier
  // (valeurs de l'enum recette.atelier) : sert à faire atterrir le
  // bouton admin « Placer dans la forge » sur la bonne page.
  const ATELIER_ROUTE = { forge: "forge", armurerie: "armurerie", alchimie: "alchimie", magie: "mage" };
  const ATELIER_RACINE = { forge: "Armes", armurerie: "Armures", alchimie: "Produits Alchimiques", magie: "Gemmes" };
  // Quitter la fiche (fermer, retour à la liste, autre objet, autre page)
  // rend définitifs les achats et fabrications qui y ont été faits.
  useEffect(() => {
    setUndoStack([]);
  }, [modal?.type, modal?.detailId, modal?.atelier, route]);
  function sendToForge(objetId, atelier) {
    const targetRoute = ATELIER_ROUTE[atelier];
    if (!targetRoute) return;
    setPendingCraftTarget({ atelier, objetId });
    location.hash = targetRoute;
  }
  useEffect(() => {
    if (!pendingCraftTarget) return;
    const { atelier } = pendingCraftTarget;
    if (route !== ATELIER_ROUTE[atelier]) return;
    loadCatalogue(atelier, ATELIER_RACINE[atelier]);
  }, [pendingCraftTarget, route]);
  useEffect(() => {
    if (!pendingCraftTarget) return;
    const { atelier, objetId } = pendingCraftTarget;
    const targetRoute = ATELIER_ROUTE[atelier];
    if (route !== targetRoute) return;
    const entry = catalogueByAtelier[atelier];
    if (!entry) return;
    setModal({ type: "db-catalogue", atelier, racine: ATELIER_RACINE[atelier], detailId: objetId });
    setPendingCraftTarget(null);
  }, [pendingCraftTarget, route, catalogueByAtelier]);
  function transferCampaign(heroId, id, direction) {
    if (
      !warriors.some((w) => w.id === heroId) ||
      !ITEMS.some((i) => i.id === id)
    )
      return { error: "Mercenaire ou objet inconnu." };
    const fort = structuredClone(gameRef.current.inventory);
    const camp = structuredClone(campaignRef.current);
    const own = camp[heroId] || [];
    const source = direction === "take" ? fort : own;
    const target = direction === "take" ? own : fort;
    const entry = source.find((i) => i.id === id);
    if (!entry || entry.quantity < 1)
      return { error: "Cet objet n’est plus disponible." };
    entry.quantity--;
    const dest = target.find((i) => i.id === id);
    if (dest) dest.quantity++;
    else target.push({ id, quantity: 1, equipped: false });
    camp[heroId] = own.filter((i) => i.quantity > 0);
    const g = {
      ...gameRef.current,
      inventory: fort.filter((i) => i.quantity > 0),
    };
    gameRef.current = g;
    campaignRef.current = camp;
    setGame(g);
    setCampaign(camp);
    notify(
      direction === "take"
        ? "Objet emporté en campagne."
        : "Objet rendu à la forteresse.",
    );
    return { state: camp };
  }
  function updateTreasury(change) {
    const result = changeTreasury(treasuryRef.current, change);
    if (result.error) return result;
    const label =
      change.id === "income"
        ? "Recettes"
        : treasuryRef.current.costs.find((c) => c.id === change.id).label;
    const g = {
      ...gameRef.current,
      gold: gameRef.current.gold + result.delta,
      log: [
        {
          id: crypto.randomUUID(),
          message: `${label} modifié manuellement : ${change.amount} Po.`,
          amount: result.delta,
          date: new Date().toISOString(),
        },
        ...gameRef.current.log,
      ].slice(0, 50),
    };
    treasuryRef.current = result.state;
    gameRef.current = g;
    setTreasury(result.state);
    setGame(g);
    notify("Trésorerie enregistrée. Le solde a été recalculé.");
    return result;
  }
  function setWorkshopDuration(id, value) {
    const n = Number(value);
    if (!Number.isInteger(n) || n < 0 || n > 5) return;
    const next = {
      ...gameRef.current,
      durations: {
        forge: 5,
        armurerie: 3,
        alchimie: 2,
        mage: 0,
        ...gameRef.current.durations,
        [id]: n,
      },
    };
    gameRef.current = next;
    setGame(next);
  }
  const defaultDurations = { forge: 5, armurerie: 3, alchimie: 2, mage: 0 };
  function decreaseInstances() {
    // Le terrain d'entraînement, l'infirmerie et les ateliers (durées des
    // fabrications) sont partagés et écrits en base : `gains` (ce que le
    // serveur a renvoyé) est complété par la file d'opérations et sert à
    // l'annulation. Les lits du Dortoir (embauche) n'ont pas de compteur.
    const undoId = crypto.randomUUID();
    setInstanceUndo({
      id: undoId,
      gains: { entrainement: [], infirmerie: [], ateliers: [] },
    });
    setInstanceTicks((v) => v + 1);
    // Seul l'administrateur fait avancer l'instance (une fois pour tous les
    // joueurs) ; le serveur le revérifie.
    if (estAdmin)
      enqueueTraining(async () => {
        const { gains, erreur } = await runSharedInstance();
        setInstanceUndo((u) => (u?.id === undoId ? { ...u, gains } : u));
        if (erreur) {
          notify(`+1 Instance : ${erreur}`);
          return;
        }
        const nom = (id) =>
          peopleRef.current.find((w) => w.id === id)?.name || "Un mercenaire";
        const phrases = [
          ...gains.entrainement.map((g) =>
            g.gradue
              ? `${nom(g.mercenaire_id)} a rejoint son instructeur (vétérance ${g.a}) et retourne au dortoir.`
              : `${nom(g.mercenaire_id)} passe à la vétérance ${g.a}.`,
          ),
          ...gains.infirmerie
            .filter((g) => g.sorti)
            .map((g) => `${nom(g.mercenaire_id)} est soigné et retrouve sa place au dortoir.`),
          ...gains.ateliers
            .filter((g) => g.a === 0)
            .map((g) => `La fabrication de l'atelier ${g.atelier} est terminée.`),
        ];
        notify(
          phrases.length
            ? `+1 Instance : ${phrases.join(" ")}`
            : "+1 Instance : toutes les Durées d’Instance diminuent de 1, minimum 0.",
        );
      });
  }
  function undoInstanceStep() {
    // Bouton désactivé tant que le +1 Instance n'a pas fini d'être appliqué.
    if (!instanceUndo || trainingPending > 0) return;
    const u = instanceUndo;
    setInstanceTicks((v) => Math.max(0, v - 1));
    setInstanceUndo(null);
    const g = u.gains;
    if (g.entrainement.length || g.infirmerie.length || g.ateliers.length)
      // Niveaux, compteurs et durées sont en base : le serveur les remet comme
      // avant et replace les mercenaires renvoyés au dortoir.
      enqueueTraining(async () => {
        const erreurs = [];
        for (const [fn, gains] of [
          ["entrainement_annuler_instance", g.entrainement],
          ["infirmerie_annuler_instance", g.infirmerie],
          ["ateliers_annuler_instance", g.ateliers],
        ]) {
          if (!gains.length) continue;
          const { error } = await supabase.rpc(fn, { p_gains: gains });
          if (error) erreurs.push(error.message);
        }
        await synchroniserPartage();
        if (erreurs.length) throw new Error(erreurs.join(" "));
      });
    notify("Dernier +1 Instance annulé.");
  }
  // Les opérations d'entraînement du +1 Instance (et son annulation) passent
  // par une file : jamais deux à la fois, même en cas de clics rapides.
  const trainingQueue = useRef(Promise.resolve());
  const [trainingPending, setTrainingPending] = useState(0);
  // Tous les mercenaires de la compagnie (pas seulement ceux du joueur) : le
  // terrain d'entraînement est visible par tous.
  const people = useMemo(
    () =>
      mercenaires.map((m) => ({
        id: m.id,
        name: m.nom,
        role: m.classe,
        portrait: m.portrait || "/assets/icons/lock.png",
        veterancy: m.veterance ?? 0,
      })),
    [mercenaires],
  );
  const peopleRef = useRef(people);
  peopleRef.current = people;
  function enqueueTraining(task) {
    setTrainingPending((n) => n + 1);
    trainingQueue.current = trainingQueue.current
      .then(task)
      .catch((e) =>
        notify(`Entraînement impossible : ${e?.message || "erreur inattendue"}`),
      )
      .finally(() => setTrainingPending((n) => n - 1));
  }
  // Relit l'état partagé : terrain d'entraînement (places, places élèves
  // débloquées), infirmerie (lits occupés, compteurs, lits débloqués) et
  // vétérances (qu'un +1 Instance a pu changer).
  // Cache du catalogue (objets, catégories) pour afficher l'arsenal et les
  // fabrications sans le retélécharger à chaque changement.
  const catalogueCacheRef = useRef({ objets: new Map(), categories: [] });
  // Or de la compagnie, arsenal, journal et fabrications en cours : lus en base
  // et reversés dans `game` (même forme qu'avant, pour l'affichage existant).
  async function synchroniserEconomie() {
    const [etat, inv, lignes, fab, jour] = await Promise.all([
      supabase.from("partie_etat").select("or_compagnie").maybeSingle(),
      supabase.from("inventaire").select("id, type"),
      supabase.from("ligne_inventaire").select("inventaire_id, objet_id, quantite"),
      supabase.from("atelier_fabrication").select("atelier, objet_id, quantite, restant"),
      supabase
        .from("partie_journal")
        .select("id, message, montant, created_at")
        .order("created_at", { ascending: false })
        .limit(50),
    ]);
    if (etat.error || inv.error || lignes.error || fab.error || !etat.data) return;
    const arsenal = inv.data.find((i) => i.type === "arsenal");
    const enStock = lignes.data.filter(
      (l) => l.inventaire_id === arsenal?.id && l.quantite > 0,
    );
    const cache = catalogueCacheRef.current;
    if ([...enStock, ...fab.data].some((x) => !cache.objets.has(x.objet_id))) {
      const [o, c] = await Promise.all([
        supabase.from("objet_catalogue").select("id, nom, icone, categorie_id, cout_achat_or"),
        supabase.from("categorie").select("id, nom, parent_id"),
      ]);
      if (!o.error && !c.error) {
        cache.objets = new Map(o.data.map((x) => [x.id, x]));
        cache.categories = c.data;
      }
    }
    const racine = (categorieId) => {
      let cur = cache.categories.find((c) => c.id === categorieId);
      while (cur?.parent_id)
        cur = cache.categories.find((c) => c.id === cur.parent_id);
      return cur?.nom || null;
    };
    const inventory = [];
    for (const l of enStock) {
      const id = `catalogue:${l.objet_id}`;
      const deja = inventory.find((x) => x.id === id);
      if (deja) {
        deja.quantity += l.quantite;
        continue;
      }
      const o = cache.objets.get(l.objet_id);
      inventory.push({
        id,
        quantity: l.quantite,
        equipped: false,
        nom: o?.nom || "Objet",
        icone: o?.icone || null,
        categorie: o ? racine(o.categorie_id) : null,
        valeur: o?.cout_achat_or ?? null,
      });
    }
    const craftingQueue = {};
    const durations = {};
    for (const x of fab.data) {
      const o = cache.objets.get(x.objet_id);
      craftingQueue[x.atelier] = {
        id: x.objet_id,
        nom: o?.nom || "Objet",
        icone: o?.icone || null,
        categorie: o ? racine(o.categorie_id) : null,
        cout: o?.cout_achat_or ?? null,
      };
      durations[x.atelier] = x.restant;
    }
    const log = (jour.data || []).map((j) => ({
      id: j.id,
      message: j.message,
      amount: j.montant,
      date: j.created_at,
    }));
    const g = {
      ...gameRef.current,
      gold: etat.data.or_compagnie,
      inventory,
      craftingQueue,
      durations,
      log,
    };
    gameRef.current = g;
    setGame(g);
  }
  async function synchroniserPartage() {
    await Promise.all([synchroniserZonesPartagees(), synchroniserEconomie()]);
  }
  async function synchroniserZonesPartagees() {
    const [places, reglage, vet, lits, litsReglage] = await Promise.all([
      supabase.from("entrainement_place").select("role, position, mercenaire_id"),
      supabase.from("entrainement_reglage").select("places_eleves").maybeSingle(),
      supabase.from("mercenaire").select("id, veterance"),
      supabase.from("infirmerie_place").select("position, mercenaire_id, restant"),
      supabase.from("infirmerie_reglage").select("places").maybeSingle(),
    ]);
    if (!lits.error) {
      const next = buildInfirmary(lits.data, litsReglage.data?.places);
      infirmRef.current = next;
      setInfirm(next);
    }
    if (!places.error) {
      const next = buildTraining(places.data, reglage.data?.places_eleves);
      trainingRef.current = next;
      setTraining(next);
    }
    if (!vet.error) {
      const parId = new Map(vet.data.map((m) => [m.id, m.veterance ?? 0]));
      setMercenaires((old) =>
        old.map((m) =>
          parId.has(m.id) && parId.get(m.id) !== m.veterance
            ? { ...m, veterance: parId.get(m.id) }
            : m,
        ),
      );
    }
  }
  // Terrain d'entraînement et infirmerie partagés : chargés à la connexion,
  // puis mis à jour en direct chez tous les joueurs (Supabase Realtime), et à
  // chaque visite des pages Entraînement, Infirmerie et Dortoirs au cas où la
  // connexion en direct serait coupée.
  useEffect(() => {
    if (!session?.user) return;
    synchroniserPartage();
    let attente;
    const rafraichir = () => {
      clearTimeout(attente);
      attente = setTimeout(synchroniserPartage, 150);
    };
    const canal = supabase
      .channel("entrainement-partage")
      .on("postgres_changes", { event: "*", schema: "public", table: "entrainement_place" }, rafraichir)
      .on("postgres_changes", { event: "*", schema: "public", table: "entrainement_reglage" }, rafraichir)
      .on("postgres_changes", { event: "*", schema: "public", table: "infirmerie_place" }, rafraichir)
      .on("postgres_changes", { event: "*", schema: "public", table: "infirmerie_reglage" }, rafraichir)
      .on("postgres_changes", { event: "*", schema: "public", table: "partie_etat" }, rafraichir)
      .on("postgres_changes", { event: "*", schema: "public", table: "partie_journal" }, rafraichir)
      .on("postgres_changes", { event: "*", schema: "public", table: "atelier_fabrication" }, rafraichir)
      .on("postgres_changes", { event: "*", schema: "public", table: "ligne_inventaire" }, rafraichir)
      .on("postgres_changes", { event: "UPDATE", schema: "public", table: "mercenaire" }, rafraichir)
      .subscribe();
    return () => {
      clearTimeout(attente);
      supabase.removeChannel(canal);
    };
  }, [session?.user?.id]);
  useEffect(() => {
    if (session?.user && !auth) synchroniserPartage();
  }, [route, session?.user?.id]);
  // +1 Instance sur les zones partagées (administrateur) : au terrain
  // d'entraînement le serveur fait gagner 1 point de vétérance à chaque élève
  // et renvoie au dortoir celui qui rejoint son instructeur (l'instructeur
  // reste en place) ; à l'infirmerie chaque compteur baisse de 1 et celui qui
  // arrive à 0 retrouve sa place au dortoir ; dans les ateliers chaque durée
  // baisse de 1 (rien n'est livré tout seul : « Envoyer à l'Arsenal »).
  async function runSharedInstance() {
    const t = await supabase.rpc("entrainement_instance");
    const i = await supabase.rpc("infirmerie_instance");
    const a = await supabase.rpc("ateliers_instance");
    await synchroniserPartage();
    const liste = (r) => (Array.isArray(r.data) ? r.data : []);
    return {
      gains: { entrainement: liste(t), infirmerie: liste(i), ateliers: liste(a) },
      erreur: [t.error?.message, i.error?.message, a.error?.message]
        .filter(Boolean)
        .join(" "),
    };
  }
  // Fiche du mercenaire (Dortoir) : bouton « Instructeur ».
  async function chooseInstructor(id) {
    const { error } = await supabase.rpc("entrainement_choisir_instructeur", {
      p_mercenaire: id,
    });
    if (error) {
      notify(error.message);
      return;
    }
    await synchroniserPartage();
    notify(
      `${peopleRef.current.find((w) => w.id === id)?.name} est instructeur au Terrain d’Entraînement.`,
    );
    location.hash = "entrainement";
  }
  // Cellule « Choisir un élève » du terrain d'entraînement.
  async function chooseStudent(index, id) {
    const { error } = await supabase.rpc("entrainement_choisir_eleve", {
      p_position: index,
      p_mercenaire: id,
    });
    if (error) return { error: error.message };
    await synchroniserPartage();
    notify(
      `${peopleRef.current.find((w) => w.id === id)?.name} commence son instruction.`,
    );
    return {};
  }
  // Renvoi au dortoir : `role` "instructor" (avec ses élèves) ou "student".
  // Réservé au recruteur du mercenaire (ou à l'administrateur), vérifié par le
  // serveur. Les niveaux gagnés sont déjà enregistrés : rien n'est perdu.
  async function sendBackToDorm(role, index) {
    const t = trainingRef.current;
    const id = role === "instructor" ? t.instructor?.heroId : t.students[index]?.heroId;
    if (!id) return {};
    const { error } = await supabase.rpc("entrainement_renvoyer", { p_mercenaire: id });
    if (error) return { error: error.message };
    await synchroniserPartage();
    notify(
      `${peopleRef.current.find((w) => w.id === id)?.name} retourne au dortoir${role === "instructor" ? " avec ses élèves" : ""}.`,
    );
    return {};
  }
  async function unlockTraining() {
    if (trainingRef.current.capacity >= 3)
      return { error: "Toutes les places élèves sont ouvertes." };
    const { error } = await supabase.rpc("entrainement_debloquer_place");
    if (error) return { error: error.message };
    await synchroniserPartage();
    notify("Une place élève est débloquée.");
    return {};
  }
  // Fiche du mercenaire (Dortoir) : bouton « Soigner ». Le mercenaire prend le
  // premier lit libre de l'infirmerie pour SOINS_INSTANCES instances, puis
  // retrouve sa place au dortoir (son lit y reste, grisé). Règles vérifiées par
  // le serveur.
  async function healMercenary(id) {
    const { error } = await supabase.rpc("infirmerie_soigner", { p_mercenaire: id });
    if (error) {
      notify(error.message);
      return;
    }
    await synchroniserPartage();
    notify(
      `${peopleRef.current.find((w) => w.id === id)?.name} est en soin à l’infirmerie (${SOINS_INSTANCES} instances).`,
    );
    location.hash = "infirmerie";
  }
  // Rappel au dortoir avant la fin des soins : son recruteur ou l'administrateur.
  async function recallFromInfirmary(id) {
    const { error } = await supabase.rpc("infirmerie_renvoyer", { p_mercenaire: id });
    if (error) return { error: error.message };
    await synchroniserPartage();
    notify(`${peopleRef.current.find((w) => w.id === id)?.name} retourne au dortoir.`);
    return {};
  }
  async function unlockInfirm() {
    if (infirmRef.current.capacity !== 2)
      return { error: "Cet emplacement est déjà débloqué." };
    const { error } = await supabase.rpc("infirmerie_debloquer_place");
    if (error) return { error: error.message };
    await synchroniserPartage();
    notify("Un lit d’infirmerie est débloqué.");
    return {};
  }
  // Le lit du dortoir est encore local à chaque navigateur (bloc suivant du
  // partage) ; sa dépense, elle, est prélevée sur l'or PARTAGÉ.
  async function unlockDorm() {
    if (dormRef.current.capacity !== 6)
      return { error: "Cet emplacement est déjà débloqué." };
    const { error } = await supabase.rpc("partie_depenser", {
      p_montant: 100,
      p_motif: "Emplacement de dortoir débloqué",
    });
    if (error) return { error: error.message };
    const nextDorm = { ...dormRef.current, capacity: 7 };
    dormRef.current = nextDorm;
    setDorm(nextDorm);
    await synchroniserPartage();
    notify("Un nouvel emplacement est débloqué.");
    return { state: nextDorm };
  }
  function notify(message) {
    setToast(message);
    clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(""), 5000);
  }
  function act(type, id, extra) {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setActionError("");
    timer.current = setTimeout(() => {
      const result = transact(gameRef.current, { type, id, ...extra });
      if (result.error) {
        setActionError(result.error);
      } else {
        gameRef.current = result.state;
        setGame(result.state);
        notify(result.message);
      }
      busyRef.current = false;
      setBusy(false);
    }, 280);
  }
  // Opération économique PARTAGÉE : le serveur (fonctions partie_*) fait foi
  // (solde, stock, recette, atelier libre, droits) ; l'affichage est relu
  // ensuite. Renvoie les données de la réponse, ou null si l'opération a
  // échoué (l'erreur est alors affichée).
  async function operationPartagee(appel) {
    if (busyRef.current) return null;
    busyRef.current = true;
    setBusy(true);
    setActionError("");
    try {
      const { data, error } = await appel();
      if (error) {
        setActionError(error.message);
        return null;
      }
      await synchroniserPartage();
      return data ?? {};
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }
  // Identifiant d'objet du catalogue depuis une ligne d'arsenal (`catalogue:<id>`).
  const objetDe = (invId) =>
    typeof invId === "string" && invId.startsWith("catalogue:")
      ? invId.slice("catalogue:".length)
      : null;
  const nomDe = (invId) =>
    gameRef.current.inventory.find((i) => i.id === invId)?.nom || "L’objet";
  // Fabrication d'un objet du catalogue : ingrédients retirés de l'arsenal ;
  // livraison immédiate, ou mise en file dans l'atelier si l'objet a une durée.
  async function actCatalogue(arme) {
    const data = await operationPartagee(() =>
      supabase.rpc("partie_fabriquer", { p_objet: arme.id }),
    );
    if (!data) return;
    // La fiche reste ouverte (fabrication lancée ou livrée tout de suite) pour
    // pouvoir l'annuler ; la fermer la rend définitive.
    setUndoStack((s) => [
      ...s,
      { kind: "craft", journalId: data.journal_id, message: data.message },
    ]);
    notify(data.message);
  }
  // Annule la dernière opération (achat ou fabrication) faite sur la fiche
  // ouverte : opération inverse journalisée par le serveur, refusée si l'objet
  // n'est plus disponible ou si la fabrication a été récupérée.
  async function undoCatalogue() {
    const last = undoStack[undoStack.length - 1];
    if (!last) {
      setActionError("Aucune opération à annuler.");
      return;
    }
    const data = await operationPartagee(() =>
      supabase.rpc("partie_annuler", { p_journal: last.journalId }),
    );
    if (!data) return;
    setUndoStack((s) => s.slice(0, -1));
    notify(data.message);
  }
  // Destruction définitive d'une quantité d'un objet de l'arsenal, après
  // confirmation Oui/Non dans la fiche (ItemActionPanel).
  async function actDestroy(id, quantity) {
    const objet = objetDe(id);
    if (!objet) {
      setActionError("Cet objet ne peut pas être détruit.");
      return;
    }
    const nom = nomDe(id);
    const data = await operationPartagee(() =>
      supabase.rpc("partie_detruire", { p_objet: objet, p_quantite: quantity }),
    );
    if (!data) return;
    setModal(null);
    notify(`Destruction de ${nom} ×${quantity}.`);
  }
  // Vente d'un objet de l'arsenal au Marché : la moitié de sa valeur est
  // créditée à la trésorerie partagée.
  async function actSell(id, quantity) {
    const objet = objetDe(id);
    if (!objet) {
      setActionError("Cet objet ne peut pas être vendu.");
      return;
    }
    const nom = nomDe(id);
    const data = await operationPartagee(() =>
      supabase.rpc("partie_vendre", { p_objet: objet, p_quantite: quantity }),
    );
    if (!data) return;
    setModal(null);
    notify(`Vente de ${nom} ×${quantity} : +${data.gain} Po.`);
  }
  // Achat d'un objet du catalogue depuis le Marché : le coût d'achat est
  // décompté de la trésorerie partagée et l'objet rejoint l'arsenal commun.
  async function actBuyCatalogue(arme) {
    const data = await operationPartagee(() =>
      supabase.rpc("partie_acheter", { p_objet: arme.id }),
    );
    if (!data) return;
    // La fiche reste ouverte : l'achat est annulable tant qu'on ne la quitte pas.
    setUndoStack((s) => [
      ...s,
      { kind: "buy", journalId: data.journal_id, message: "" },
    ]);
    notify(`${arme.nom} acheté : −${arme.cout_achat_or} Po.`);
  }
  // Récupère une fabrication terminée (durée d'instance à 0) : l'objet rejoint
  // l'arsenal et l'atelier est libéré. Referme la fiche de l'objet tout juste
  // livré (il faut retourner au catalogue pour en choisir un autre).
  async function actCollect(route) {
    const data = await operationPartagee(() =>
      supabase.rpc("partie_recuperer", { p_atelier: route }),
    );
    if (!data) return;
    setModal(null);
    // Vide la case locale de démonstration : elle ne doit pas se remettre
    // prête à refabriquer toute seule après la livraison.
    setSelection(null);
    notify(data.message);
  }
  function go(l) {
    if (l.locked) {
      setModal({ type: "locked", place: l });
      return;
    }
    location.hash = l.id;
  }
  // Charge le catalogue Supabase (objets rattachés à la catégorie racine
  // donnée + leur recette éventuelle, avec ses ingrédients) à la demande, une
  // seule fois par clé. Contrairement à ITEMS (démo locale), ces objets
  // viennent réellement de l'admin. Clés : un atelier (forge, armurerie,
  // alchimie, magie), "market:<catégorie>" (Marché) ou "global" (Catalogue de
  // l'en-tête : tout ce qui est achetable ou fabricable, toutes rubriques).
  async function loadCatalogue(atelier, racineNom) {
    if (catalogueByAtelier[atelier]) return;
    const consultation = atelier.startsWith("market:");
    const global = atelier === "global";
    const [
      { data: categories, error: catErr },
      { data: objets, error: objErr },
      { data: recettes, error: recErr },
      { data: ingredients, error: ingErr },
    ] = await Promise.all([
      supabase.from("categorie").select("id, nom, parent_id"),
      supabase.from("objet_catalogue").select("*"),
      supabase.from("recette").select("*"),
      supabase.from("ingredient_recette").select("*"),
    ]);
    const err = catErr || objErr || recErr || ingErr;
    if (err) {
      setCatalogueByAtelier((prev) => ({
        ...prev,
        [atelier]: { items: null, error: err.message },
      }));
      return;
    }
    const racine = global
      ? null
      : categories.find(
          (c) =>
            c.nom.trim().toLowerCase() === racineNom.trim().toLowerCase() &&
            !c.parent_id,
        );
    const isUnderRacine = (categorieId) => {
      let current = categories.find((c) => c.id === categorieId);
      while (current) {
        if (racine && current.id === racine.id) return true;
        current = categories.find((c) => c.id === current.parent_id);
      }
      return false;
    };
    // Sous-onglets du catalogue = les catégories de niveau 2 sous la racine
    // (ex. Armes courantes / Armes de guerre sous Armes), quelle que soit la
    // profondeur réelle de la catégorie de l'objet (un objet catégorisé plus
    // finement remonte dans le bon onglet de niveau 2). Un objet directement
    // rattaché à la racine (pas encore reclassé, ou racine sans sous-
    // catégories comme Gemmes/Produits Alchimiques) prend le nom de la
    // racine elle-même comme groupe.
    const groupName = (categorieId) => {
      let node = categories.find((c) => c.id === categorieId);
      if (!node) return racineNom;
      if (racine && node.id === racine.id) return racine.nom;
      while (node && racine && node.parent_id !== racine.id) {
        node = categories.find((c) => c.id === node.parent_id);
      }
      return node?.nom || racineNom;
    };
    const objetById = new Map(objets.map((o) => [o.id, o]));
    // Armure = sous la rubrique « Armures », boucliers exclus (même règle que
    // l'admin) : affiche protection et type à la place de la portée.
    const estArmure = (categorieId) => {
      let current = categories.find((c) => c.id === categorieId);
      let dansArmures = false;
      while (current) {
        const nom = current.nom.trim().toLowerCase();
        if (nom.startsWith("bouclier")) return false;
        if (nom === "armures") dansArmures = true;
        current = categories.find((c) => c.id === current.parent_id);
      }
      return dansArmures;
    };
    // Arme : la catégorie de l'objet ou l'un de ses ancêtres commence par
    // « Arme » (même règle que isCategorieArme de l'admin). Sert à réserver
    // la vétérance requise aux armes et aux armures.
    const estArme = (categorieId) => {
      let current = categories.find((c) => c.id === categorieId);
      while (current) {
        if (current.nom.trim().toLowerCase().startsWith("arme")) return true;
        current = categories.find((c) => c.id === current.parent_id);
      }
      return false;
    };
    // Produit alchimique : la catégorie de l'objet ou l'un de ses ancêtres
    // s'appelle « Produits Alchimiques » (même règle que l'admin). Avec les
    // armes, seule rubrique où la portée s'affiche.
    const estAlchimique = (categorieId) => {
      let current = categories.find((c) => c.id === categorieId);
      while (current) {
        if (current.nom.trim().toLowerCase() === "produits alchimiques") return true;
        current = categories.find((c) => c.id === current.parent_id);
      }
      return false;
    };
    // Bouclier : la catégorie de l'objet ou l'un de ses ancêtres s'appelle
    // « Bouclier… » : affiche ses malus à la place de la portée.
    const estBouclier = (categorieId) => {
      let current = categories.find((c) => c.id === categorieId);
      while (current) {
        if (current.nom.trim().toLowerCase().startsWith("bouclier")) return true;
        current = categories.find((c) => c.id === current.parent_id);
      }
      return false;
    };
    // Marché : « Objets divers » regroupe aussi les catégories racines sans
    // bouton dédié, sous leur propre onglet — sauf les Gemmes, qui ne
    // s'obtiennent que par fabrication (Tour du Mage) et ne sont pas en vente.
    const rootOf = (categorieId) => {
      let c = categories.find((x) => x.id === categorieId);
      while (c?.parent_id) c = categories.find((x) => x.id === c.parent_id);
      return c;
    };
    const MARKET_BUTTON_ROOTS = ["armes", "armures", "composants", "matériaux", "produits alchimiques", "gemmes"];
    const isDivers = consultation && racineNom.trim().toLowerCase() === "objet divers";
    const included = (o) =>
      isDivers
        ? !MARKET_BUTTON_ROOTS.includes((rootOf(o.categorie_id)?.nom || "").trim().toLowerCase())
        : isUnderRacine(o.categorie_id);
    // Catalogue global : onglet = catégorie de niveau 2 sous la racine propre
    // à chaque objet (même principe que groupName, racine par racine).
    const groupeSousRacine = (categorieId, root) => {
      let node = categories.find((c) => c.id === categorieId);
      if (!node || !root) return root?.nom || "Autres";
      if (node.id === root.id) return root.nom;
      while (node && node.parent_id !== root.id) {
        node = categories.find((c) => c.id === node.parent_id);
      }
      return node?.nom || root.nom;
    };
    const construire = (o) => {
      const recette = recettes.find(
        (r) => r.resultat_objet_id === o.id && r.actif !== false,
      );
      const ingredientsList = recette
        ? ingredients
            .filter((i) => i.recette_id === recette.id)
            .map((i) => ({
              nom: objetById.get(i.objet_id)?.nom || "Ingrédient inconnu",
              quantite: i.quantite_requise,
            }))
        : [];
      const root = rootOf(o.categorie_id);
      return {
        ...o,
        ingredientsList,
        // Atelier de fabrication (forge/armurerie/alchimie/magie), tel que
        // défini par la recette : null si l'objet n'a pas de recette.
        atelier: recette?.atelier || null,
        estArme: estArme(o.categorie_id),
        estAlchimique: estAlchimique(o.categorie_id),
        estArmure: estArmure(o.categorie_id),
        estBouclier: estBouclier(o.categorie_id),
        groupe: global
          ? groupeSousRacine(o.categorie_id, root)
          : isDivers && root && root.id !== racine?.id
            ? root.nom
            : groupName(o.categorie_id),
        racine: global || isDivers ? root?.nom || racineNom : racineNom,
      };
    };
    // Global : uniquement ce qui est réellement disponible, à l'achat (coût
    // défini) ou à la fabrication (recette avec au moins un ingrédient).
    const items = global
      ? objets
          .filter((o) => o.actif !== false)
          .map(construire)
          .filter(
            (it) =>
              (it.cout_achat_or !== null && it.cout_achat_or !== undefined) ||
              it.ingredientsList.length > 0,
          )
      : objets.filter((o) => o.actif !== false && included(o)).map(construire);
    setCatalogueByAtelier((prev) => ({ ...prev, [atelier]: { items, error: "" } }));
  }
  // null si aucune commande locale n'est en cours pour Forge/Armurerie (cf.
  // useState(null) plus haut) : pas de repli sur ITEMS[0], sinon la case
  // réafficherait toujours un objet par défaut au lieu de rester vide.
  const item = ITEMS.find((i) => i.id === selection) || null;
  if (route === "admin") return <Admin onCraftItem={sendToForge} />;
  if (session === undefined) {
    return (
      <main
        className="auth-page"
        style={{ backgroundImage: `url(${ASSETS.login})` }}
      />
    );
  }
  if (auth) {
    if (session) return null; // redirection vers #forteresse en cours (effet ci-dessus)
    return (
      <Auth
        key={route}
        signup={route === "inscription"}
        onEnter={(n) => {
          setName(n);
          location.hash = "forteresse";
          notify(`Bienvenue, ${n}.`);
        }}
      />
    );
  }
  if (!session) return null; // redirection vers #connexion en cours (effet ci-dessus)
  return (
    <div className={`app${route === "forteresse" ? " app-fullwidth" : ""}`}>
      <a className="skip" href="#main">
        Aller au contenu
      </a>
      <header className="game-header">
        <nav className="class-nav" aria-label="Personnages">
          <a
            className="nav-logout"
            href="#connexion"
            onClick={(e) => {
              e.preventDefault();
              supabase.auth.signOut();
            }}
          >
            Se déconnecter
          </a>
          {CHARACTER_CLASSES.map(([id, label]) => (
            <a
              key={id}
              className={`character-link ${route.startsWith(`personnages/${id}`) ? "active" : ""}`}
              href={`#personnages/${id}`}
              aria-current={
                route.startsWith(`personnages/${id}`) ? "page" : undefined
              }
            >
              {label}
            </a>
          ))}
          <a
            className={route === "forteresse" ? "active" : ""}
            href="#forteresse"
            aria-current={route === "forteresse" ? "page" : undefined}
          >
            Forteresse
          </a>
          {session?.user?.email?.toLowerCase() === "btestart@aol.com" && (
            <a href="#admin">Administration</a>
          )}
        </nav>
        <div className="header-treasury">
        <a
          className="gold-counter"
          href="#tresorerie"
          aria-label={`Trésorerie : ${game.gold} pièces d’or`}
        >
          <span className="coin" aria-hidden="true">
            <img src="/assets/gold-coin.png" alt="" />
          </span>
          <span>
            {money(game.gold)} <small>Po</small>
          </span>
        </a>
        <button
          type="button"
          className="header-time header-catalogue"
          onClick={() => {
            setActionError("");
            loadCatalogue("global", "Tout");
            setModal({
              type: "db-catalogue",
              atelier: "global",
              racine: "Catalogue",
              global: true,
            });
          }}
        >
          Catalogue
        </button>
        {/* +1 Instance : réservé à l'administrateur (il fait avancer
            l'entraînement de tous les joueurs). Absent pour les joueurs. */}
        {estAdmin && (
          <div className="instance-controls">
            <button className="header-time" onClick={decreaseInstances}
              aria-label="+1 Instance · toutes les Durées d’Instance -1"
              title={`${instanceTicks} instance(s) écoulée(s) · Retire 1 à toutes les Durées d’Instance, minimum 0`}>
              +1 Instance
            </button>
            <button className="header-time header-time-undo" onClick={undoInstanceStep}
              disabled={!instanceUndo || trainingPending > 0}
              aria-label="Annuler le dernier +1 Instance"
              title="Annuler le dernier +1 Instance">
              Annuler
            </button>
          </div>
        )}
        {route === "forteresse" && (
          <button className="quest-sign header-quests" aria-label="Quêtes" onClick={() => { location.hash = "quetes"; }}>
            <img src="/assets/references/quests.png" alt="" />
          </button>
        )}
        </div>
      </header>
      {route.startsWith("personnages/") ? (
        <Characters
          route={route}
          warriors={warriors}
          mercenaires={mercenaires}
          recrutes={[...mesRecrutes.keys()]}
          nomsJoueur={Object.fromEntries(mesRecrutes)}
          tousRecrutes={[...tousRecrutes]}
          estAdmin={estAdmin}
          onRecruit={recruit}
          onDismiss={dismiss}
          onSetVeterance={setVeterance}
          onSetInstructor={chooseInstructor}
          onHeal={healMercenary}
          infirmerieComplete={infirm.beds.slice(0, infirm.capacity).every(Boolean)}
          absences={absences}
          instructeurEnPlace={!!training.instructor}
          litLibre={firstFreeBed(dorm) >= 0}
          onUpdate={(id, data) =>
            setWarriors((old) =>
              old.map((w) => (w.id === id ? { ...w, ...data } : w)),
            )
          }
          Modal={Modal}
          notify={notify}
        />
      ) : route === "forteresse" ? (
        <main id="main" className="home">
          <h1 className="sr-only" tabIndex="-1" ref={titleRef}>
            La Forteresse
          </h1>
          <div
            className="castle-map"
            style={{ backgroundImage: `url(${ASSETS.castle})` }}
          >
            <BackdropVideo src="/assets/video/fortress-anime3.mp4" />
            {LOCATIONS.filter((l) => l.id !== "quetes").map((l) => (
              <button
                key={l.id}
                onClick={() => go(l)}
                className={`location ${l.id === "quetes" ? "quest-sign" : "parchment"}`}
                style={{
                  left: `${l.x}%`,
                  top: `${l.y}%`,
                  // Le % est réduit (x0.65) pour que les cartes ne se chevauchent jamais
                  // entre elles vu l'écart entre certains centres (ex. Tour du Mage/Trésorerie,
                  // Dortoirs/Infirmerie) ; le plafond en px garde la taille desktop inchangée.
                  width: `min(${l.w * 0.65}%, ${l.w * 9}px)`,
                  height: `min(${l.h * 0.65}%, ${l.h * 6.92}px)`,
                }}
                aria-label={`${l.name}${l.locked ? " — verrouillé" : ""}`}
              >
                {l.id === "quetes" ? (
                  <img src="/assets/references/quests.png" alt="Quêtes" />
                ) : (
                  <>
                    <Sprite location={l} />
                    <span>
                      {l.id === "entrainement" ? (
                        <>
                          Terrain <span className="tight-word">d’Entraînement</span>
                        </>
                      ) : (
                        l.name
                      )}
                    </span>
                    {l.locked && (
                      <span className="lock-mark" aria-hidden="true">
                        <img src="/assets/icons/lock.png" alt="" />
                      </span>
                    )}
                  </>
                )}
              </button>
            ))}
          </div>
          <section className="mobile-locations">
            <div className="section-title">
              <h1>La Forteresse</h1>
              <span>11 lieux</span>
            </div>
            <div className="location-list">
              {LOCATIONS.map((l) => (
                <button
                  className="parchment location-row"
                  key={l.id}
                  onClick={() => go(l)}
                >
                  <Sprite location={l} />
                  <span>
                    {l.name}
                    <small>{l.locked ? "Verrouillé" : l.description}</small>
                  </span>
                  <span aria-hidden="true">›</span>
                </button>
              ))}
            </div>
          </section>
        </main>
      ) : (
        <main id="main" className={`interior ${route}`}>
          {BACKDROP_VIDEO[route] ? (
            <BackdropVideo src={BACKDROP_VIDEO[route]} ratio={BACKDROP_VIDEO_RATIO[route]} dip={BACKDROP_VIDEO_DIP[route]} rate={BACKDROP_VIDEO_RATE[route]} />
          ) : (
            <div
              className="interior-backdrop"
              style={{
                backgroundImage: `url(${ASSETS[{ armurerie: "armory", forge: "forge", dortoirs: "dormitory", entrainement: "training", quetes: "quests", infirmerie: "infirmary", alchimie: "alchemy", tresorerie: "treasury", marche: "market", mage: "mage" }[route]] || ASSETS.castle})`,
              }}
            />
          )}
          <div className="room-top">
            <a href="#forteresse">‹ Forteresse</a>
            <h1 ref={titleRef} tabIndex="-1">
              {place?.name || "Lieu introuvable"}
            </h1>
            <button
              className="wood-button"
              onClick={() => setModal({ type: "inventory" })}
            >
              Inventaire{" "}
              <span>{game.inventory.reduce((a, b) => a + b.quantity, 0)}</span>
            </button>
          </div>
          {route === "marche" ? (
            <Market
              onCategory={({ racine }) => {
                // Consultation du catalogue Supabase pour cette catégorie
                // racine (le mode achat sera traité ensuite).
                const atelier = `market:${racine}`;
                setActionError("");
                loadCatalogue(atelier, racine);
                setModal({ type: "db-catalogue", atelier, racine, market: true });
              }}
            />
          ) : route === "quetes" ? (
            <Quests
              onInventory={() => setModal({ type: "inventory" })}
              onCampaign={() => setModal({ type: "campaign" })}
            />
          ) : route === "tresorerie" ? (
            <Treasury
              treasury={treasury}
              gold={game.gold}
              log={game.log}
              onChange={updateTreasury}
              Modal={Modal}
            />
          ) : route === "entrainement" ? (
            <Training
              training={training}
              people={people}
              warriors={warriors}
              absents={Object.keys(absences)}
              estAdmin={estAdmin}
              gold={game.gold}
              onChoose={chooseStudent}
              onSendBack={sendBackToDorm}
              onUnlock={unlockTraining}
              Modal={Modal}
            />
          ) : route === "dortoirs" ? (
            <Dortoir
              key="dortoir"
              dorm={dorm}
              warriors={warriors}
              absences={absences}
              gold={game.gold}
              onUnlock={unlockDorm}
              Modal={Modal}
            />
          ) : route === "infirmerie" ? (
            <Infirmary
              key="infirmerie"
              infirmary={infirm}
              people={people}
              warriors={warriors}
              estAdmin={estAdmin}
              gold={game.gold}
              onRecall={recallFromInfirmary}
              onUnlock={unlockInfirm}
              Modal={Modal}
            />
          ) : ["armurerie", "forge", "alchimie", "mage"].includes(route) ? (
            <>
              <div className="workshop">
                <section className="equipment-panel parchment">
                  <p className="eyebrow">{WORKSHOP_TEXT[route].eyebrow}</p>
                  {(() => {
                    const queued = game.craftingQueue?.[route];
                    const remaining =
                      game.durations?.[route] ?? defaultDurations[route] ?? 0;
                    const ready = !!queued && remaining === 0;
                    // Case vide tant qu'aucune commande n'a ete passee (ni
                    // objet local choisi via le Marche, ni fabrication
                    // catalogue en cours) : pas d'objet pret a fabriquer par
                    // defaut, il faut une veritable commande d'un joueur.
                    if (!item && !queued) {
                      return (
                        <p className="muted">
                          Aucune fabrication en cours. Consultez le catalogue
                          pour choisir un objet à envoyer{" "}
                          {WORKSHOP_TEXT[route].destination}.
                        </p>
                      );
                    }
                    // Fabrication du catalogue en cours/prete sans commande
                    // locale selectionnee : on ne connait que id/nom/icone
                    // (pas les champs de ITEMS comme description/defense/
                    // metal-leather-wood), donc on affiche seulement la
                    // progression partagee, pas la fiche complete.
                    if (!item) {
                      const queuedObj =
                        queued && typeof queued === "object" ? queued : null;
                      const queuedNom = queuedObj?.nom || "Fabrication en cours";
                      return (
                        <>
                          {queuedObj?.icone && (
                            <img
                              className="db-item-art"
                              src={queuedObj.icone}
                              alt={queuedNom}
                            />
                          )}
                          <h2>{queuedNom}</h2>
                          <div className="stat-line">
                            <span>Durée d’instance restante</span>
                            <strong>{remaining}</strong>
                          </div>
                          <button
                            className="primary"
                            disabled={busy || !ready}
                            onClick={() => actCollect(route)}
                          >
                            {busy
                              ? "Fabrication…"
                              : ready
                                ? "Envoyer à l’Arsenal"
                                : "Fabrication en cours…"}
                          </button>
                          {actionError && (
                            <p role="alert" className="error">
                              {actionError}
                            </p>
                          )}
                          <p className="muted">
                            {ready
                              ? "Fabrication terminée : cliquez sur « Envoyer à l’Arsenal » pour libérer l’atelier."
                              : `Fabrication en cours : encore ${remaining} instance(s) avant de pouvoir l’envoyer à l’arsenal.`}
                          </p>
                        </>
                      );
                    }
                    return (
                      <>
                        <ItemArt item={item} />
                        <h2>{item.name}</h2>
                        <p>{item.description}</p>
                        <div className="stat-line">
                          <span>
                            {item.type === "Armes" ? "Attaque" : "Protection"}
                          </span>
                          <strong>{item.defense}</strong>
                        </div>
                        <div className="workshop-duration">
                          <label htmlFor="workshop-duration">Durée d’instance</label>
                          <select
                            id="workshop-duration"
                            disabled={!!queued}
                            value={remaining}
                            onChange={(e) =>
                              setWorkshopDuration(route, e.target.value)
                            }
                          >
                            {[0, 1, 2, 3, 4, 5].map((n) => (
                              <option key={n} value={n}>
                                {n}
                              </option>
                            ))}
                          </select>
                        </div>
                        <h3>Ressources nécessaires</h3>
                        <div className="materials">
                          {[
                            ["metal", "Métal"],
                            ["leather", "Cuir"],
                            ["wood", "Bois"],
                          ].map(([k, label]) => (
                            <div key={k}>
                              <span>{label}</span>
                              <strong>{item[k]}</strong>
                              <small>Stock : {materialQuantity(game.inventory, k)}</small>
                            </div>
                          ))}
                        </div>
                        <button
                          className="primary"
                          disabled={
                            busy ||
                            (queued && !ready) ||
                            (!queued &&
                              ["metal", "leather", "wood"].some(
                                (k) => materialQuantity(game.inventory, k) < item[k],
                              ))
                          }
                          onClick={() => {
                            if (ready) {
                              actCollect(route);
                              return;
                            }
                            if (remaining > 0)
                              act("craft-queue", item.id, { route });
                            else act("craft", item.id);
                          }}
                        >
                          {busy
                            ? "Fabrication…"
                            : ready
                              ? "Envoyer à l’Arsenal"
                              : queued
                                ? "Fabrication en cours…"
                                : "Fabriquer"}
                        </button>
                        {!queued &&
                          ["metal", "leather", "wood"].some(
                            (k) => materialQuantity(game.inventory, k) < item[k],
                          ) && <p className="error">Ressources insuffisantes.</p>}
                        {actionError && (
                          <p role="alert" className="error">
                            {actionError}
                          </p>
                        )}
                        {ready ? (
                          <p className="muted">
                            Fabrication terminée : cliquez sur « Envoyer à
                            l’Arsenal » pour libérer l’atelier.
                          </p>
                        ) : queued ? (
                          <p className="muted">
                            Fabrication en cours : encore {remaining}{" "}
                            instance(s) avant de pouvoir l’envoyer à
                            l’arsenal.
                          </p>
                        ) : (
                          <p className="muted">
                            L’objet fabriqué rejoint votre inventaire une
                            fois la durée d’instance à 0.
                          </p>
                        )}
                      </>
                    );
                  })()}
                </section>
                <button
                  className="catalog-button wood-button"
                  onClick={() => {
                    // La route s'appelle "mage" mais l'atelier stocké en
                    // base (recette.atelier) est "magie".
                    const atelier = route === "mage" ? "magie" : route;
                    const racine = ATELIER_RACINE[atelier];
                    loadCatalogue(atelier, racine);
                    setModal({ type: "db-catalogue", atelier, racine });
                  }}
                >
                  {WORKSHOP_TEXT[route].catalogue} ›
                </button>
              </div>
            </>
          ) : route === "stock" ? (
            <section className="stock-panel parchment">
              <h2>Arsenal de la forteresse</h2>
              <p>
                Équipements et consommables de la compagnie. Sélectionnez un
                objet pour agir.
              </p>
              <div className="arsenal-tabs">
                {ARSENAL_TABS.map((t) => (
                  <button
                    key={t}
                    type="button"
                    className={t === arsenalTab ? "active" : ""}
                    onClick={() => setArsenalTab(t)}
                  >
                    {t}
                  </button>
                ))}
              </div>
              {(() => {
                const shown =
                  arsenalTab === "Général"
                    ? game.inventory
                    : game.inventory.filter(
                        (own) => arsenalCategoryOf(own) === arsenalTab,
                      );
                return (
                  <div className="inventory-grid">
                    {shown.length ? (
                      shown.map((own) => {
                        const { name, art } = inventoryItemInfo(own);
                        return (
                          <button
                            key={own.id}
                            className="inventory-slot"
                            onClick={() => {
                              setActionError("");
                              setModal({ type: "item", id: own.id });
                            }}
                            aria-label={`${name}, quantité ${own.quantity}`}
                            title={name}
                          >
                            {art}
                            <span className="inventory-slot-name" aria-hidden="true">
                              {name}
                            </span>
                            <b>{own.quantity}</b>
                            {own.equipped && <small>Équipé</small>}
                          </button>
                        );
                      })
                    ) : (
                      <p className="muted">
                        {game.inventory.length
                          ? "Aucun objet dans cette catégorie pour le moment."
                          : "L’arsenal est vide. Les objets achetés ou fabriqués s’y ajoutent automatiquement."}
                      </p>
                    )}
                  </div>
                );
              })()}
            </section>
          ) : route === "tresorerie" ? (
            <section className="ledger parchment">
              <p className="eyebrow">Registre de la compagnie</p>
              <h2>Trésorerie</h2>
              <div className="balance">
                <span>Solde actuel</span>
                <strong>{money(game.gold)} Po</strong>
              </div>
              <div className="stat-line">
                <span>Solde initial de démonstration</span>
                <b>905 Po</b>
              </div>
              <h3>Derniers mouvements</h3>
              {game.log.length ? (
                game.log.map((l) => (
                  <div className="ledger-row" key={l.id}>
                    <span>
                      {l.message}
                      <small>
                        {new Date(l.date).toLocaleTimeString("fr-FR", {
                          hour: "2-digit",
                          minute: "2-digit",
                        })}
                      </small>
                    </span>
                    <b>{l.amount ? `${l.amount} Po` : "—"}</b>
                  </div>
                ))
              ) : (
                <p>
                  Aucun mouvement pour le moment. Vos achats et fabrications
                  apparaîtront ici.
                </p>
              )}
            </section>
          ) : route === "marche" ? (
            <section className="market-panel parchment">
              <h2>Le Marché</h2>
              <p>Équipez la compagnie avant le départ.</p>
              <Catalog
                items={ITEMS}
                game={game}
                busy={busy}
                onBuy={(id) => act("buy", id)}
              />
              {actionError && (
                <p className="error" role="alert">
                  {actionError}
                </p>
              )}
            </section>
          ) : route === "infirmerie" || route === "dortoirs" ? (
            <section className="ledger parchment">
              <h2>
                {route === "infirmerie"
                  ? "Les compagnons au repos"
                  : "Votre compagnie"}
              </h2>
              <div className="companion">
                <div>
                  <h3>{name}</h3>
                  <p>{game.health < 3 ? "Blessé léger" : "En pleine forme"}</p>
                </div>
                <strong>{game.health} / 3 PV</strong>
              </div>
              <button
                className="primary"
                disabled={
                  busy ||
                  game.health === 3 ||
                  !game.inventory.some((i) => i.id === "potion")
                }
                onClick={() => act("use", "potion")}
              >
                Utiliser une potion de soin
              </button>
              <p className="muted">
                {game.inventory.find((i) => i.id === "potion")?.quantity || 0}{" "}
                potions disponibles
              </p>
              {actionError && (
                <p role="alert" className="error">
                  {actionError}
                </p>
              )}
              <div className="companion">
                <div>
                  <h3>Isolde</h3>
                  <p>Au repos à l’infirmerie</p>
                </div>
                <strong>1 / 3 PV</strong>
              </div>
            </section>
          ) : route === "quetes" ? (
            <section className="ledger parchment">
              <p className="eyebrow">Le tableau des aventures</p>
              <h2>Les ombres du col</h2>
              <p>
                Des voyageurs ont disparu sur le chemin du nord. Rassemblez la
                compagnie et préparez vos équipements avant de franchir les
                portes.
              </p>
              <div className="stat-line">
                <span>Difficulté</span>
                <strong>Exploration</strong>
              </div>
              <button
                className="primary"
                disabled={game.quest || busy}
                onClick={() => act("quest")}
              >
                {game.quest ? "Quête acceptée" : "Accepter la quête"}
              </button>
              <p className="muted">
                Quête de démonstration. Sa résolution sera définie avec le
                maître du jeu.
              </p>
            </section>
          ) : (
            <section className="ledger parchment">
              <h2>{place?.name || "Ce lieu n’existe pas"}</h2>
              <p>
                {route === "alchimie"
                  ? "Les recettes de l’alchimiste seront ajoutées à partir des règles de Bruno. Vos potions sont déjà disponibles dans l’inventaire."
                  : "Revenez à la forteresse pour poursuivre votre visite."}
              </p>
              <button
                className="primary"
                onClick={() => setModal({ type: "inventory" })}
              >
                Ouvrir l’inventaire
              </button>
            </section>
          )}
          <nav className="room-nav" aria-label="Lieux de la forteresse">
            {LOCATIONS.map((l) => (
              <button
                key={l.id}
                title={l.name}
                aria-label={l.name}
                aria-current={l.id === route ? "page" : undefined}
                className={l.id === route ? "active" : ""}
                onClick={() => go(l)}
              >
                {l.id === "quetes" ? (
                  <span className="sprite asset-sprite" aria-hidden="true">
                    <img src="/assets/icons/quetes-sidebar.png" alt="" />
                  </span>
                ) : (
                  <Sprite location={l} />
                )}
                <span>{l.name}</span>
              </button>
            ))}
          </nav>
        </main>
      )}
      {toast && (
        <div role="status" className="toast">
          {toast}
        </div>
      )}
      {modal && (
        <Modal
          title={
            modal.type === "catalog"
              ? "Catalogue"
              : modal.type === "db-catalogue"
                ? modal.detailId
                  ? catalogueByAtelier[modal.atelier]?.items?.find(
                      (i) => i.id === modal.detailId,
                    )?.nom || modal.racine
                  : modal.global
                    ? "Catalogue"
                    : `Catalogue : ${modal.racine}`
                : modal.type === "inventory"
                ? "Inventaire de la compagnie"
                : modal.type === "locked"
                  ? modal.place.name
                  : modal.type === "character"
                    ? character
                    : ITEMS.find((i) => i.id === modal.id)?.name ||
                      game.inventory.find((i) => i.id === modal.id)?.nom ||
                      "Objet"
          }
          onClose={() => {
            setModal(null);
            setActionError("");
          }}
        >
          {modal.type === "campaign" ? (
            <CampaignInventory
              warriors={warriors}
              campaign={campaign}
              stock={game.inventory}
              onTransfer={transferCampaign}
              ItemArt={ItemArt}
            />
          ) : modal.type === "catalog" ? (
            <>
              <div className="search-wrap">
                <input
                  ref={searchRef}
                  aria-label="Rechercher un équipement"
                  placeholder="Rechercher un équipement…"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                />
                {search && (
                  <button
                    className="text-button"
                    onClick={() => {
                      setSearch("");
                      searchRef.current.focus();
                    }}
                  >
                    Effacer
                  </button>
                )}
              </div>
              <div className="filters">
                {[
                  "Tout",
                  "Armures",
                  "Armes",
                  "Objets magiques",
                  "Objets divers",
                ].map((f) => (
                  <button
                    key={f}
                    aria-pressed={filter === f}
                    className={filter === f ? "active" : ""}
                    onClick={() => setFilter(f)}
                  >
                    {f}
                  </button>
                ))}
              </div>
              <Catalog
                items={ITEMS.filter(
                  (i) =>
                    !i.craftOnly && (filter === "Tout" ||
                      i.type === filter ||
                      (filter === "Objets magiques" && i.type === "Potions")) &&
                    i.name
                      .toLocaleLowerCase("fr")
                      .includes(search.toLocaleLowerCase("fr")),
                )}
                game={game}
                busy={busy}
                onBuy={(id) => act("buy", id)}
                onSelect={(id) => {
                  setSelection(id);
                  setModal(null);
                  location.hash = id === "epee" ? "forge" : "armurerie";
                }}
              />
            </>
          ) : modal.type === "db-catalogue" ? (
            (() => {
              const entry = catalogueByAtelier[modal.atelier];
              const detailItem =
                modal.detailId &&
                entry?.items?.find((i) => i.id === modal.detailId);
              if (detailItem) {
                // Fiche de l'objet affichee dans la modale elle-meme (pas de
                // panneau de page dedie), pour les 4 ateliers : le joueur
                // peut la fermer et revenir a la liste, ou lancer la
                // fabrication depuis cette meme fenetre.
                return (
                  <>
                    {(() => {
                      // Atelier de fabrication de CET objet (celui de sa
                      // recette) ; dans un atelier, à défaut, celui de la page.
                      const atelierItem =
                        detailItem.atelier ||
                        (modal.global || modal.market ? null : modal.atelier);
                      const routeItem = ATELIER_ROUTE[atelierItem];
                      return (
                        <CatalogueItemDetail
                          item={detailItem}
                          game={game}
                          busy={busy}
                          context={
                            modal.global ? "global" : modal.market ? "market" : "atelier"
                          }
                          route={routeItem}
                          actionLabel={
                            atelierItem === "forge"
                              ? "Envoyer à la forge"
                              : atelierItem === "armurerie"
                                ? "Envoyer à l’armurerie"
                                : "Fabriquer"
                          }
                          onBuy={actBuyCatalogue}
                          onCraft={(a) => actCatalogue(a, routeItem)}
                          onCollect={() => actCollect(routeItem)}
                          undo={undoStack[undoStack.length - 1] || null}
                          onUndo={undoCatalogue}
                        />
                      );
                    })()}
                    {actionError && (
                      <p role="alert" className="error">
                        {actionError}
                      </p>
                    )}
                    <button
                      type="button"
                      className="text-button"
                      onClick={() =>
                        setModal({ ...modal, detailId: null })
                      }
                    >
                      ‹ Retour à la liste
                    </button>
                  </>
                );
              }
              return entry?.error ? (
                <p className="admin-error">{entry.error}</p>
              ) : !entry ? (
                <p>Chargement…</p>
              ) : entry.items.length === 0 ? (
                <p className="muted">
                  Aucun objet dans cette catégorie pour le moment.
                </p>
              ) : (
                (() => {
                  const preferredOrder = [
                    "Armes courantes",
                    "Armes de guerre",
                    "Armes de moine",
                    "Armure légère",
                    "Armure intermédiaire",
                    "Armure lourde",
                    "Objets",
                  ];
                  const groups = [...new Set(entry.items.map((a) => a.groupe))];
                  groups.sort((a, b) => {
                    const ia = preferredOrder.indexOf(a);
                    const ib = preferredOrder.indexOf(b);
                    if (ia !== -1 || ib !== -1)
                      return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
                    return a.localeCompare(b, "fr");
                  });
                  const activeTab = groups.includes(
                    catalogueTabByAtelier[modal.atelier],
                  )
                    ? catalogueTabByAtelier[modal.atelier]
                    : groups[0];
                  // Catalogue global : une recherche couvre toutes les rubriques
                  // (les onglets sont alors sans objet).
                  const q = modal.global ? globalSearch.trim().toLocaleLowerCase("fr") : "";
                  const shown = (
                    q
                      ? entry.items.filter((a) => a.nom.toLocaleLowerCase("fr").includes(q))
                      : entry.items.filter((a) => a.groupe === activeTab)
                  ).sort((a, b) => a.nom.localeCompare(b.nom, "fr"));
                  return (
                    <>
                      {modal.global && (
                        <div className="search-wrap">
                          <input
                            aria-label="Rechercher dans le catalogue"
                            placeholder="Rechercher un objet…"
                            value={globalSearch}
                            onChange={(e) => setGlobalSearch(e.target.value)}
                          />
                          {globalSearch && (
                            <button
                              type="button"
                              className="text-button"
                              onClick={() => setGlobalSearch("")}
                            >
                              Effacer
                            </button>
                          )}
                        </div>
                      )}
                      {groups.length > 1 && !q && (
                        <div className="db-item-tabs">
                          {groups.map((g) => (
                            <button
                              key={g}
                              type="button"
                              className={g === activeTab ? "active" : ""}
                              onClick={() =>
                                setCatalogueTabByAtelier((prev) => ({
                                  ...prev,
                                  [modal.atelier]: g,
                                }))
                              }
                            >
                              {g}
                            </button>
                          ))}
                        </div>
                      )}
                      <div className="db-item-list">
                        {shown.map((a) => (
                          <button
                            key={a.id}
                            type="button"
                            className="db-item-row"
                            onClick={() =>
                              setModal({ ...modal, detailId: a.id })
                            }
                          >
                            {a.icone ? (
                              <img className="db-item-icon" src={a.icone} alt="" loading="lazy" decoding="async" />
                            ) : (
                              <span className="db-item-icon" aria-hidden="true" />
                            )}
                            <span>{a.nom}</span>
                            {modal.global && (
                              <small className="db-item-tag">
                                {[
                                  a.cout_achat_or !== null && a.cout_achat_or !== undefined
                                    ? `${a.cout_achat_or} Po`
                                    : null,
                                  a.ingredientsList.length ? "Fabrication" : null,
                                ]
                                  .filter(Boolean)
                                  .join(" · ")}
                              </small>
                            )}
                          </button>
                        ))}
                      </div>
                      {!shown.length && <p className="muted">Aucun résultat.</p>}
                    </>
                  );
                })()
              );
            })()
          ) : modal.type === "inventory" ? (
            <>
              <p className="muted">Arsenal commun · {money(game.gold)} Po</p>
              {game.inventory.length ? (
                game.inventory.map((own) => {
                  const { name, art } = inventoryItemInfo(own);
                  return (
                    <button
                      key={own.id}
                      type="button"
                      className="inventory-row inventory-row-button"
                      onClick={() => {
                        setActionError("");
                        setModal({ type: "item", id: own.id });
                      }}
                    >
                      {art}
                      <div>
                        <h3>{name}</h3>
                        <small>
                          Quantité : {own.quantity}
                          {own.equipped ? " · Équipé" : ""}
                        </small>
                      </div>
                    </button>
                  );
                })
              ) : (
                <p>
                  Inventaire de la compagnie est vide. Rendez-vous au marché
                  pour le remplir.
                </p>
              )}
              <a
                className="inline-link"
                href="#stock"
                onClick={() => setModal(null)}
              >
                Voir l’arsenal complet
              </a>
            </>
          ) : modal.type === "locked" ? (
            <>
              <p>{modal.place.description}</p>
              <p>
                Ce lieu est verrouillé dans la démonstration. Les conditions
                d’accès seront définies avec Bruno.
              </p>
            </>
          ) : modal.type === "character" ? (
            <>
              <p>Fiche de démonstration · {character}</p>
              <h3>{name}</h3>
              <p>Points de vie : {game.health} / 3</p>
              <p>
                Les aptitudes propres aux classes seront définies à partir du
                brief.
              </p>
              <button
                className="primary"
                onClick={() => setModal({ type: "inventory" })}
              >
                Voir l’équipement
              </button>
            </>
          ) : (
            <ItemActionPanel
              key={modal.id}
              game={game}
              id={modal.id}
              onSell={actSell}
              onDestroy={actDestroy}
              busy={busy}
              error={actionError}
            />
          )}
          {actionError && (
            <p className="error" role="alert">
              {actionError}
            </p>
          )}
        </Modal>
      )}
    </div>
  );
}
function Catalog({ items, game, busy, onBuy, onSelect }) {
  return items.length ? (
    <div className="catalog-list">
      {items.map((i) => (
        <article className="catalog-item" key={i.id}>
          <ItemArt item={i} />
          <div>
            <small>{i.type}</small>
            <h3>{i.name}</h3>
            <p>{i.description}</p>
            <span>{game.stock[i.id]} en stock</span>
            <div className="catalog-actions">
              <button
                className="primary"
                disabled={busy || game.stock[i.id] === 0 || game.gold < i.price}
                onClick={() => onBuy(i.id)}
              >
                {game.stock[i.id] === 0
                  ? "Épuisé"
                  : game.gold < i.price
                    ? "Or insuffisant"
                    : `Acheter · ${i.price} Po`}
              </button>
              {onSelect && i.metal && (
                <button className="text-button" onClick={() => onSelect(i.id)}>
                  Voir la recette
                </button>
              )}
            </div>
          </div>
        </article>
      ))}
    </div>
  ) : (
    <p className="empty-state">
      Aucun équipement trouvé. Essayez un autre nom ou une autre catégorie.
    </p>
  );
}
