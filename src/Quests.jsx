import { useState } from "react";
import { ReferenceCrop } from "./Characters.jsx";
import { ITEMS } from "./data.js";
export const QUESTS = [
  {
    id: "marteau",
    name: "Le Marteau de Feu",
    level: 3,
    text: "Retrouvez l’artefact du prince Galwin dans les mines maudites de Kersang.",
    icon: [16, 60, 33, 32],
  },
  {
    id: "faille",
    name: "La Faille",
    level: 8,
    text: "Description à renseigner.",
    icon: [252, 56, 40, 38],
  },
  {
    id: "dignitaire",
    name: "Le Dignitaire",
    level: 4,
    text: "Description à renseigner.",
    icon: [16, 210, 38, 39],
  },
  {
    id: "gobelin",
    name: "Camp Gobelin",
    level: 3,
    text: "Description à renseigner.",
    icon: [252, 207, 39, 43],
  },
];
export function Quests({ onInventory, onCampaign }) {
  return (
    <section className="quests-workspace">
      <div className="quest-actions">
        <button onClick={onInventory}>
          <ReferenceCrop
            crop={[473, 50, 70, 63]}
            source="quests-page"
            sourceWidth={604}
          />
          <span>Arsenal</span>
        </button>
        <button onClick={onCampaign}>
          <ReferenceCrop
            crop={[551, 49, 49, 64]}
            source="quests-page"
            sourceWidth={604}
          />
          <span>Inventaires de campagne</span>
        </button>
      </div>
      <div className="quest-grid">
        {QUESTS.map((q) => (
          <article key={q.id} className="quest-card">
            <header>
              <ReferenceCrop
                crop={q.icon}
                source="quests-page"
                sourceWidth={604}
              />
              <h2>{q.name}</h2>
              <span
                className="quest-level"
                aria-label={`Vétérance requise : ${q.level}`}
              >
                {q.level}
              </span>
            </header>
            <p>{q.text}</p>
            <small>Vétérance requise : {q.level}</small>
          </article>
        ))}
      </div>
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
