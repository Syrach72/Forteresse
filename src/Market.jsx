// name : libellé du bouton ; racine : nom de la catégorie racine du catalogue
// (table categorie) vers laquelle il renvoie ; icon : /assets/icons/market-<icon>.webp
// Matériaux et Embauche a quitté le Marché (Bruno, 2026-09-29) : ce bouton se trouve sur la page Ressources.
const CATEGORIES = [
  { name: "Armes", racine: "Armes", icon: "armes" },
  { name: "Armures", racine: "Armures", icon: "armures" },
  { name: "Objets divers", racine: "Objet divers", icon: "objets-divers" },
  { name: "Composants", racine: "Composants", icon: "composants" },
  { name: "Produits Alchimiques", racine: "Produits Alchimiques", icon: "alchimie" },
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
          <span className="sprite asset-sprite">
            <img src={`/assets/icons/market-${c.icon}.webp`} alt="" />
          </span>
          <span>{c.name}</span>
        </button>
      ))}
    </section>
  );
}
