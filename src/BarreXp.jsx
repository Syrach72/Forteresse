import { xpPalier } from "./xp.js";

// Compteur d'expérience d'un mercenaire : XP acquise dans son niveau de vétérance actuel / XP nécessaire pour
// atteindre le niveau suivant. Au niveau maximum il n'y a plus de palier.
export function BarreXp({ xp = 0, veterance = 1, className = "" }) {
  const palier = xpPalier(veterance);
  if (palier == null) {
    return (
      <div className={`barre-xp barre-xp-max ${className}`.trim()} title="Niveau de vétérance maximal">
        <span className="barre-xp-texte">Niveau maximal</span>
      </div>
    );
  }
  const acquis = Math.max(0, Math.min(xp || 0, palier));
  return (
    <div
      className={`barre-xp ${className}`.trim()}
      title={`${acquis} XP sur ${palier} pour passer à la vétérance ${veterance + 1}`}
      role="meter"
      aria-label="Expérience"
      aria-valuemin={0}
      aria-valuemax={palier}
      aria-valuenow={acquis}
    >
      <span className="barre-xp-jauge" aria-hidden="true">
        <span className="barre-xp-rempli" style={{ width: `${(acquis / palier) * 100}%` }} />
      </span>
      <span className="barre-xp-texte">
        {acquis} / {palier} XP
      </span>
    </div>
  );
}
