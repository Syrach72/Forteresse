import { ReferenceCrop } from "./Characters.jsx";
// name : libellé du bouton ; racine : nom de la catégorie racine du catalogue
// (table categorie) vers laquelle il renvoie ; icon : /assets/icons/<icon>.png
// ou, à défaut, un détail de l'image de référence du marché (crop).
const CATEGORIES = [
  { name: "Armes", racine: "Armes", crop: [279, 146, 45, 43] },
  { name: "Armures", racine: "Armures", icon: "armurerie" },
  { name: "Objets divers", racine: "Objet divers", crop: [85, 211, 53, 47] },
  { name: "Composants", racine: "Composants", icon: "mushroom" },
  { name: "Matériaux", racine: "Matériaux", icon: "forge" },
  { name: "Produits Alchimiques", racine: "Produits Alchimiques", icon: "magic-items" },
];
export function Market({ onCategory }) {
  return (
    <section className="market-hub" aria-label="Catégories du marché">
      {CATEGORIES.map((c) => (
        <button
          className="market-category parchment"
          key={c.name}
          onClick={() => onCategory(c)}
        >
          {c.icon ? (
            <span className="sprite asset-sprite">
              <img src={`/assets/icons/${c.icon}.png`} alt="" />
            </span>
          ) : (
            <ReferenceCrop crop={c.crop} source="market" sourceWidth={598} />
          )}
          <span>{c.name}</span>
        </button>
      ))}
    </section>
  );
}
