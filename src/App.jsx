import { useState, useEffect, useRef } from "react";
import { Alchemy } from "./Alchemy.jsx";
import { changeAlchemy, initialAlchemy } from "./alchemy.js";
import { Mage } from "./Mage.jsx";
import { changeMage, initialMage } from "./mage.js";
import { ASSETS, LOCATIONS, CLASSES, ITEMS } from "./data";
import { initialGame, transact } from "./game";
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
const money = (n) => new Intl.NumberFormat("fr-FR").format(n);
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
  function submit(e) {
    e.preventDefault();
    const f = new FormData(e.currentTarget);
    const invalid = {};
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(f.get("email")))
      invalid.email = "Saisissez une adresse e-mail valide.";
    if (String(f.get("password")).length < 8)
      invalid.password = "Utilisez au moins 8 caractères.";
    if (signup && String(f.get("pseudo")).trim().length < 2)
      invalid.pseudo = "Saisissez au moins 2 caractères.";
    setErrors(invalid);
    if (Object.keys(invalid).length) {
      document.getElementById(Object.keys(invalid)[0]).focus();
      return;
    }
    setBusy(true);
    onEnter(signup ? String(f.get("pseudo")).trim() : "Aldric");
  }
  return (
    <main
      className="auth-page"
      style={{ backgroundImage: `url(${ASSETS.login})` }}
    >
      <a className="auth-back" href="#forteresse">
        Explorer la démo
      </a>
      <form className="auth-card parchment" onSubmit={submit} noValidate>
        <p className="eyebrow">Bienvenue à la forteresse</p>
        <h1>{signup ? "Créer un compte" : "Connexion"}</h1>
        <p className="auth-intro">
          Retrouvez votre compagnie. Préparez l’aventure.
        </p>
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
              <small id="password-help">
                8 caractères minimum pour cette démo.
              </small>
            )}
            {errors[name] && (
              <small className="error" id={`${name}-error`}>
                {errors[name]}
              </small>
            )}
          </div>
        ))}
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
        <p className="demo-note">
          Prototype : connexion simulée. Aucun compte créé, aucun mot de passe
          enregistré.
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
  const [selection, setSelection] = useState("maille");
  const [filter, setFilter] = useState("Tout");
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
    if (route === "forge") setSelection("epee");
    if (route === "armurerie") setSelection("maille");
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
  function updateAlchemy(action) {
    const result = changeAlchemy(gameRef.current, action);
    if (result.error) return result;
    gameRef.current = result.state;
    setGame(result.state);
    return result;
  }
  function updateMage(action) {
    const result = changeMage(gameRef.current, action);
    if (result.error) return result;
    gameRef.current = result.state;
    setGame(result.state);
    return result;
  }
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
      durations: gameRef.current.durations || defaultDurations,
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
    const next = { ...gameRef.current, durations: instanceUndo.durations };
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
  function act(type, id) {
    if (busyRef.current) return;
    busyRef.current = true;
    setBusy(true);
    setActionError("");
    timer.current = setTimeout(() => {
      const result = transact(gameRef.current, { type, id });
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
  function go(l) {
    if (l.id === "forge") setSelection("epee");
    if (l.id === "armurerie") setSelection("maille");
    if (l.locked) {
      setModal({ type: "locked", place: l });
      return;
    }
    location.hash = l.id;
  }
  const openCatalog = () => {
    setFilter("Tout");
    setSearch("");
    setActionError("");
    setModal({ type: "catalog" });
  };
  const item = ITEMS.find((i) => i.id === selection) || ITEMS[0];
  if (route === "admin") return <Admin />;
  if (auth)
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
  return (
    <div className={`app${route === "forteresse" ? " app-fullwidth" : ""}`}>
      <a className="skip" href="#main">
        Aller au contenu
      </a>
      <header className="game-header">
        <nav className="class-nav" aria-label="Personnages">
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
          <div
            className="interior-backdrop"
            style={{
              backgroundImage: `url(${ASSETS[{ armurerie: "armory", forge: "forge", dortoirs: "dormitory", entrainement: "training", quetes: "quests", infirmerie: "infirmary", alchimie: "alchemy", tresorerie: "treasury", marche: "market", mage: "mage" }[route]] || ASSETS.castle})`,
            }}
          />
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
              onCategory={(category) => {
                setFilter(category);
                setSearch("");
                setActionError("");
                setModal({ type: "catalog" });
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
          ) : route === "alchimie" ? (
            <Alchemy alchemy={game.alchemy || initialAlchemy()} inventory={game.inventory} onChange={updateAlchemy} />
          ) : route === "mage" ? (
            <Mage mage={game.mage || initialMage()} inventory={game.inventory} onChange={updateMage} />
          ) : ["armurerie", "forge"].includes(route) ? (
            <>
              <div className="workshop">
                <section className="equipment-panel parchment">
                  <p className="eyebrow">
                    {route === "forge"
                      ? "Le feu donne forme"
                      : "À l’abri de l’acier"}
                  </p>
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
                      value={
                        game.durations?.[route] ?? (route === "forge" ? 5 : 3)
                      }
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
                        <small>Stock : {game.resources[k]}</small>
                      </div>
                    ))}
                  </div>
                  <button
                    className="primary"
                    disabled={
                      busy ||
                      ["metal", "leather", "wood"].some(
                        (k) => game.resources[k] < item[k],
                      )
                    }
                    onClick={() => act("craft", item.id)}
                  >
                    {busy ? "Fabrication…" : "Fabriquer"}
                  </button>
                  {["metal", "leather", "wood"].some(
                    (k) => game.resources[k] < item[k],
                  ) && <p className="error">Ressources insuffisantes.</p>}
                  {actionError && (
                    <p role="alert" className="error">
                      {actionError}
                    </p>
                  )}
                  <p className="muted">
                    L’objet fabriqué rejoint votre inventaire.
                  </p>
                </section>
                <button
                  className="catalog-button wood-button"
                  onClick={openCatalog}
                >
                  {route === "forge"
                    ? "Catalogue des armes"
                    : "Modèles d’armures"}{" "}
                  ›
                </button>
                <div className="room-caption">
                  <p>{route === "forge" ? "La Forge" : "L’Armurerie"}</p>
                  <span>
                    {route === "forge"
                      ? "Chaque lame raconte une histoire."
                      : "Préparez-vous à la prochaine aventure."}
                  </span>
                </div>
              </div>
            </>
          ) : route === "stock" ? (
            <section className="stock-panel parchment">
              <h2>Arsenal de la forteresse</h2>
              <p>
                Équipements et consommables de la compagnie. Sélectionnez un
                objet pour agir.
              </p>
              <div className="inventory-grid">
                {Array.from({ length: 24 }, (_, i) => {
                  const own = game.inventory[i];
                  const it = own && ITEMS.find((x) => x.id === own.id);
                  return own ? (
                    <button
                      key={own.id}
                      className="inventory-slot"
                      onClick={() => {
                        setActionError("");
                        setModal({ type: "item", id: own.id });
                      }}
                      aria-label={`${it.name}, quantité ${own.quantity}`}
                    >
                      <ItemArt item={it} />
                      <b>{own.quantity}</b>
                      {own.equipped && <small>Équipé</small>}
                    </button>
                  ) : (
                    <div
                      className="inventory-slot empty"
                      key={`empty-${i}`}
                      aria-hidden="true"
                    />
                  );
                })}
              </div>
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
                onClick={() => {
                  if (l.id === "forge") setSelection("epee");
                  if (l.id === "armurerie") setSelection("maille");
                  go(l);
                }}
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
              : modal.type === "inventory"
                ? "Inventaire de la compagnie"
                : modal.type === "locked"
                  ? modal.place.name
                  : modal.type === "character"
                    ? character
                    : ITEMS.find((i) => i.id === modal.id)?.name || "Objet"
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
          ) : modal.type === "inventory" ? (
            <>
              <p className="muted">Arsenal commun · {money(game.gold)} Po</p>
              {game.inventory.length ? (
                game.inventory.map((own) => {
                  const i = ITEMS.find((x) => x.id === own.id);
                  return (
                    <div key={own.id} className="inventory-row">
                      <ItemArt item={i} />
                      <div>
                        <h3>{i.name}</h3>
                        <small>
                          Quantité : {own.quantity}
                          {own.equipped ? " · Équipé" : ""}
                        </small>
                      </div>
                      <button
                        className="wood-button"
                        disabled={busy}
                        onClick={() =>
                          act(i.type === "Potions" ? "use" : "equip", own.id)
                        }
                      >
                        {i.type === "Potions"
                          ? "Utiliser"
                          : own.equipped
                            ? "Ranger"
                            : "Équiper"}
                      </button>
                    </div>
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
            <>
              <p>
                Quantité :{" "}
                {game.inventory.find((i) => i.id === modal.id)?.quantity || 0}
              </p>
              <button
                className="primary"
                disabled={
                  busy || !game.inventory.some((i) => i.id === modal.id)
                }
                onClick={() =>
                  act(ITEMS.find(i => i.id === modal.id)?.type === "Potions" ? "use" : "equip", modal.id)
                }
              >
                {ITEMS.find(i => i.id === modal.id)?.type === "Potions"
                  ? "Utiliser la potion"
                  : game.inventory.find((i) => i.id === modal.id)?.equipped
                    ? "Ranger"
                    : "Équiper"}
              </button>
            </>
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
