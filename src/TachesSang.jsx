// Taches de sang sur le portrait de la fiche d'un mercenaire blessé, comme une vitre posée devant tout le
// portrait. Quatre modèles : deux étirés sur toute la hauteur/largeur (m1, m3), deux gardés tels quels et
// centrés (m2, m4). Le nombre d'effets suit la santé perdue : 1 dès qu'il est blessé, 2 à partir d'un tiers
// perdu, 3 au-delà des deux tiers. Le choix est aléatoire mais stable pour un mercenaire (tiré de son
// identifiant), et les effets s'accumulent au lieu de changer. Décoratif : ni cliquable, ni lu à voix haute.
const MODELES = [
  { src: "m1", etire: true },
  { src: "m2", etire: false },
  { src: "m3", etire: true },
  { src: "m4", etire: false },
];

// Petit générateur déterministe à partir d'un texte (identifiant du mercenaire).
function graine(texte) {
  let h = 2166136261;
  for (const c of String(texte)) h = Math.imul(h ^ c.charCodeAt(0), 16777619);
  return h >>> 0;
}
function melange(seed) {
  const liste = [...MODELES];
  let s = seed || 1;
  for (let i = liste.length - 1; i > 0; i--) {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
    const j = s % (i + 1);
    [liste[i], liste[j]] = [liste[j], liste[i]];
  }
  return liste;
}

export function TachesSang({ niveau = 0, seed = "" }) {
  if (!niveau) return null;
  const choix = melange(graine(seed)).slice(0, Math.min(niveau, MODELES.length));
  return (
    <span className="taches-sang" aria-hidden="true">
      {choix.map((m) => (
        <img key={m.src} className={m.etire ? "etire" : "centre"} src={`/assets/sang/${m.src}.webp`} alt="" />
      ))}
    </span>
  );
}
