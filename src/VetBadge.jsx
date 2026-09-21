// Pastille de vétérance d'un mercenaire : image « laurier » sur laquelle le
// nombre est centré. Utilisée partout où la vétérance d'un mercenaire est
// affichée (Dortoir, Terrain d'Entraînement, fiche, galerie des classes). La
// taille se règle avec la variable CSS --vet.
export function VetBadge({ value, className = "" }) {
  const long = String(value ?? "").length > 2;
  return (
    <span
      className={`vet-badge${long ? " vet-badge-long" : ""} ${className}`.trim()}
      title="Vétérance"
    >
      {value}
    </span>
  );
}
