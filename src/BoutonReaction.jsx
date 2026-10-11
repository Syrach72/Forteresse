// Bouton rond « Réaction » : vert bouteille tant que la réaction du round est disponible, grisé une fois
// dépensée. Elle redevient disponible quand le MJ clique sur Rd (règle appliquée côté serveur).
export function BoutonReaction({ utilisee, onClick, disabled = false, taille = "grand" }) {
  return (
    <button
      type="button"
      className={`bouton-reaction bouton-reaction-${taille}${utilisee ? " utilisee" : ""}`}
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
}
