// Bouton rond « Réaction » : vert bouteille tant que la réaction du round est disponible, grisé une fois
// dépensée. Elle redevient disponible quand le MJ clique sur Rd (règle appliquée côté serveur).
// `anneau` : le bouton est serti dans l'anneau de bronze (mercenaires, compagnons et familiers) ; les fiches de
// créatures du MJ gardent un simple bouton rond.
export function BoutonReaction({ utilisee, onClick, disabled = false, taille = "grand", anneau = false }) {
  const bouton = (
    <button
      type="button"
      className={`bouton-reaction bouton-reaction-${taille}${anneau ? " bouton-reaction-serti" : ""}${utilisee ? " utilisee" : ""}`}
      onClick={onClick}
      disabled={disabled}
      aria-pressed={!!utilisee}
      title={
        utilisee
          ? "Réaction dépensée : elle redevient disponible au prochain Rd"
          : "Réaction disponible : cliquez pour la dépenser"
      }
    >
      <span>Réaction</span>
    </button>
  );
  if (!anneau) return bouton;
  return (
    <div className={`reaction-anneau reaction-anneau-${taille}`}>
      {bouton}
      <img src="/assets/icons/anneau-reaction.webp" alt="" aria-hidden="true" draggable="false" />
    </div>
  );
}
