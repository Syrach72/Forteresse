import { useState, useEffect, useRef } from "react";
import { ASSETS, LOCATIONS, CLASSES, ITEMS } from "./data";
import { initialGame, transact, RESOURCE_ALIASES, materialQuantity, ingredientQuantity, sellableValue } from "./game";
import { Market } from "./Market.jsx";
import { Quests, CampaignInventory } from "./Quests.jsx";
import { Treasury } from "./Treasury.jsx";
import { INITIAL_TREASURY, changeTreasury } from "./treasury-data.js";
import { Training } from "./Training.jsx";
import {
  INITIAL_TRAINING,
  stepTraining,
  trainingIds,
} from "./training-data.js";
import { Characters } from "./Characters.jsx";
import { Dormitory } from "./Dormitory.jsx";
import {
  INITIAL_DORMITORY,
  INITIAL_INFIRMARY,
  stepDurations,
  updateDormitory,
} from "./dormitory";
import { WARRIORS, CHARACTER_CLASSES } from "./characters";
import { Admin } from "./Admin.jsx";
import { supabase } from "./supabaseClient";
const money = (n) => new Intl.NumberFormat("fr-FR").format(n);
const BACKDROP_VIDEO = {
  alchimie: "/assets/video/alchimiste-anime.mp4",
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
function BackdropVideo({ src, ratio }) {
  const ref1 = useRef(null);
  const ref2 = useRef(null);
  useEffect(() => {
    const a = ref1.current;
    const b = ref2.current;
    if (!a || !b) return;
    a.style.opacity = 1;
    b.style.opacity = 0;
    let active = a;
    let idle = b;
    let crossfading = false;
    let raf;
    const safePlay = (video) => {
      video.play().catch(() => {});
    };
    safePlay(a);
    const tick = () => {
      if (active.paused) safePlay(active);
      if (active.duration) {
        const remaining = active.duration - active.currentTime;
        if (remaining <= BACKDROP_LOOP_FADE) {
          if (!crossfading) {
            crossfading = true;
            idle.currentTime = 0;
            safePlay(idle);
          }
          const t = Math.min(1, Math.max(0, 1 - remaining / BACKDROP_LOOP_FADE));
          active.style.opacity = 1 - t;
          idle.style.opacity = t;
          if (remaining <= 0.02) {
            active.pause();
            [active, idle] = [idle, active];
            active.style.opacity = 1;
            idle.style.opacity = 0;
            crossfading = false;
          }
        } else {
          active.style.opacity = 1;
          idle.style.opacity = 0;
        }
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [src, ratio]);
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
function ItemActionPanel({ game, id, onSell, busy, error }) {
  const [qty, setQty] = useState(1);
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
      {/* Équiper et Détruire restent inertes : Bruno donnera les règles
          (emplacement d'équipement, confirmation de destruction) avant de
          les brancher. La vente au Marché (moitié de la valeur) est active. */}
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
              }}
            />
          </label>
        </div>
        <button
          className="wood-button"
          disabled={busy || gain === null || own.equipped}
          title={
            gain === null
              ? "Valeur non définie : vente impossible"
              : `Vendre pour ${gain} Po (moitié de la valeur)`
          }
          onClick={() => onSell(own.id, qty)}
        >
          Vendre
        </button>
        <button className="wood-button" disabled title="Bientôt disponible">
          Détruire
        </button>
      </div>
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
// Fiche d'un objet réel du catalogue Supabase (Forge/Armurerie/Laboratoire/
// Tour du Mage) : image, description, recette si elle existe, et tentative
// de fabrication. Chaque ingrédient/composant est débité de game.inventory
// par son nom (voir ingredientQuantity, game.js) ; un stock insuffisant
// désactive le bouton plutôt que de fabriquer gratuitement.
function CatalogueItemDetail({
  item,
  game,
  busy,
  actionLabel = "Fabriquer",
  onCraft,
  onCollect,
  route,
  readOnly = false,
  onBuy,
  onCancel,
}) {
  // Fiche d'achat depuis le Marché : descriptif, vétérance, portée et coût
  // d'achat, avec Acheter (débite le coût de la trésorerie) et Annuler.
  if (readOnly) {
    const cout = item.cout_achat_or;
    const coutDefini = cout !== null && cout !== undefined;
    const soldeInsuffisant = coutDefini && game.gold < cout;
    return (
      <>
        {item.icone && (
          <img className="db-item-art" src={item.icone} alt={item.nom} />
        )}
        <h2>{item.nom}</h2>
        <h3>Descriptif</h3>
        <p>{item.description || "Description à définir."}</p>
        <div className="stat-line">
          <span>Vétérance requise</span>
          <strong>{item.veterance_requise ?? "à définir"}</strong>
        </div>
        <div className="stat-line">
          <span>Portée</span>
          <strong>{item.portee || "à définir"}</strong>
        </div>
        <div className="stat-line">
          <span>Coût d’achat</span>
          <strong>{coutDefini ? `${cout} Po` : "à définir"}</strong>
        </div>
        <div className="market-buy-actions">
          <button
            className="primary"
            type="button"
            disabled={busy || !coutDefini || soldeInsuffisant}
            onClick={() => onBuy(item)}
          >
            {busy ? "Achat…" : "Acheter"}
          </button>
          <button className="text-button" type="button" onClick={onCancel}>
            Annuler
          </button>
        </div>
        {!coutDefini && (
          <p className="muted">Le coût d’achat n’est pas encore défini : achat impossible.</p>
        )}
        {soldeInsuffisant && (
          <p className="error">Solde insuffisant : {game.gold} Po en trésorerie.</p>
        )}
      </>
    );
  }
  const needs = item.ingredientsList;
  const lacking = needs.some((ing) => ingredientQuantity(game.inventory, ing.nom) < ing.quantite);
  // Fabrication en attente pour CET atelier (peu importe l'objet) : la
  // Duree d'instance definie par l'admin (item.duree_fabrication_instances)
  // decompte via le bouton +1 Instance, comme pour la demo locale forge/
  // armurerie. A 0, elle n'est PAS livree automatiquement : il faut cliquer
  // "Envoyer à l'Arsenal" (action "collect-craft", game.js) pour liberer
  // l'atelier et permettre une nouvelle fabrication.
  const queuedHere = game.craftingQueue?.[route];
  const remaining = game.durations?.[route] ?? item.duree_fabrication_instances ?? 0;
  const readyHere = !!queuedHere && remaining === 0;
  return (
    <>
      {item.icone && (
        <img className="db-item-art" src={item.icone} alt={item.nom} />
      )}
      <h2>{item.nom}</h2>
      <p>{item.description || "Description à définir."}</p>
      <div className="stat-line">
        <span>Vétérance requise</span>
        <strong>{item.veterance_requise ?? "à définir"}</strong>
      </div>
      <div className="stat-line">
        <span>Portée</span>
        <strong>{item.portee || "à définir"}</strong>
      </div>
      <div className="workshop-duration">
        <label>Temps de fabrication (instances)</label>
        <strong>
          {queuedHere
            ? remaining
            : (item.duree_fabrication_instances ?? "à définir")}
        </strong>
      </div>
      <h3>{route === "alchimie" ? "Composants" : "Ressources nécessaires"}</h3>
      {item.ingredientsList.length ? (
        <div className="materials">
          {item.ingredientsList.map((ing) => (
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
      <button
        className="primary"
        type="button"
        disabled={
          busy ||
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
              : actionLabel}
      </button>
      {lacking && (
        <p className="error">Ressources insuffisantes pour cette fabrication.</p>
      )}
      {readyHere ? (
        <p className="muted">
          Fabrication terminée : cliquez sur « Envoyer à l’Arsenal » pour
          libérer l’atelier.
        </p>
      ) : queuedHere ? (
        <p className="muted">
          Fabrication en cours : encore {remaining} instance(s) avant de
          pouvoir l’envoyer à l’arsenal.
        </p>
      ) : (
        <p className="muted">
          L’objet fabriqué rejoint votre inventaire une fois la durée
          d’instance à 0.
        </p>
      )}
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
    const invalid = {};
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
      invalid.email = "Saisissez une adresse e-mail valide.";
    if (password.length < 8)
      invalid.password = "Utilisez au moins 8 caractères.";
    if (signup && pseudo.length < 2)
      invalid.pseudo = "Saisissez au moins 2 caractères.";
    setErrors(invalid);
    setServerError("");
    if (Object.keys(invalid).length) {
      document.getElementById(Object.keys(invalid)[0]).focus();
      return;
    }
    setBusy(true);
    const { data, error } = signup
      ? await supabase.auth.signUp({
          email,
          password,
          options: { data: { pseudo } },
        })
      : await supabase.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (error) {
      setServerError(
        error.message === "Invalid login credentials"
          ? "E-mail ou mot de passe incorrect."
          : error.message === "User already registered"
            ? "Un compte existe déjà avec cet e-mail."
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
        {["email", "password", ...(signup ? ["pseudo"] : [])].map((name) => (
          <div className="field" key={name}>
            <label htmlFor={name}>
              {name === "email"
                ? "E-mail"
                : name === "password"
                  ? "Mot de passe"
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
                      : "nickname"
                }
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
  const [warriors, setWarriors] = useState(() => structuredClone(WARRIORS));
  const [route, setRoute] = useState(location.hash.slice(1) || "forteresse");
  const [game, setGame] = useState(initialGame);
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
  // Charge une seule fois, au demarrage, le stock de l'Arsenal saisi cote
  // admin (Administration > Arsenal, table ligne_inventaire) et le fusionne
  // dans game.inventory : c'est ce qui permet au MJ d'ajouter "a la main"
  // les materiaux/composants gagnes en mission, pour que les joueurs les
  // retrouvent dans leur Arsenal (au prochain chargement de la page, comme
  // le reste de la demo). Fusion additive avec l'inventaire local existant
  // (potions de depart, objets deja fabriques cette session) via le meme id
  // `catalogue:<uuid>` que craft-catalogue/collect-craft, pour ne pas creer
  // une seconde ligne pour le meme objet. Un seul compteur par objet : pas
  // de compteur separe pour Fer/Cuir/Bois (voir plus bas, remplacement des
  // lignes `material:<cle>` de demo par l'objet reel de l'admin).
  const arsenalDbLoadedRef = useRef(false);
  useEffect(() => {
    if (!session?.user || arsenalDbLoadedRef.current) return;
    arsenalDbLoadedRef.current = true;
    (async () => {
      const [
        { data: inventaires, error: invErr },
        { data: lignes, error: ligErr },
        { data: objets, error: objErr },
        { data: categories, error: catErr },
      ] = await Promise.all([
        supabase.from("inventaire").select("id, type"),
        supabase.from("ligne_inventaire").select("*"),
        supabase.from("objet_catalogue").select("id, nom, icone, categorie_id, cout_achat_or"),
        supabase.from("categorie").select("id, nom, parent_id"),
      ]);
      // Table absente ou hors-ligne : l'Arsenal reste sur la demo locale,
      // sans bloquer le reste du jeu.
      if (invErr || ligErr || objErr || catErr) return;
      const arsenal = inventaires.find((i) => i.type === "arsenal");
      if (!arsenal) return;
      const objetById = new Map(objets.map((o) => [o.id, o]));
      const topCategoryName = (categorieId) => {
        let current = categories.find((c) => c.id === categorieId);
        while (current?.parent_id)
          current = categories.find((c) => c.id === current.parent_id);
        return current?.nom || null;
      };
      const dbItems = lignes
        .filter((l) => l.inventaire_id === arsenal.id && l.quantite > 0)
        .map((l) => {
          const o = objetById.get(l.objet_id);
          return {
            id: `catalogue:${l.objet_id}`,
            quantity: l.quantite,
            equipped: false,
            nom: o?.nom || "Objet",
            icone: o?.icone || null,
            categorie: o ? topCategoryName(o.categorie_id) : null,
            valeur: o?.cout_achat_or ?? null,
          };
        });
      if (!dbItems.length) return;
      // Construit a partir de gameRef.current (source lue par act()), pas
      // d'un callback setGame(g => ...) : act() ecrit dans gameRef.current
      // sans jamais relire l'etat React `game`, donc une fusion qui ne
      // mettrait a jour que setGame serait ecrasee au premier clic (le
      // craft suivant repartirait de l'etat pre-fusion et l'ecraserait a
      // son tour) — cf. le meme motif gameRef.current = g; setGame(g); que
      // les autres actions de ce fichier (transferCampaign, etc.).
      let inventory = gameRef.current.inventory.map((x) => ({ ...x }));
      for (const it of dbItems) {
        // Fer/Métal, Cuir ou Bois : remplace la ligne de démonstration
        // locale (`material:<clé>`, data.js) au lieu de s'y ajouter — un
        // seul compteur par matériau, celui de l'admin devient la
        // référence dès qu'il existe (voir materialQuantity, game.js).
        const materialKey = RESOURCE_ALIASES[(it.nom || "").trim().toLowerCase()];
        if (materialKey)
          inventory = inventory.filter((x) => x.id !== `material:${materialKey}`);
        const idx = inventory.findIndex((x) => x.id === it.id);
        if (idx >= 0)
          inventory[idx] = {
            ...inventory[idx],
            quantity: inventory[idx].quantity + it.quantity,
          };
        else inventory = [...inventory, it];
      }
      const g = { ...gameRef.current, inventory };
      gameRef.current = g;
      setGame(g);
    })();
  }, [session]);
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
    // Instantané avant modification, pour permettre un « Annuler » exact
    // (ré-appliquer un delta +1 ne suffit pas : un compteur déjà à 0 avant
    // le clic resterait à 0 après un -1 puis un +1, au lieu de refléter
    // qu'il n'avait pas bougé — l'annulation restaure donc l'état capturé
    // ici, plutôt que de rejouer l'opération inverse).
    setInstanceUndo({
      dorm: dormRef.current,
      infirm: infirmRef.current,
      training: trainingRef.current,
      game: gameRef.current,
    });
    const d = stepDurations(dormRef.current, -1);
    const i = stepDurations(infirmRef.current, -1);
    const t = stepTraining(trainingRef.current, -1);
    dormRef.current = d;
    infirmRef.current = i;
    trainingRef.current = t;
    setDorm(d);
    setInfirm(i);
    setTraining(t);
    setInstanceTicks((v) => v + 1);
    const next = {
      ...gameRef.current,
      durations: Object.fromEntries(
        Object.entries(gameRef.current.durations || defaultDurations).map(([k, v]) => [
          k,
          Math.max(0, Math.min(5, v - 1)),
        ]),
      ),
    };
    gameRef.current = next;
    setGame(next);
    notify("+1 Instance : toutes les Durées d’Instance diminuent de 1, minimum 0.");
  }
  function undoInstanceStep() {
    if (!instanceUndo) return;
    dormRef.current = instanceUndo.dorm;
    infirmRef.current = instanceUndo.infirm;
    trainingRef.current = instanceUndo.training;
    setDorm(instanceUndo.dorm);
    setInfirm(instanceUndo.infirm);
    setTraining(instanceUndo.training);
    const next = instanceUndo.game;
    gameRef.current = next;
    setGame(next);
    setInstanceTicks((v) => Math.max(0, v - 1));
    setInstanceUndo(null);
    notify("Dernier +1 Instance annulé.");
  }
  function changeTraining(role, index, person) {
    if (
      person &&
      (!warriors.some((w) => w.id === person.heroId) ||
        !Number.isInteger(person.remaining) ||
        person.remaining < 0 ||
        person.remaining > 5)
    )
      return { error: "Participant ou durée invalide." };
    const current = trainingRef.current;
    const existing =
      role === "instructor" ? current.instructor : current.students[index];
    if (
      person &&
      person.heroId !== existing?.heroId &&
      [
        ...trainingIds(current),
        ...dormRef.current.beds.filter(Boolean).map((b) => b.heroId),
        ...infirmRef.current.beds.filter(Boolean).map((b) => b.heroId),
      ].includes(person.heroId)
    )
      return { error: "Ce mercenaire est déjà occupé." };
    const next =
      role === "instructor"
        ? { ...current, instructor: person }
        : {
            ...current,
            students: current.students.map((s, i) =>
              i === index ? person : s,
            ),
          };
    trainingRef.current = next;
    setTraining(next);
    notify("Entraînement mis à jour.");
    return { state: next };
  }
  function unlockTraining() {
    if (trainingRef.current.capacity >= 3)
      return { error: "Toutes les places élèves sont ouvertes." };
    if (gameRef.current.gold < 100)
      return { error: "Trésorerie insuffisante." };
    const next = {
      ...trainingRef.current,
      capacity: trainingRef.current.capacity + 1,
    };
    const g = {
      ...gameRef.current,
      gold: gameRef.current.gold - 100,
      log: [
        {
          id: crypto.randomUUID(),
          message: "Place élève débloquée : −100 Po.",
          amount: -100,
          date: new Date().toISOString(),
        },
        ...gameRef.current.log,
      ].slice(0, 50),
    };
    trainingRef.current = next;
    gameRef.current = g;
    setTraining(next);
    setGame(g);
    notify("Une place élève est débloquée.");
    return { state: next };
  }
  function changeDorm(action) {
    if (
      action.type === "place" &&
      !warriors.some((w) => w.id === action.heroId)
    )
      return { error: "Mercenaire inconnu." };
    if (
      action.type === "place" &&
      trainingIds(trainingRef.current).includes(action.heroId)
    )
      return { error: "Ce mercenaire est à l’entraînement." };
    if (
      action.type === "place" &&
      infirmRef.current.beds.some((b) => b?.heroId === action.heroId)
    )
      return { error: "Ce mercenaire est déjà à l’infirmerie." };
    const result = updateDormitory(dormRef.current, action);
    if (result.state) {
      dormRef.current = result.state;
      setDorm(result.state);
      notify(
        action.type === "release"
          ? "Repos terminé : le mercenaire est disponible."
          : "Dortoir mis à jour.",
      );
    }
    return result;
  }
  function changeInfirm(action) {
    if (
      action.type === "place" &&
      !warriors.some((w) => w.id === action.heroId)
    )
      return { error: "Mercenaire inconnu." };
    if (
      action.type === "place" &&
      trainingIds(trainingRef.current).includes(action.heroId)
    )
      return { error: "Ce mercenaire est à l’entraînement." };
    if (
      action.type === "place" &&
      dormRef.current.beds.some((b) => b?.heroId === action.heroId)
    )
      return { error: "Ce mercenaire est déjà au dortoir." };
    const result = updateDormitory(infirmRef.current, action);
    if (result.state) {
      infirmRef.current = result.state;
      setInfirm(result.state);
      notify(
        action.type === "release"
          ? "Soins terminés : le mercenaire est disponible."
          : "Infirmerie mise à jour.",
      );
    }
    return result;
  }
  function unlockInfirm() {
    if (infirmRef.current.capacity !== 2)
      return { error: "Cet emplacement est déjà débloqué." };
    if (gameRef.current.gold < 1000)
      return { error: "Trésorerie insuffisante." };
    const next = { ...infirmRef.current, capacity: 3 };
    const nextGame = {
      ...gameRef.current,
      gold: gameRef.current.gold - 1000,
      log: [
        {
          id: crypto.randomUUID(),
          message: "Lit d’infirmerie débloqué : −1000 Po.",
          amount: -1000,
          date: new Date().toISOString(),
        },
        ...gameRef.current.log,
      ].slice(0, 50),
    };
    infirmRef.current = next;
    gameRef.current = nextGame;
    setInfirm(next);
    setGame(nextGame);
    notify("Un lit d’infirmerie est débloqué.");
    return { state: next };
  }
  function unlockDorm() {
    if (dormRef.current.capacity !== 6)
      return { error: "Cet emplacement est déjà débloqué." };
    if (gameRef.current.gold < 100)
      return { error: "Trésorerie insuffisante." };
    const nextDorm = { ...dormRef.current, capacity: 7 };
    const nextGame = {
      ...gameRef.current,
      gold: gameRef.current.gold - 100,
      log: [
        {
          id: crypto.randomUUID(),
          message: "Emplacement de dortoir débloqué : −100 Po.",
          amount: -100,
          date: new Date().toISOString(),
        },
        ...gameRef.current.log,
      ].slice(0, 50),
    };
    dormRef.current = nextDorm;
    gameRef.current = nextGame;
    setDorm(nextDorm);
    setGame(nextGame);
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
  function actCatalogue(arme, route) {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setActionError("");
    timer.current = setTimeout(() => {
      const result = transact(gameRef.current, {
        type: "craft-catalogue",
        arme,
        route,
      });
      if (result.error) {
        setActionError(result.error);
      } else {
        gameRef.current = result.state;
        setGame(result.state);
        // Toujours refermer la fenetre (fabrication lancee ou livree tout
        // de suite) : la modale native bloque le reste de la page pendant
        // qu'elle est ouverte, notamment le bouton +1 Instance necessaire
        // pour faire avancer une fabrication mise en attente.
        setModal(null);
        notify(result.message);
      }
      busyRef.current = false;
      setBusy(false);
    }, 280);
  }
  // Vente d'un objet de l'arsenal au Marché : la moitié de sa valeur est
  // créditée à la trésorerie par transact("sell").
  function actSell(id, quantity) {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setActionError("");
    timer.current = setTimeout(() => {
      const result = transact(gameRef.current, { type: "sell", id, quantity });
      if (result.error) {
        setActionError(result.error);
      } else {
        gameRef.current = result.state;
        setGame(result.state);
        setModal(null);
        notify(result.message);
      }
      busyRef.current = false;
      setBusy(false);
    }, 280);
  }
  // Achat d'un objet du catalogue depuis le Marché : le coût d'achat est
  // décompté de la trésorerie (game.gold) par transact("buy-catalogue").
  function actBuyCatalogue(arme) {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setActionError("");
    timer.current = setTimeout(() => {
      const result = transact(gameRef.current, { type: "buy-catalogue", arme });
      if (result.error) {
        setActionError(result.error);
      } else {
        gameRef.current = result.state;
        setGame(result.state);
        setModal(null);
        notify(result.message);
      }
      busyRef.current = false;
      setBusy(false);
    }, 280);
  }
  // Recupere manuellement une fabrication (locale ou catalogue) une fois sa
  // Duree d'instance a 0 : libere l'atelier pour une nouvelle fabrication.
  // Referme la fiche de l'objet catalogue tout juste livre (vide les
  // cellules Temps de fabrication/Ressources) au lieu de la laisser prete
  // a relancer immediatement le meme objet : il faut retourner au
  // catalogue pour en choisir un (comme apres une livraison immediate).
  function actCollect(route) {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setActionError("");
    timer.current = setTimeout(() => {
      const result = transact(gameRef.current, { type: "collect-craft", route });
      if (result.error) {
        setActionError(result.error);
      } else {
        gameRef.current = result.state;
        setGame(result.state);
        setModal(null);
        // Vide la case locale (Épée longue/Cotte de mailles) : elle ne doit
        // pas se remettre prête à refabriquer toute seule apres la
        // livraison, mais rester vide jusqu'a une nouvelle commande
        // explicite (Marché > Voir la recette, ou le Catalogue).
        setSelection(null);
        notify(result.message);
      }
      busyRef.current = false;
      setBusy(false);
    }, 280);
  }
  function go(l) {
    if (l.locked) {
      setModal({ type: "locked", place: l });
      return;
    }
    location.hash = l.id;
  }
  // Charge le catalogue Supabase d'un atelier (objets rattachés à la
  // catégorie racine donnée + recette de cet atelier associée, avec ses
  // ingrédients) à la demande, une seule fois par atelier. Contrairement à
  // ITEMS (démo locale), ces objets viennent réellement de l'admin.
  async function loadCatalogue(atelier, racineNom) {
    if (catalogueByAtelier[atelier]) return;
    // Clé "market:<catégorie>" : simple consultation depuis le Marché, sans
    // recette (pas d'atelier associé).
    const consultation = atelier.startsWith("market:");
    const none = Promise.resolve({ data: [], error: null });
    const [
      { data: categories, error: catErr },
      { data: objets, error: objErr },
      { data: recettes, error: recErr },
      { data: ingredients, error: ingErr },
    ] = await Promise.all([
      supabase.from("categorie").select("id, nom, parent_id"),
      supabase.from("objet_catalogue").select("*"),
      consultation ? none : supabase.from("recette").select("*").eq("atelier", atelier),
      consultation ? none : supabase.from("ingredient_recette").select("*"),
    ]);
    const err = catErr || objErr || recErr || ingErr;
    if (err) {
      setCatalogueByAtelier((prev) => ({
        ...prev,
        [atelier]: { items: null, error: err.message },
      }));
      return;
    }
    const racine = categories.find(
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
    // Marché : « Objets divers » regroupe aussi les catégories racines sans
    // bouton dédié (ex. Gemmes), sous leur propre onglet.
    const rootOf = (categorieId) => {
      let c = categories.find((x) => x.id === categorieId);
      while (c?.parent_id) c = categories.find((x) => x.id === c.parent_id);
      return c;
    };
    const MARKET_BUTTON_ROOTS = ["armes", "armures", "composants", "matériaux", "produits alchimiques"];
    const isDivers = consultation && racineNom.trim().toLowerCase() === "objet divers";
    const included = (o) =>
      isDivers
        ? !MARKET_BUTTON_ROOTS.includes((rootOf(o.categorie_id)?.nom || "").trim().toLowerCase())
        : isUnderRacine(o.categorie_id);
    const items = objets
      .filter((o) => o.actif !== false && included(o))
      .map((o) => {
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
        return {
          ...o,
          ingredientsList,
          groupe:
            isDivers && rootOf(o.categorie_id) && rootOf(o.categorie_id).id !== racine?.id
              ? rootOf(o.categorie_id).nom
              : groupName(o.categorie_id),
          racine: isDivers ? rootOf(o.categorie_id)?.nom || racineNom : racineNom,
        };
      });
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
        <div className="instance-controls">
          <button className="header-time" onClick={decreaseInstances}
            aria-label="+1 Instance · toutes les Durées d’Instance -1"
            title={`${instanceTicks} instance(s) écoulée(s) · Retire 1 à toutes les Durées d’Instance, minimum 0`}>
            +1 Instance
          </button>
          <button className="header-time header-time-undo" onClick={undoInstanceStep}
            disabled={!instanceUndo}
            aria-label="Annuler le dernier +1 Instance"
            title="Annuler le dernier +1 Instance">
            Annuler
          </button>
        </div>
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
            <BackdropVideo src="/assets/video/fortress-anime.mp4" />
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
            <BackdropVideo src={BACKDROP_VIDEO[route]} ratio={BACKDROP_VIDEO_RATIO[route]} />
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
              warriors={warriors}
              otherOccupied={[...dorm.beds, ...infirm.beds]
                .filter(Boolean)
                .map((b) => b.heroId)}
              gold={game.gold}
              onChange={changeTraining}
              onUnlock={unlockTraining}
              Modal={Modal}
            />
          ) : route === "dortoirs" ? (
            <Dormitory
              dorm={dorm}
              warriors={warriors}
              gold={game.gold}
              onChange={changeDorm}
              onUnlock={unlockDorm}
              Modal={Modal}
              otherOccupied={[
                ...infirm.beds.filter(Boolean).map((b) => b.heroId),
                ...trainingIds(training),
              ]}
            />
          ) : route === "infirmerie" ? (
            <Dormitory
              kind="infirmary"
              dorm={infirm}
              warriors={warriors}
              gold={game.gold}
              onChange={changeInfirm}
              onUnlock={unlockInfirm}
              Modal={Modal}
              otherOccupied={[
                ...dorm.beds.filter(Boolean).map((b) => b.heroId),
                ...trainingIds(training),
              ]}
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
                          >
                            {art}
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
                    <CatalogueItemDetail
                      item={detailItem}
                      game={game}
                      busy={busy}
                      route={ATELIER_ROUTE[modal.atelier]}
                      readOnly={!!modal.market}
                      onBuy={actBuyCatalogue}
                      onCancel={() => setModal({ ...modal, detailId: null })}
                      actionLabel={
                        modal.atelier === "forge"
                          ? "Envoyer à la forge"
                          : modal.atelier === "armurerie"
                            ? "Envoyer à l’armurerie"
                            : "Fabriquer"
                      }
                      onCraft={(a) => actCatalogue(a, ATELIER_ROUTE[modal.atelier])}
                      onCollect={() => actCollect(ATELIER_ROUTE[modal.atelier])}
                    />
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
                  const shown = entry.items
                    .filter((a) => a.groupe === activeTab)
                    .sort((a, b) => a.nom.localeCompare(b.nom, "fr"));
                  return (
                    <>
                      {groups.length > 1 && (
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
                              <img className="db-item-icon" src={a.icone} alt="" />
                            ) : (
                              <span className="db-item-icon" aria-hidden="true" />
                            )}
                            <span>{a.nom}</span>
                          </button>
                        ))}
                      </div>
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
