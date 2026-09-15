import { useState } from "react";
import { ARCANA, MAGE_FORMULAS, availableArcana, findMageFormula } from "./mage.js";
const MIME = "application/x-forteresse-arcana";
// Huit points répartis en octogone autour du centre de la roue (50, 50),
// même principe que les cinq branches du pentagramme d’alchimie.
const POINTS = [
  [50, 12],
  [77, 23],
  [88, 50],
  [77, 77],
  [50, 88],
  [23, 77],
  [12, 50],
  [23, 23],
];
export function ArcanaOrb({ arcana }) {
  return (
    <span className="arcana-orb" style={{ "--arcana-color": arcana.color }} aria-hidden="true" />
  );
}
export function Mage({ mage, inventory, onChange }) {
  const [selected, setSelected] = useState(null);
  const [hover, setHover] = useState(null);
  const [error, setError] = useState("");
  const [lastCast, setLastCast] = useState(null);
  const [notice, setNotice] = useState("");
  const formula = findMageFormula(mage.slots);
  const occupied = mage.slots.filter(Boolean).length;
  function perform(action) {
    const result = onChange(action);
    setError(result?.error || "");
    if (result?.error) return false;
    setSelected(null);
    setLastCast(null);
    if (result?.formula) {
      setLastCast({ ...result.formula, key: crypto.randomUUID() });
      setNotice(`${result.formula.name} ajoutée à l’arsenal. Les arcanes ont été consommées.`);
    } else
      setNotice(
        action.type === "clear"
          ? "Les huit branches sont libérées."
          : action.type === "remove"
            ? "Arcane rendue à l’inventaire."
            : "Roue mise à jour.",
      );
    return true;
  }
  function deposit(slot, payload = selected) {
    if (!payload) {
      setNotice("Choisissez d’abord une arcane dans l’inventaire.");
      return;
    }
    if (payload.kind === "slot") perform({ type: "move", from: payload.slot, to: slot });
    else if (payload.kind === "inventory") perform({ type: "place", slot, id: payload.id });
  }
  function startDrag(e, payload) {
    e.dataTransfer.setData(MIME, JSON.stringify(payload));
    e.dataTransfer.effectAllowed = payload.kind === "slot" ? "move" : "copy";
    setSelected(payload);
  }
  function readDrop(e) {
    e.preventDefault();
    setHover(null);
    try {
      return JSON.parse(e.dataTransfer.getData(MIME));
    } catch {
      return null;
    }
  }
  const selectedName = selected && ARCANA.find((a) => a.id === selected.id)?.name;
  return (
    <section
      className="mage-workspace"
      aria-label="Tour du Mage"
      onKeyDown={(e) => {
        if (e.key === "Escape") {
          setSelected(null);
          setNotice("Sélection annulée.");
        }
      }}
    >
      <div className="mage-intro">
        <p>Glissez les arcanes sur la roue, ou sélectionnez-les puis touchez un emplacement.</p>
        <span>Formules de démonstration · ordre libre · 1 arcane par branche</span>
      </div>
      <div className="mage-table">
        <section className="mage-circle-panel" aria-label="Roue des arcanes">
          <div className="mage-circle-heading">
            <h2>La roue arcanique</h2>
            <button className="text-button" disabled={!occupied} onClick={() => perform({ type: "clear" })}>
              Tout retirer
            </button>
          </div>
          <p className="mage-selection" role="status">
            {selectedName ? `${selectedName} sélectionnée · choisissez une branche` : `${occupied} / 8 branches occupées`}
          </p>
          <div className={`mage-sigil ${formula ? "formula-ready" : ""}`} style={{ "--formula-color": formula?.color || "#8c5bd6" }}>
            {POINTS.map(([x, y], slot) => {
              const id = mage.slots[slot];
              const arcana = ARCANA.find((a) => a.id === id);
              return (
                <div className="sigil-branch" key={slot} style={{ left: `${x}%`, top: `${y}%` }}>
                  <button
                    className={`sigil-target ${id ? "filled" : ""} ${hover === slot ? "drop-active" : ""} ${selected?.kind === "slot" && selected.slot === slot ? "selected" : ""}`}
                    aria-label={`Branche ${slot + 1} : ${arcana?.name || "vide"}`}
                    aria-pressed={selected?.kind === "slot" && selected.slot === slot}
                    draggable={!!id}
                    onDragStart={(e) => id && startDrag(e, { kind: "slot", slot, id })}
                    onDragEnd={() => setHover(null)}
                    onDragOver={(e) => {
                      if (e.dataTransfer.types.includes(MIME)) {
                        e.preventDefault();
                        setHover(slot);
                      }
                    }}
                    onDragLeave={() => setHover(null)}
                    onDrop={(e) => deposit(slot, readDrop(e))}
                    onClick={() => {
                      if (selected) deposit(slot);
                      else if (id) setSelected({ kind: "slot", slot, id });
                      else deposit(slot);
                    }}
                  >
                    {arcana ? <ArcanaOrb arcana={arcana} /> : <span aria-hidden="true">{slot + 1}</span>}
                  </button>
                  {arcana && (
                    <button
                      className="sigil-remove"
                      aria-label={`Retirer ${arcana.name} de la branche ${slot + 1}`}
                      onClick={() => perform({ type: "remove", slot })}
                    >
                      ×
                    </button>
                  )}
                </div>
              );
            })}
            <div className="sigil-center" aria-hidden="true">
              {formula ? "✧" : "◇"}
            </div>
          </div>
          <div className={`mage-result ${lastCast ? "cast-success" : ""}`} key={lastCast?.key || "preview"}>
            <div>
              <span className="mage-result-label">{lastCast ? "Ajoutée à l’arsenal" : "Résultat de l’invocation"}</span>
              <h3>{lastCast?.name || formula?.name || (occupied ? "Combinaison inconnue" : "Choisissez vos arcanes")}</h3>
              <p>
                {lastCast
                  ? "Votre formule est prête."
                  : formula
                    ? `${formula.ingredients.length} arcanes seront consommées.`
                    : occupied
                      ? "Consultez le grimoire ci-contre. Rien n’est consommé."
                      : "Une formule apparaît dès que la combinaison est complète."}
              </p>
            </div>
            <button className="primary mage-cast" disabled={!formula} onClick={() => perform({ type: "brew" })}>
              Invoquer la formule
            </button>
          </div>
          {error && (
            <p role="alert" className="error mage-error">
              {error}
            </p>
          )}
          <p className="sr-only" role="status" aria-live="polite">
            {notice}
          </p>
        </section>
        <aside
          className="mage-inventory parchment"
          aria-label="Inventaire des arcanes"
          onDragOver={(e) => {
            if (selected?.kind === "slot" && e.dataTransfer.types.includes(MIME)) e.preventDefault();
          }}
          onDrop={(e) => {
            const payload = readDrop(e);
            if (payload?.kind === "slot") perform({ type: "remove", slot: payload.slot });
          }}
        >
          <header>
            <h2>Arcanes</h2>
            <span>Quantités disponibles</span>
          </header>
          <div className="arcana-grid">
            {ARCANA.map((arcana) => {
              const count = availableArcana(mage, arcana.id);
              return (
                <button
                  key={arcana.id}
                  className={`arcana-tile ${selected?.kind === "inventory" && selected.id === arcana.id ? "selected" : ""}`}
                  aria-label={`${arcana.name}, ${count} disponibles`}
                  aria-pressed={selected?.kind === "inventory" && selected.id === arcana.id}
                  disabled={count < 1}
                  draggable={count > 0}
                  onDragStart={(e) => startDrag(e, { kind: "inventory", id: arcana.id })}
                  onDragEnd={() => setHover(null)}
                  onClick={() => {
                    setSelected(
                      selected?.kind === "inventory" && selected.id === arcana.id
                        ? null
                        : { kind: "inventory", id: arcana.id },
                    );
                    setError("");
                  }}
                >
                  <ArcanaOrb arcana={arcana} />
                  <b>{count}</b>
                  <span className="arcana-name">{arcana.name}</span>
                </button>
              );
            })}
          </div>
          <details className="mage-formulas" open>
            <summary>Grimoire · {MAGE_FORMULAS.length} formules</summary>
            <div>
              {MAGE_FORMULAS.map((f) => (
                <button
                  type="button"
                  key={f.id}
                  className="mage-formula-card"
                  onClick={() => perform({ type: "fill", formulaId: f.id })}
                >
                  <h3>
                    {f.name} <small>×{inventory.find((i) => i.id === f.output)?.quantity || 0} à l’arsenal</small>
                  </h3>
                  <p>{f.ingredients.map((id) => ARCANA.find((a) => a.id === id).name).join(" + ")}</p>
                </button>
              ))}
            </div>
          </details>
        </aside>
      </div>
    </section>
  );
}
