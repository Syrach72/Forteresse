import { useState } from "react";
import { ReferenceCrop } from "./Characters.jsx";
export function Dormitory({
  dorm,
  warriors,
  gold,
  onChange,
  onUnlock,
  onDismiss,
  names = [],
  onRename,
  Modal,
  kind = "dormitory",
  otherOccupied = [],
}) {
  const isInfirmary = kind === "infirmary";
  const initialCapacity = isInfirmary ? 2 : 6;
  const unlockPrice = isInfirmary ? 1000 : 100;
  const label = isInfirmary ? "soins" : "repos";
  const [selected, setSelected] = useState(null);
  const [popup, setPopup] = useState(null);
  const [error, setError] = useState("");
  const [hover, setHover] = useState(null);
  function place(slot, id = selected) {
    if (!id) {
      setPopup({ type: "pick", slot });
      return;
    }
    setError("");
    setPopup({ type: "place", slot, heroId: id });
  }
  function submit(e) {
    e.preventDefault();
    const raw = new FormData(e.currentTarget).get("remaining");
    if (String(raw).trim() === "") {
      setError("Indiquez la durée du repos.");
      return;
    }
    const result = onChange({
      type: popup.type === "place" ? "place" : "duration",
      slot: popup.slot,
      heroId: popup.heroId,
      remaining: Number(raw),
    });
    if (result?.error) setError(result.error);
    else {
      setPopup(null);
      setSelected(null);
    }
  }
  return (
    <>
      <section
        className={`dorm-board ${isInfirmary ? "infirmary-board" : "dorm-named"}`}
        aria-label="Emplacements de repos"
      >
        <div className="dorm-title">
          <h2>
            {isInfirmary
              ? "Infirmerie de la compagnie"
              : "Dortoirs de la compagnie"}
          </h2>
          <span>
            {dorm.beds.filter(Boolean).length} en {label} · {dorm.capacity}{" "}
            places débloquées
          </span>
        </div>
        <div className="bed-grid">
          {dorm.beds.map((bed, slot) => {
            const hero = warriors.find((w) => w.id === bed?.heroId);
            const locked = slot >= dorm.capacity;
            const purchasable =
              slot === initialCapacity && dorm.capacity === initialCapacity;
            return (
              <div
                className="bed-cell"
                key={slot}
                onDragOver={(e) => {
                  if (!locked && !bed) {
                    e.preventDefault();
                    setHover(slot);
                  }
                }}
                onDragLeave={() => setHover(null)}
                onDrop={(e) => {
                  e.preventDefault();
                  setHover(null);
                  const id = e.dataTransfer.getData("text/plain");
                  if (warriors.some((w) => w.id === id) && !locked && !bed)
                    place(slot, id);
                }}
              >
              <button
                className={`bed-slot ${locked ? "bed-locked" : ""} ${hover === slot ? "drop-target" : ""}`}
                onClick={() => {
                  setError("");
                  if (locked)
                    setPopup({ type: purchasable ? "unlock" : "locked", slot });
                  else if (bed)
                    setPopup({ type: "rest", slot, heroId: bed.heroId });
                  else place(slot);
                }}
                aria-label={
                  locked
                    ? purchasable
                      ? `Débloquer l’emplacement ${slot + 1} pour ${unlockPrice} pièces d’or`
                      : `Emplacement ${slot + 1} verrouillé`
                    : bed
                      ? `${hero?.name}, ${label} restant ${bed.remaining}`
                      : `Emplacement ${slot + 1} libre`
                }
              >
                <span className="bed-frame" aria-hidden="true">
                  <img src="/assets/references/dormitory.png" alt="" />
                </span>
                {bed && hero ? (
                  <>
                    <ReferenceCrop
                      className="bed-portrait"
                      crop={hero.portrait}
                    />
                    <span className="rest-counter" title="Durée du repos">
                      {bed.remaining}
                    </span>
                    <span className="bed-name">{hero.name}</span>
                  </>
                ) : locked ? (
                  <>
                    <span className="bed-lock" aria-hidden="true">
                      <img src="/assets/icons/lock.png" alt="" />
                    </span>
                    {purchasable && <strong>{unlockPrice} Po</strong>}
                  </>
                ) : (
                  <span className="free-bed">Placer un mercenaire</span>
                )}
              </button>
              {onRename && !locked && (
                <input
                  className="bed-player"
                  type="text"
                  maxLength={24}
                  value={names[slot] ?? ""}
                  placeholder="Nom du joueur"
                  aria-label={`Nom du joueur, lit ${slot + 1}`}
                  onChange={(e) => onRename(slot, e.target.value)}
                />
              )}
              </div>
            );
          })}
        </div>
      </section>
      <section className="available-heroes parchment">
        <div className="section-title">
          <div>
            <h2>Mercenaires disponibles</h2>
            <p>
              Sélectionnez un mercenaire puis une place libre, ou glissez son portrait.
            </p>
          </div>
        </div>
        <div className="available-grid">
          {warriors
            .filter(
              (w) =>
                !dorm.beds.some((b) => b?.heroId === w.id) &&
                !otherOccupied.includes(w.id),
            )
            .map((w) => (
              <div className="available-slot" key={w.id}>
                <button
                  className={`available-hero ${selected === w.id ? "selected" : ""}`}
                  aria-pressed={selected === w.id}
                  draggable
                  onDragStart={(e) => {
                    e.dataTransfer.setData("text/plain", w.id);
                    e.dataTransfer.effectAllowed = "move";
                    setSelected(w.id);
                  }}
                  onClick={() => setSelected(selected === w.id ? null : w.id)}
                >
                  <ReferenceCrop crop={w.portrait} />
                  <span>{w.name}</span>
                </button>
                {onDismiss && (
                  <button
                    className="text-button text-button-danger"
                    type="button"
                    aria-label={`Renvoyer ${w.name}`}
                    onClick={() => {
                      setError("");
                      setPopup({ type: "dismiss", heroId: w.id });
                    }}
                  >
                    Renvoyer
                  </button>
                )}
              </div>
            ))}
        </div>
        {warriors.length === 0 ? (
          <p>
            {isInfirmary
              ? "Aucun mercenaire disponible ici pour le moment."
              : "Aucun mercenaire recruté pour le moment : recrutez-en depuis les pages Personnages."}
          </p>
        ) : (
          warriors.every(
            (w) =>
              dorm.beds.some((b) => b?.heroId === w.id) ||
              otherOccupied.includes(w.id),
          ) && (
            <p>
              Tous les mercenaires sont occupés. Libérez-en un au repos, en soins ou à l’entraînement.
            </p>
          )
        )}
        {selected && warriors.some((w) => w.id === selected) && (
          <p role="status" className="placement-status">
            {warriors.find((w) => w.id === selected)?.name} sélectionné :
            choisissez un lit libre.
          </p>
        )}
      </section>
      {popup && (
        <Modal
          title={
            popup.type === "unlock"
              ? "Débloquer un emplacement"
              : popup.type === "locked"
                ? "Emplacement verrouillé"
                : popup.type === "pick"
                  ? "Choisir un mercenaire"
                  : popup.type === "dismiss"
                    ? `Renvoyer ${warriors.find((w) => w.id === popup.heroId)?.name || "le mercenaire"}`
                    : warriors.find((w) => w.id === popup.heroId)?.name || "Repos"
          }
          onClose={() => setPopup(null)}
        >
          {popup.type === "unlock" ? (
            <>
              <p>
                Débloquez une place supplémentaire pour accueillir un
                mercenaire. La trésorerie de la compagnie sera débitée de{" "}
                <strong>{unlockPrice} Po</strong>.
              </p>
              <p>
                Solde actuel : {gold} Po · Après déblocage :{" "}
                {Math.max(0, gold - unlockPrice)} Po
              </p>
              <button
                className="primary"
                disabled={gold < unlockPrice}
                onClick={() => {
                  const result = onUnlock();
                  if (result?.error) setError(result.error);
                  else setPopup(null);
                }}
              >
                Débloquer pour {unlockPrice} Po
              </button>
              {gold < unlockPrice && (
                <p className="error">
                  La compagnie n’a pas assez de pièces d’or.
                </p>
              )}
            </>
          ) : popup.type === "locked" ? (
            <p>
              Le coût de cet emplacement n’a pas encore été renseigné par le
              maître du jeu.
            </p>
          ) : popup.type === "dismiss" ? (
            <>
              <p>
                <strong>
                  {warriors.find((w) => w.id === popup.heroId)?.name}
                </strong>{" "}
                quitte la compagnie. Il redevient disponible sur la page de sa
                classe, où n’importe quel joueur pourra le recruter.
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
                  onClick={async () => {
                    await onDismiss(popup.heroId);
                    setPopup(null);
                    setSelected(null);
                  }}
                >
                  Renvoyer
                </button>
              </div>
            </>
          ) : popup.type === "pick" ? (
            <div className="pick-hero-list">
              {warriors.every(
                (w) =>
                  dorm.beds.some((b) => b?.heroId === w.id) ||
                  otherOccupied.includes(w.id),
              ) && (
                <p>
                  Aucun mercenaire disponible. Libérez un participant dans un
                  autre emplacement.
                </p>
              )}
              {warriors
                .filter(
                  (w) =>
                    !dorm.beds.some((b) => b?.heroId === w.id) &&
                    !otherOccupied.includes(w.id),
                )
                .map((w) => (
                  <button
                    className="wood-button"
                    key={w.id}
                    onClick={() =>
                      setPopup({
                        type: "place",
                        slot: popup.slot,
                        heroId: w.id,
                      })
                    }
                  >
                    {w.name}
                  </button>
                ))}
            </div>
          ) : (
            <form className="rest-form" onSubmit={submit} noValidate>
              <label htmlFor="rest-remaining">Durée de {label} restante</label>
              <input
                id="rest-remaining"
                name="remaining"
                type="number"
                min="0"
                max="5"
                step="1"
                defaultValue={
                  popup.type === "place" ? 1 : dorm.beds[popup.slot]?.remaining
                }
                aria-invalid={!!error}
                aria-describedby={error ? "rest-error" : "rest-help"}
              />
              <p id="rest-help">
                Compteur de 0 à 5, mis à jour manuellement pendant la partie.
                Aucun minuteur réel.
              </p>
              <div className="rest-actions">
                {popup.type === "rest" && (
                  <button
                    className="text-button"
                    type="button"
                    onClick={() => {
                      onChange({ type: "release", slot: popup.slot });
                      setPopup(null);
                    }}
                  >
                    {isInfirmary ? "Terminer les soins" : "Terminer le repos"}
                  </button>
                )}
                {popup.type === "rest" && onDismiss && (
                  <button
                    className="text-button text-button-danger"
                    type="button"
                    onClick={() =>
                      setPopup({ type: "dismiss", heroId: popup.heroId })
                    }
                  >
                    Renvoyer
                  </button>
                )}
                <button className="primary">
                  {popup.type === "place"
                    ? `Placer en ${label}`
                    : "Enregistrer la durée"}
                </button>
              </div>
            </form>
          )}
          {error && (
            <p id="rest-error" className="error" role="alert">
              {error}
            </p>
          )}
        </Modal>
      )}
    </>
  );
}
