import { useState } from "react";
import { ReferenceCrop } from "./Characters.jsx";
export function Training({
  training,
  warriors,
  otherOccupied,
  gold,
  onChange,
  onUnlock,
  Modal,
}) {
  const [popup, setPopup] = useState(null);
  const [error, setError] = useState("");
  const [chosen, setChosen] = useState("");
  const participants = [training.instructor, ...training.students];
  const used = participants.filter(Boolean).map((x) => x.heroId);
  function open(role, index, person) {
    setChosen(person?.heroId || "");
    setError("");
    setPopup({ role, index, person });
  }
  function save(e) {
    e.preventDefault();
    const raw = new FormData(e.currentTarget).get("duration");
    if (!chosen) {
      setError("Choisissez un mercenaire.");
      return;
    }
    if (
      String(raw).trim() === "" ||
      !Number.isInteger(Number(raw)) ||
      Number(raw) < 0 ||
      Number(raw) > 5
    ) {
      setError("Saisissez un entier de 0 à 5.");
      return;
    }
    const result = onChange(popup.role, popup.index, {
      heroId: chosen,
      remaining: Number(raw),
    });
    if (result?.error) setError(result.error);
    else setPopup(null);
  }
  function portrait(person, role, index) {
    const hero = warriors.find((w) => w.id === person?.heroId);
    return (
      <button
        className={`training-place parchment ${role === "instructor" ? "instructor-place" : ""}`}
        aria-label={
          hero
            ? `${role === "instructor" ? "Instructeur" : "Élève"} ${hero.name}, durée ${person.remaining}`
            : `Choisir un ${role === "instructor" ? "instructeur" : "élève"}`
        }
        onClick={() => open(role, index, person)}
      >
        {hero ? (
          <>
            <span className="training-duration">{person.remaining}</span>
            <ReferenceCrop crop={hero.portrait} />
            <strong>{hero.name}</strong>
          </>
        ) : (
          <span>
            Choisir un {role === "instructor" ? "instructeur" : "élève"}
          </span>
        )}
        <small>{role === "instructor" ? "Instructeur" : "Élève"}</small>
      </button>
    );
  }
  return (
    <section className="training-workspace">
      <div className="training-caption">
        <h2>La cour d’entraînement</h2>
        <p>
          Un instructeur, ses élèves. Des compteurs gérés pendant la partie.
        </p>
      </div>
      <div className="training-cohort">
        {portrait(training.instructor, "instructor", 0)}
        {training.students.map((person, index) =>
          index < training.capacity ? (
            <div key={index}>{portrait(person, "student", index)}</div>
          ) : (
            <button
              key={index}
              className="training-place parchment training-locked"
              onClick={() => {
                setError("");
                setPopup({ role: "unlock", index });
              }}
            >
              <span>Emplacement élève</span>
              <strong>100 Po</strong>
              <small>Débloquer</small>
            </button>
          ),
        )}
      </div>
      {popup && (
        <Modal
          title={
            popup.role === "unlock"
              ? "Ajouter une place élève"
              : popup.role === "instructor"
                ? "Instructeur"
                : "Élève"
          }
          onClose={() => setPopup(null)}
        >
          {popup.role === "unlock" ? (
            <>
              <p>
                Ajouter une place d’élève débite 100 Po de la trésorerie de la
                compagnie.
              </p>
              <button
                className="primary"
                disabled={gold < 100}
                onClick={() => {
                  const result = onUnlock();
                  if (result?.error) setError(result.error);
                  else setPopup(null);
                }}
              >
                Débloquer pour 100 Po
              </button>
              {gold < 100 && <p className="error">Trésorerie insuffisante.</p>}
            </>
          ) : (
            <form className="rest-form" onSubmit={save} noValidate>
              <label htmlFor="training-hero">Mercenaire</label>
              <select
                id="training-hero"
                value={chosen}
                onChange={(e) => setChosen(e.target.value)}
              >
                <option value="">Choisir un mercenaire</option>
                {warriors
                  .filter(
                    (w) =>
                      w.id === popup.person?.heroId ||
                      (!used.includes(w.id) && !otherOccupied.includes(w.id)),
                  )
                  .map((w) => (
                    <option key={w.id} value={w.id}>
                      {w.name}
                    </option>
                  ))}
              </select>
              <label htmlFor="training-duration">Durée</label>
              <input
                id="training-duration"
                name="duration"
                type="number"
                min="0"
                max="5"
                step="1"
                defaultValue={popup.person?.remaining ?? 0}
                aria-invalid={!!error}
                aria-describedby={error ? "training-error" : undefined}
              />
              <div className="rest-actions">
                {popup.person && (
                  <button
                    type="button"
                    className="text-button"
                    onClick={() => {
                      onChange(popup.role, popup.index, null);
                      setPopup(null);
                    }}
                  >
                    Retirer le participant
                  </button>
                )}
                <button className="primary">Enregistrer</button>
              </div>
            </form>
          )}
          {error && (
            <p id="training-error" role="alert" className="error">
              {error}
            </p>
          )}
        </Modal>
      )}
    </section>
  );
}
