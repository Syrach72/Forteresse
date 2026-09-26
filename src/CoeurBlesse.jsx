// Cœur pulsant : signale qu'un mercenaire n'a pas récupéré toute sa santé (santé actuelle < santé max).
// Icône dessinée ici (SVG) ; l'animation « battement » est dans styles.css (.coeur-blesse).
export function CoeurBlesse({ className = "" }) {
  return (
    <span
      className={`coeur-blesse${className ? ` ${className}` : ""}`}
      role="img"
      aria-label="Blessé : santé incomplète"
      title="Blessé : santé incomplète"
    >
      <svg viewBox="0 0 32 30" aria-hidden="true">
        <defs>
          <radialGradient id="coeur-degrade" cx="35%" cy="30%" r="80%">
            <stop offset="0%" stopColor="#ff8a7a" />
            <stop offset="45%" stopColor="#d3202a" />
            <stop offset="100%" stopColor="#7a0c16" />
          </radialGradient>
        </defs>
        <path
          d="M16 28.5C7 21.2 2 16.6 2 10.3 2 6 5.2 3 9 3c3 0 5.4 1.6 7 4.2C17.600 4.600 20 3 23 3c3.800 0 7 3 7 7.300 0 6.300-5 10.900-14 18.200Z"
          fill="url(#coeur-degrade)"
          stroke="#3a0509"
          strokeWidth="1.600"
          strokeLinejoin="round"
        />
        <path d="M8 8.500c1.200-1.500 3.200-1.800 4.400-.9" fill="none" stroke="#ffd2c8" strokeWidth="1.800" strokeLinecap="round" opacity=".85" />
      </svg>
    </span>
  );
}
