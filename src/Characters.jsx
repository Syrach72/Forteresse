import { useState, useEffect, useRef } from "react";
import { CHARACTER_CLASSES, WEAPONS, LEVELS, COUT_RECRUTEMENT_PAR_VETERANCE } from "./characters";
import { ASSETS } from "./data";
import { SOINS_INSTANCES } from "./dormitory.js";
import { VetBadge } from "./VetBadge.jsx";
import { TableauCompetences, EquipementMercenaire, DetailCompetence, Orbe } from "./MercFiche.jsx";
// Objets qui peuvent être équipés depuis le sac à dos (rubriques du catalogue).
const EQUIPABLES = ["Armes", "Armures", "Objet divers"];
const PARCHMENT_CLASSES = [
  "guerrier",
  "roublard",
  "rodeur",
  "pretre",
  "druide",
  "incantateur",
  "paladin",
];
export function ReferenceCrop({
  crop,
  source = "warriors",
  sourceWidth = 599,
  className = "",
  label = "",
}) {
  if (typeof crop === "string")
    // Portrait d'un mercenaire recruté : URL de l'image (format 3:4).
    return (
      <span
        className={`reference-crop reference-crop-url ${className}`}
        style={{ aspectRatio: "3/4" }}
        role={label ? "img" : undefined}
        aria-label={label || undefined}
        aria-hidden={label ? undefined : true}
      >
        <img alt="" src={crop} />
      </span>
    );
  const [x, y, w, h] = crop;
  return (
    <span
      className={`reference-crop ${className}`}
      style={{ aspectRatio: `${w}/${h}` }}
      role={label ? "img" : undefined}
      aria-label={label || undefined}
      aria-hidden={label ? undefined : true}
    >
      <img
        alt=""
        src={`/assets/references/${source}.webp`}
        style={{
          width: `${(sourceWidth / w) * 100}%`,
          maxWidth: "none",
          left: `${(-x / w) * 100}%`,
          top: `${(-y / h) * 100}%`,
        }}
      />
    </span>
  );
}
// Identifiant de route d'une classe (« Rôdeur » → « rodeur ») à partir du nom
// saisi dans l'administration.
export const classeRoute = (nom) =>
  (nom || "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .trim()
    .toLowerCase();
export function Characters({
  route,
  warriors,
  mercenaires = [],
  recrutes = [],
  tousRecrutes = [],
  estAdmin = false,
  onRecruit = () => {},
  onDismiss = () => {},
  onSetVeterance = async () => ({}),
  onSetInstructor = () => {},
  absences = {},
  instructeurEnPlace = false,
  onHeal = () => {},
  onQuete = () => {},
  onRappel = () => {},
  queteEnCours = null,
  queteComplete = false,
  infirmerieComplete = false,
  litLibre = true,
  nomsJoueur = {},
  onUpdate,
  Modal,
  notify,
  sacsDos = new Map(),
  onRendreArsenal = () => {},
  equipements = new Map(),
  competences = new Map(),
  onEquiper = () => {},
  onDesequiper = () => {},
  erreur = "",
  or = 0,
  onSetActuel = async () => ({}),
  onClearError = () => {},
  busy = false,
}) {
  const [, classId, heroId] = route.split("/");
  const cls = CHARACTER_CLASSES.find((c) => c[0] === classId);
  const merc = mercenaires.find((m) => m.id === heroId);
  // Énergie Max = Mental × vétérance ; Santé Max = Puissance × vétérance ; dans les deux cas le
  // résultat ne descend jamais sous 6 (règle de Bruno). Calculés, jamais saisis.
  const maxAuto = (base, vet) => Math.max(6, (base ?? 0) * (vet ?? 1));
  const energieMax = merc ? maxAuto(merc.mental, merc.veterance) : null;
  const santeMax = merc ? maxAuto(merc.puissance, merc.veterance) : null;
  const hero = merc ? undefined : warriors.find((w) => w.id === heroId);
  // Fiche d'un mercenaire recruté : réservée à son recruteur et à l'admin.
  const accesFiche = (id) => !tousRecrutes.includes(id) || recrutes.includes(id) || estAdmin;
  const [popup, setPopup] = useState(null);
  const [errors, setErrors] = useState({});
  // Nom du joueur inscrit sur la fiche avant de recruter (enregistré avec le
  // recrutement, puis affiché sur les pages où apparaît le mercenaire).
  const [nomJoueur, setNomJoueur] = useState("");
  // Vétérance en cours de saisie (administrateur seulement, sur la fiche).
  const [vet, setVet] = useState("");
  const [vetError, setVetError] = useState("");
  // Énergie et santé actuelles (saisie du joueur) : vide = le maximum s'affiche.
  const [energieAct, setEnergieAct] = useState("");
  const [santeAct, setSanteAct] = useState("");
  const [actuelError, setActuelError] = useState("");
  useEffect(() => {
    setEnergieAct(String(merc?.energieActuelle ?? energieMax ?? ""));
    setSanteAct(String(merc?.santeActuelle ?? santeMax ?? ""));
    setActuelError("");
  }, [merc?.id, merc?.energieActuelle, merc?.santeActuelle, energieMax, santeMax]);
  useEffect(() => {
    setVet(String(merc?.veterance ?? ""));
    setVetError("");
  }, [merc?.id, merc?.veterance]);
  const title = useRef();
  useEffect(() => {
    setPopup(null);
    onClearError();
    setNomJoueur("");
    document.title = `${hero?.name || cls?.[1] || "Personnages"} · Forteresse`;
    title.current?.focus({ preventScroll: true });
  }, [route]);
  function save(e) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    const data = {};
    const invalid = {};
    for (const key of [
      "attack",
      "defense",
      "mind",
      "movement",
      "mana",
      "health",
      "veterancy",
    ]) {
      const raw = String(form.get(key) || "").trim();
      if (raw === "") {
        data[key] = undefined;
        continue;
      }
      const n = Number(raw);
      if (!Number.isInteger(n) || n < 0 || n > 999)
        invalid[key] = "Saisissez un entier de 0 à 999.";
      else data[key] = n;
    }
    for (const key of ["name", "role", "armor", "parry", "notes"])
      data[key] = String(form.get(key) || "").trim();
    if (!data.name) invalid.name = "Le nom est obligatoire.";
    setErrors(invalid);
    if (Object.keys(invalid).length) {
      document.getElementById(`edit-${Object.keys(invalid)[0]}`).focus();
      return;
    }
    onUpdate(hero.id, data);
    setPopup(null);
    notify("Fiche modifiée manuellement pour cette session.");
  }
  return (
    <main
      id="main"
      className={`characters-page ${hero || merc ? "character-detail" : "character-gallery"}`}
      style={
        PARCHMENT_CLASSES.includes(classId)
          ? {
              backgroundImage: `url(${ASSETS.parchment})`,
              backgroundSize: "cover",
              backgroundPosition: "center",
            }
          : undefined
      }
    >
      <div className="characters-heading">
        <div>
          {heroId && <p className="eyebrow">Les personnages de la compagnie</p>}
          <h1 tabIndex="-1" ref={title}>
            {merc
              ? merc.nom
              : hero
                ? hero.name
                : `${cls?.[1] || "Personnages"} : choisis un mercenaire disponible`}
          </h1>
        </div>
        <a
          href={
            merc && recrutes.includes(merc.id)
              ? "#dortoirs"
              : hero || merc
                ? `#personnages/${classId}`
                : "#forteresse"
          }
        >
          {merc
            ? recrutes.includes(merc.id)
              ? "‹ Dortoirs"
              : `‹ ${cls?.[1] || "Personnages"}`
            : hero
              ? "‹ Tous les guerriers"
              : "‹ Forteresse"}
        </a>
      </div>
      <nav className="mobile-class-nav" aria-label="Classes de personnages">
        {CHARACTER_CLASSES.map(([id, label]) => (
          <a
            key={id}
            href={`#personnages/${id}`}
            aria-current={id === classId ? "page" : undefined}
          >
            {label}
          </a>
        ))}
      </nav>
      {!heroId ? (
        mercenaires.some((m) => classeRoute(m.classe) === classId) ? (
          <div className="warrior-grid">
            {mercenaires
              .filter((m) => classeRoute(m.classe) === classId)
              .map((m) => {
                const pris = tousRecrutes.includes(m.id);
                const carte = (
                  <>
                    <span className="merc-portrait">
                      {m.portrait ? (
                        <img src={m.portrait} alt={`Portrait de ${m.nom}`} />
                      ) : (
                        <span className="merc-portrait-vide" aria-hidden="true" />
                      )}
                    </span>
                    <span className="merc-caption">
                      <strong>{m.nom}</strong>
                      <span className="merc-vet">
                        Vétérance <VetBadge value={m.veterance} />
                      </span>
                    </span>
                  </>
                );
                // Recruté : grisé et inclicable pour les joueurs ; l'admin
                // peut toujours ouvrir la fiche.
                if (pris && !estAdmin)
                  return (
                    <div
                      className="merc-card recrute"
                      key={m.id}
                      aria-disabled="true"
                      title="Déjà recruté"
                    >
                      {carte}
                    </div>
                  );
                return (
                  <a
                    className={`merc-card${pris ? " recrute recrute-admin" : ""}`}
                    key={m.id}
                    href={`#personnages/${classId}/${m.id}`}
                    aria-label={`Ouvrir la fiche de ${m.nom}`}
                  >
                    {carte}
                  </a>
                );
              })}
          </div>
        ) : (
          <section className="parchment empty-class">
            <h2>Aucun personnage pour le moment</h2>
            <p>
              Les fiches de cette classe seront ajoutées au fur et à mesure.
            </p>
            <a href="#personnages/guerrier">Voir les guerriers</a>
          </section>
        )
      ) : merc ? (
        accesFiche(merc.id) ? (
          <>
          <section className="merc-sheet parchment">
            <span className="merc-portrait merc-portrait-grand">
              {merc.portrait ? (
                <img src={merc.portrait} alt={`Portrait de ${merc.nom}`} />
              ) : (
                <span className="merc-portrait-vide" aria-hidden="true" />
              )}
            </span>
            <div className="merc-sheet-body">
              <h2>{merc.nom}</h2>
              <div className="stat-line">
                <span>Classe</span>
                <strong>
                  {merc.classe || "—"}
                  {merc.sousClasse ? ` (${merc.sousClasse})` : ""}
                </strong>
              </div>
              {estAdmin ? (
                <form
                  className="stat-line merc-veterance-edit"
                  noValidate
                  onSubmit={async (e) => {
                    e.preventDefault();
                    const result = await onSetVeterance(merc.id, vet);
                    setVetError(result?.error || "");
                  }}
                >
                  <label htmlFor="merc-veterance">Vétérance</label>
                  <span>
                    <input
                      id="merc-veterance"
                      type="number"
                      min="1"
                      max="999"
                      step="1"
                      value={vet}
                      aria-invalid={!!vetError}
                      aria-describedby={vetError ? "merc-veterance-error" : undefined}
                      onChange={(e) => setVet(e.target.value)}
                    />
                    <button
                      className="wood-button"
                      type="submit"
                      disabled={vet === String(merc.veterance ?? "")}
                    >
                      Enregistrer
                    </button>
                  </span>
                </form>
              ) : (
                <div className="stat-line">
                  <span>Vétérance</span>
                  <VetBadge className="vet-badge-fiche" value={merc.veterance} />
                </div>
              )}
              {vetError && (
                <p id="merc-veterance-error" className="error" role="alert">
                  {vetError}
                </p>
              )}
              <div className="merc-stats">
                {[
                  ["Puissance", merc.puissance],
                  ["Vélocité", merc.velocite],
                  ["Mental", merc.mental],
                  ["Mouvement", merc.mouvement === null || merc.mouvement === undefined ? null : `${merc.mouvement}c`],
                ].map(([libelle, valeur]) => (
                  <div className="stat-line" key={libelle}>
                    <span>{libelle}</span>
                    <strong>{valeur ?? "—"}</strong>
                  </div>
                ))}
                {(() => {
                  const peutModifier = recrutes.includes(merc.id) || estAdmin;
                  const lire = (v) => {
                    if (String(v).trim() === "") return { ok: true, n: null };
                    const n = Number(v);
                    return Number.isInteger(n) && n >= 0 && n <= 999 ? { ok: true, n } : { ok: false };
                  };
                  const inchange =
                    santeAct === String(merc.santeActuelle ?? santeMax ?? "") &&
                    energieAct === String(merc.energieActuelle ?? energieMax ?? "");
                  const orbes = (
                    <div className="orbes">
                      <Orbe
                        type="sante"
                        libelle="Santé"
                        id="merc-sante-actuelle"
                        max={santeMax}
                        actuelle={merc.santeActuelle ?? santeMax}
                        editable={peutModifier}
                        valeur={santeAct}
                        onChange={setSanteAct}
                      />
                      <Orbe
                        type="energie"
                        libelle="Énergie"
                        id="merc-energie-actuelle"
                        max={energieMax}
                        actuelle={merc.energieActuelle ?? energieMax}
                        editable={peutModifier}
                        valeur={energieAct}
                        onChange={setEnergieAct}
                      />
                    </div>
                  );
                  return peutModifier ? (
                    <form
                      className="merc-actuel-form"
                      noValidate
                      onSubmit={async (e) => {
                        e.preventDefault();
                        const en = lire(energieAct);
                        const sa = lire(santeAct);
                        if (!en.ok || !sa.ok) {
                          setActuelError("Saisissez des entiers de 0 à 999.");
                          return;
                        }
                        const result = await onSetActuel(merc.id, en.n, sa.n);
                        setActuelError(result?.error || "");
                      }}
                    >
                      {orbes}
                      <button className="wood-button" type="submit" disabled={inchange}>
                        Enregistrer la santé et l’énergie
                      </button>
                      {actuelError && (
                        <p className="error" role="alert">
                          {actuelError}
                        </p>
                      )}
                    </form>
                  ) : (
                    orbes
                  );
                })()}
              </div>
              <p className="muted">
                La fiche détaillée de ce mercenaire sera complétée ultérieurement.
              </p>
              {recrutes.includes(merc.id) ? (
                <div className="merc-recruit-form">
                  <div className="stat-line merc-joueur-fixe">
                    <span>Nom du joueur</span>
                    <strong>{nomsJoueur[merc.id] || "—"}</strong>
                  </div>
                  <div className="merc-actions">
                    <button
                      className="wood-button merc-recruit"
                      type="button"
                      disabled={!!absences[merc.id] || instructeurEnPlace}
                      onClick={() => onSetInstructor(merc.id)}
                    >
                      Instructeur
                    </button>
                    <button
                      className="wood-button merc-recruit"
                      type="button"
                      disabled={!!absences[merc.id] || infirmerieComplete}
                      onClick={() => onHeal(merc.id)}
                    >
                      Soigner
                    </button>
                    <button
                      className="wood-button merc-recruit"
                      type="button"
                      disabled={!!absences[merc.id] || !queteEnCours || queteComplete}
                      title={
                        !queteEnCours
                          ? "Choisissez d’abord une quête sur la page Quêtes."
                          : queteComplete
                            ? "Les 6 places de la quête sont prises."
                            : `Engager dans « ${queteEnCours.nom} »`
                      }
                      onClick={() => onQuete(merc.id)}
                    >
                      Quête
                    </button>
                    <button
                      className="wood-button merc-recruit"
                      type="button"
                      onClick={() => setPopup({ type: "renvoi" })}
                    >
                      Renvoyer
                    </button>
                    <button
                      className="merc-sac-dos"
                      type="button"
                      onClick={() => setPopup({ type: "sac" })}
                      aria-label={`Sac à dos de ${merc.nom}`}
                      title="Sac à dos"
                    >
                      <img src="/assets/icons/sac-a-dos.webp" alt="" />
                    </button>
                  </div>
                  {absences[merc.id] && (
                    <button
                      className="wood-button merc-annuler"
                      type="button"
                      onClick={() => onRappel(merc.id)}
                    >
                      Annuler cet ordre : retour au dortoir
                    </button>
                  )}
                  <p className="merc-recrute-note">
                    {absences[merc.id]
                      ? `${merc.nom} n’est pas au dortoir (${absences[merc.id].toLowerCase()}) : il garde son lit.`
                      : `« Instructeur » l’envoie former des élèves de sa classe${instructeurEnPlace ? " (un instructeur est déjà en place)" : ""} ; « Soigner » l’envoie à l’infirmerie pour ${SOINS_INSTANCES} instances${infirmerieComplete ? " (aucun lit libre pour le moment)" : ""} ; « Quête » l’engage dans la quête en cours${queteEnCours ? ` (${queteEnCours.nom})` : " (aucune quête choisie pour le moment)"}.`}
                  </p>
                  <p className="merc-recrute-note">
                    {merc.nom} a son lit au Dortoir. Le renvoyer efface le nom
                    du joueur et libère le lit ; il conserve sa vétérance et sa
                    fiche. Le recruter de nouveau coûterait{" "}
                    {COUT_RECRUTEMENT_PAR_VETERANCE * (merc.veterance ?? 1)} Po.
                  </p>
                </div>
              ) : tousRecrutes.includes(merc.id) ? (
                <p className="merc-recrute-note">
                  Recruté par un autre joueur (accès administrateur).
                </p>
              ) : (
                <form
                  className="merc-recruit-form"
                  onSubmit={(e) => {
                    e.preventDefault();
                    if (nomJoueur.trim() && litLibre)
                      onRecruit(merc, nomJoueur.trim());
                  }}
                >
                  <p className="merc-cout-recrutement">
                    Recrutement : {COUT_RECRUTEMENT_PAR_VETERANCE} Po × vétérance {merc.veterance ?? 1} ={" "}
                    <strong>{COUT_RECRUTEMENT_PAR_VETERANCE * (merc.veterance ?? 1)} Po</strong>, prélevés sur la
                    trésorerie. Renvoyé, il faudra le payer de nouveau pour le recruter.
                    {estAdmin && vet !== String(merc.veterance ?? "") && (
                      <>
                        {" "}
                        <strong className="error">
                          Le coût suit la vétérance enregistrée ({merc.veterance ?? 1}) : cliquez sur « Enregistrer »
                          pour appliquer {vet || "la nouvelle valeur"}.
                        </strong>
                      </>
                    )}
                  </p>
                  <label htmlFor="merc-nom-joueur">Nom du joueur</label>
                  <input
                    id="merc-nom-joueur"
                    type="text"
                    maxLength={24}
                    autoComplete="off"
                    value={nomJoueur}
                    placeholder="Écrivez votre nom"
                    aria-describedby="merc-recruit-help"
                    onChange={(e) => setNomJoueur(e.target.value)}
                  />
                  <button
                    className="wood-button merc-recruit"
                    type="submit"
                    disabled={!litLibre || !nomJoueur.trim() || or < COUT_RECRUTEMENT_PAR_VETERANCE * (merc.veterance ?? 1)}
                  >
                    Recruter · {COUT_RECRUTEMENT_PAR_VETERANCE * (merc.veterance ?? 1)} Po
                  </button>
                  <p id="merc-recruit-help" className="merc-recrute-note">
                    {!litLibre
                      ? `Aucun lit libre au Dortoir : libérez un lit ou débloquez-en un pour recruter ${merc.nom}.`
                      : or < COUT_RECRUTEMENT_PAR_VETERANCE * (merc.veterance ?? 1)
                        ? `Trésorerie insuffisante : ${COUT_RECRUTEMENT_PAR_VETERANCE * (merc.veterance ?? 1)} Po sont nécessaires (la compagnie en possède ${or}).`
                        : !nomJoueur.trim()
                        ? "Inscrivez votre nom pour pouvoir recruter ce mercenaire. Il restera affiché sur lui jusqu’à son renvoi."
                        : `${merc.nom} prendra place dans un lit du Dortoir.`}
                  </p>
                </form>
              )}
            </div>
          </section>
          {tousRecrutes.includes(merc.id) && (
            <section className="merc-bloc parchment" aria-labelledby="merc-equipement-titre">
              <h2 id="merc-equipement-titre">Équipement</h2>
              <p className="muted">
                3 armes, 1 armure, 1 bouclier et 3 objets. On équipe depuis le sac à dos ; déséquiper renvoie l’objet au sac.
              </p>
              {erreur && (
                <p className="error" role="alert">
                  {erreur}
                </p>
              )}
              <EquipementMercenaire
                equip={equipements.get(merc.id)}
                busy={busy}
                onDesequiper={(emplacement, position) => onDesequiper(merc.id, emplacement, position)}
              />
            </section>
          )}
          <section className="merc-bloc parchment" aria-labelledby="merc-competences-titre">
            <h2 id="merc-competences-titre">Compétences</h2>
            <p className="muted">
              Une ligne par niveau de vétérance ; les compétences d’une ligne se débloquent quand la vétérance de {merc.nom}{" "}
              ({merc.veterance ?? 1}) l’atteint.
            </p>
            <TableauCompetences
              cellules={competences.get(merc.id) || []}
              veterance={merc.veterance ?? 1}
              onCell={(c) =>
                setPopup({
                  type: "competence",
                  title: c.competence?.nom || "Cellule vide",
                  cellule: c,
                  veterance: merc.veterance ?? 1,
                })
              }
            />
          </section>
          </>
        ) : (
          <section className="parchment empty-class">
            <h2>Fiche réservée</h2>
            <p>Ce mercenaire a été recruté : sa fiche n’est accessible qu’à son recruteur.</p>
            <a href={`#personnages/${classId}`}>Retour</a>
          </section>
        )
      ) : heroId && !hero && mercenaires.length === 0 ? (
        <p className="muted">Chargement de la fiche…</p>
      ) : hero ? (
        <>
          <div className="sheet-toolbar">
            <span>Fiche renseignée manuellement</span>
            <button
              className="wood-button"
              onClick={() => {
                setErrors({});
                setPopup({ type: "edit" });
              }}
            >
              Modifier la fiche
            </button>
          </div>
          <div className="character-sheet">
            <aside className="hero-panel parchment">
              <div className="hero-identity">
                <strong title="Vétérance">{hero.veterancy}</strong>
                <h2>{hero.name}</h2>
              </div>
              <ReferenceCrop
                className="hero-portrait"
                crop={hero.portrait}
                label={hero.name}
              />
              <h3 className="hero-class">{hero.role}</h3>
              <div className="hero-stats">
                {[
                  ["attack", "Attaque"],
                  ["defense", "Défense"],
                  ["mind", "Esprit"],
                  ["movement", "Mouvement"],
                  ["mana", "Mana"],
                  ["health", "Vie"],
                ].map(([key, label]) => (
                  <button
                    key={key}
                    className={`hero-stat ${key}`}
                    onClick={() =>
                      setPopup({
                        type: "info",
                        title: label,
                        text: `Valeur actuelle : ${hero[key] ?? "à renseigner"}. Cette caractéristique est modifiée manuellement dans la fiche. Son rôle précis sera documenté avec Bruno.`,
                      })
                    }
                  >
                    <span>{label}</span>
                    <strong>{hero[key] ?? "—"}</strong>
                  </button>
                ))}
              </div>
              <div className="hero-equipment">
                <h3>Armure</h3>
                <p>{hero.armor || "À renseigner"}</p>
                <button
                  className="text-button"
                  onClick={() =>
                    setPopup({
                      type: "info",
                      title: hero.parry || "Parade",
                      text: "Valeur reportée de la fiche de référence. La règle détaillée de parade est à renseigner par le maître du jeu.",
                    })
                  }
                >
                  {hero.parry || "Parade : à renseigner"}
                </button>
              </div>
              {hero.notes && <p className="hero-notes">{hero.notes}</p>}
            </aside>
            <section
              className="weapons-column"
              aria-label="Armes et descriptions"
            >
              {hero.known ? (
                WEAPONS.map((weapon, i) => (
                  <button
                    className={`weapon-scroll parchment ${weapon.empty ? "empty-weapon" : ""}`}
                    key={weapon.name}
                    onClick={() =>
                      setPopup({
                        type: "info",
                        title: weapon.name,
                        text:
                          weapon.text +
                          (weapon.range ? ` ${weapon.range}` : ""),
                      })
                    }
                  >
                    <h2>{weapon.name}</h2>
                    <div className="weapon-body">
                      <ReferenceCrop
                        crop={weapon.crop}
                        source="warrior-sheet-top"
                        sourceWidth={588}
                      />
                      <p>{weapon.text}</p>
                    </div>
                    {weapon.range && (
                      <strong className="weapon-range">{weapon.range}</strong>
                    )}
                    <span className="weapon-help">Voir le détail</span>
                  </button>
                ))
              ) : (
                <div className="parchment weapon-scroll">
                  <h2>Armes et aptitudes</h2>
                  <p>
                    La fiche détaillée de ce personnage n’a pas encore été
                    fournie.
                  </p>
                </div>
              )}
            </section>
            <section
              className="progression-panel"
              aria-labelledby="progression-title"
            >
              <h2 id="progression-title">Progression</h2>
              <p>Vétérance et aptitudes</p>
              <div className="progression-grid">
                {LEVELS.map((level, row) => (
                  <div className="progression-row" key={level}>
                    <span className="level-number">{level}</span>
                    {Array.from({ length: 6 }, (_, col) => {
                      const active =
                        hero.known &&
                        ((row === 0 && col < 3) ||
                          (row === 1 && col === 0) ||
                          (row === 2 && col === 0) ||
                          (row === 3 && col < 2));
                      const crop =
                        row === 0
                          ? [
                              [418, 66, 24, 27],
                              [444, 66, 24, 27],
                              [470, 66, 24, 27],
                            ][col]
                          : row === 1
                            ? [418, 94, 24, 27]
                            : row === 2
                              ? [418, 121, 24, 27]
                              : col === 0
                                ? [418, 149, 24, 27]
                                : [444, 149, 24, 27];
                      return active ? (
                        <button
                          key={col}
                          className="ability-cell unlocked"
                          aria-label={`Aptitude ${col + 1}, vétérance ${level}`}
                          onClick={() =>
                            setPopup({
                              type: "info",
                              title: `Aptitude · Vétérance ${level}`,
                              text: "Cette aptitude est présente dans la capture. Son nom et sa description seront renseignés manuellement ; aucun effet automatique n’est appliqué.",
                            })
                          }
                        >
                          <ReferenceCrop
                            crop={crop}
                            source="warrior-sheet-top"
                            sourceWidth={588}
                          />
                        </button>
                      ) : (
                        <span
                          key={col}
                          className="ability-cell"
                          aria-hidden="true"
                        />
                      );
                    })}
                  </div>
                ))}
              </div>
              <button
                className="text-button ability-example"
                onClick={() => setPopup({ type: "fougue", title: "Fougue" })}
              >
                Fougue · voir l’explication
              </button>
            </section>
          </div>
          <p className="sheet-note">
            Les valeurs de Gnaeus proviennent des captures. Les fiches des
            autres guerriers restent à compléter. Les modifications de cette
            démo sont conservées jusqu’au rechargement.
          </p>
        </>
      ) : (
        <section className="parchment empty-class">
          <h2>Personnage introuvable</h2>
          <a href="#personnages/guerrier">Retour aux guerriers</a>
        </section>
      )}
      {popup && (
        <Modal
          title={
            popup.type === "edit"
              ? "Modifier la fiche"
              : popup.type === "renvoi"
                ? `Renvoyer ${merc?.nom || "le mercenaire"}`
                : popup.type === "sac"
                  ? `Sac à dos de ${merc?.nom || "le mercenaire"}`
                  : popup.title
          }
          onClose={() => setPopup(null)}
        >
          {popup.type === "sac" ? (
            <>
              <p className="muted">
                9 emplacements, jusqu’à 3 par objet. Envoyé depuis l’Arsenal
                (composants alchimiques, armes, armures et objets divers) ;
                rendu à l’arsenal ci-dessous, sans restriction. Armes, armures
                et objets peuvent être équipés (bouton « Équiper »).
              </p>
              {erreur && (
                <p className="error" role="alert">
                  {erreur}
                </p>
              )}
              <div className="sac-dos-grid">
                {Array.from({ length: 9 }, (_, i) => (sacsDos.get(merc.id) || [])[i] || null).map(
                  (item, i) =>
                    item ? (
                      <div className="sac-dos-slot" key={`${item.objetId}:${(item.gemmes || []).join(",")}:${i}`}>
                        {item.icone && <img src={item.icone} alt="" />}
                        <span className="sac-dos-qty">×{item.quantite}</span>
                        <span className="sac-dos-nom">{item.nom}</span>
                        {item.gemmesIcones?.length > 0 && (
                          <span className="sac-dos-gemmes">
                            {item.gemmesIcones.map((g, k) => (
                              <img key={k} src={g} alt="Gemme sertie" />
                            ))}
                          </span>
                        )}
                        {EQUIPABLES.includes(item.categorie) && (
                          <button
                            type="button"
                            className="wood-button sac-dos-equiper"
                            disabled={busy}
                            onClick={() => onEquiper(merc.id, item.objetId, item.gemmes)}
                          >
                            Équiper
                          </button>
                        )}
                        <button
                          type="button"
                          className="text-button"
                          onClick={() => onRendreArsenal(merc.id, item.objetId, item.quantite, item.gemmes)}
                        >
                          Rendre à l’arsenal
                        </button>
                      </div>
                    ) : (
                      <div className="sac-dos-slot sac-dos-slot-vide" key={`vide-${i}`} aria-hidden="true" />
                    ),
                )}
              </div>
            </>
          ) : popup.type === "renvoi" ? (
            <>
              <p>
                <strong>{merc?.nom}</strong> quitte la compagnie : son lit et le
                nom du joueur sont effacés. Il redevient disponible sur la page
                de sa classe, avec sa vétérance et tout ce qu’il a acquis.
              </p>
              <div className="rest-actions">
                <button
                  className="text-button"
                  type="button"
                  onClick={() => setPopup(null)}
                >
                  Annuler
                </button>
                <button
                  className="primary"
                  type="button"
                  onClick={() => {
                    setPopup(null);
                    onDismiss(merc.id);
                  }}
                >
                  Renvoyer
                </button>
              </div>
            </>
          ) : popup.type === "edit" ? (
            <form className="edit-character" onSubmit={save} noValidate>
              <p>
                Les valeurs saisies remplacent manuellement celles de cette
                session.
              </p>
              {[
                ["name", "Nom"],
                ["role", "Classe et spécialité"],
                ["armor", "Armure"],
                ["parry", "Parade"],
                ["notes", "Notes"],
              ].map(([key, label]) => (
                <div className="field" key={key}>
                  <label htmlFor={`edit-${key}`}>{label}</label>
                  <input
                    id={`edit-${key}`}
                    name={key}
                    defaultValue={hero[key] || ""}
                    aria-invalid={!!errors[key]}
                    aria-describedby={errors[key] ? `error-${key}` : undefined}
                  />
                  {errors[key] && (
                    <small id={`error-${key}`} className="error">
                      {errors[key]}
                    </small>
                  )}
                </div>
              ))}
              <div className="edit-stats">
                {[
                  ["attack", "Attaque"],
                  ["defense", "Défense"],
                  ["mind", "Esprit"],
                  ["movement", "Mouvement"],
                  ["mana", "Mana"],
                  ["health", "Vie"],
                  ["veterancy", "Vétérance"],
                ].map(([key, label]) => (
                  <div className="field" key={key}>
                    <label htmlFor={`edit-${key}`}>{label}</label>
                    <input
                      id={`edit-${key}`}
                      name={key}
                      type="number"
                      min="0"
                      max="999"
                      step="1"
                      defaultValue={hero[key] ?? ""}
                      aria-invalid={!!errors[key]}
                      aria-describedby={
                        errors[key] ? `error-${key}` : undefined
                      }
                    />
                    {errors[key] && (
                      <small id={`error-${key}`} className="error">
                        {errors[key]}
                      </small>
                    )}
                  </div>
                ))}
              </div>
              <div className="edit-actions">
                <button
                  type="button"
                  className="text-button"
                  onClick={() => setPopup(null)}
                >
                  Annuler
                </button>
                <button className="primary">Enregistrer la fiche</button>
              </div>
            </form>
          ) : popup.type === "competence" ? (
            <DetailCompetence cellule={popup.cellule} veterance={popup.veterance} />
          ) : popup.type === "fougue" ? (
            <div className="ability-description">
              <ReferenceCrop
                crop={[381, 83, 67, 67]}
                source="ability-popup"
                sourceWidth={583}
              />
              <p className="ability-cost">Coût : 3 Énergies</p>
              <p>
                En dépensant 3 Énergies (limité à une fois par 24h), le Guerrier
                peut prendre une Action supplémentaire.
              </p>
            </div>
          ) : (
            <p>{popup.text}</p>
          )}
        </Modal>
      )}
    </main>
  );
}
