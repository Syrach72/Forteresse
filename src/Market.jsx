import { ReferenceCrop } from "./Characters.jsx";
const CATEGORIES = [
  {
    name: "Objets divers",
    x: 19.5,
    y: 71,
    w: 16,
    h: 29,
    crop: [85, 211, 53, 47],
  },
  { name: "Armes", x: 53.3, y: 49.8, w: 15, h: 25, crop: [279, 146, 45, 43] },
  { name: "Armures", x: 72, y: 65, w: 16, h: 27, crop: [377, 196, 54, 49] },
  {
    name: "Objets magiques",
    x: 89.5,
    y: 64,
    w: 17,
    h: 31,
    crop: [480, 183, 48, 44],
  },
];
export function Market({ onCategory }) {
  return (
    <section className="market-hub" aria-label="Catégories du marché">
      {CATEGORIES.map((c) => (
        <button
          className="market-category parchment"
          key={c.name}
          style={{
            left: `${c.x}%`,
            top: `${c.y}%`,
            width: `${c.w}%`,
            height: `${c.h}%`,
          }}
          onClick={() => onCategory(c.name)}
        >
          {["Armures", "Objets magiques"].includes(c.name) ? (
            <span className="sprite asset-sprite"><img src={`/assets/icons/${c.name === "Armures" ? "armurerie" : "magic-items"}.png`} alt="" /></span>
          ) : <ReferenceCrop crop={c.crop} source="market" sourceWidth={598} />}
          <span>{c.name}</span>
        </button>
      ))}
    </section>
  );
}
