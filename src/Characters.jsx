import { useState, useEffect, useRef } from "react";
import { CHARACTER_CLASSES, WEAPONS, LEVELS } from "./characters";
import { ASSETS } from "./data";
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
        src={`/assets/references/${source}.png`}
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
const classeRoute = (nom) =>
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
  onUpdate,
  Modal,
  notify,
}) {
  const [, classId, heroId] = route.split("/");
  const cls = CHARACTER_CLASSES.find((c) => c[0] === classId);
  const merc = mercenaires.find((m) => m.id === heroId);
  const hero = merc ? undefined : warriors.find((w) => w.id === heroId);
  // Fiche d'un mercenaire recruté : réservée à son recruteur et à l'admin.
  const accesFiche = (id) => !tousRecrutes.includes(id) || recrutes.includes(id) || estAdmin;
  const [popup, setPopup] = useState(null);
  const [errors, setErrors] = useState({});
  const title = useRef();
  useEffect(() => {
    setPopup(null);
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
          <p className="eyebrow">Les personnages de la compagnie</p>
          <h1 tabIndex="-1" ref={title}>
            {merc ? merc.nom : hero ? hero.name : cls?.[1] || "Personnages"}
          </h1>
        </div>
        <a href={hero || merc ? `#personnages/${classId}` : "#forteresse"}>
          {merc
            ? `‹ ${cls?.[1] || "Personnages"}`
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
                      <span>Vétérance : {m.veterance}</span>
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
                <strong>{merc.classe || "—"}</strong>
              </div>
              <div className="stat-line">
                <span>Vétérance</span>
                <strong>{merc.veterance}</strong>
              </div>
              <p className="muted">
                La fiche détaillée de ce mercenaire sera complétée ultérieurement.
              </p>
              {recrutes.includes(merc.id) ? (
                <p className="merc-recrute-note">
                  Recruté : {merc.nom} est disponible au Dortoir.
                </p>
              ) : tousRecrutes.includes(merc.id) ? (
                <p className="merc-recrute-note">
                  Recruté par un autre joueur (accès administrateur).
                </p>
              ) : (
                <button
                  className="wood-button merc-recruit"
                  type="button"
                  onClick={() => onRecruit(merc)}
                >
                  Recruter
                </button>
              )}
            </div>
          </section>
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
          title={popup.type === "edit" ? "Modifier la fiche" : popup.title}
          onClose={() => setPopup(null)}
        >
          {popup.type === "edit" ? (
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
