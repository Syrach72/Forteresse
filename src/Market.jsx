// name : libellé du bouton ; racine : nom de la catégorie racine du catalogue
// (table categorie) vers laquelle il renvoie ; icon : /assets/icons/market-<icon>.png
// dual : ouvre Matériaux et Embauche côte à côte (les employés n'achètent
// pas un objet pour l'arsenal, ils rejoignent la Gestion des Employés).
const CATEGORIES = [
  { name: "Armes", racine: "Armes", icon: "armes" },
  { name: "Armures", racine: "Armures", icon: "armures" },
  { name: "Objets divers", racine: "Objet divers", icon: "objets-divers" },
  { name: "Composants", racine: "Composants", icon: "composants" },
  { name: "Matériaux et Embauche", racine: "Matériaux", icon: "materiaux", dual: true },
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
            <img src={`/assets/icons/market-${c.icon}.png`} alt="" />
          </span>
          <span>{c.name}</span>
        </button>
      ))}
    </section>
  );
}
