// Taches de sang sur le portrait de la fiche d'un mercenaire blessé. Niveau 1 : au moins un tiers de la
// santé perdue (quelques taches) ; niveau 2 : plus des deux tiers perdus (taches denses). Calques semi-
// transparents posés sur l'image (posés tels quels (la multiplication les rend invisibles sur les fonds noirs)), positions en % du portrait : peau (visage,
// cou) et vêtements (torse, bras). Décoratif : ni cliquable ni lu par les lecteurs d'écran.
const TACHES = [
  // Niveau 1
  { n: 1, src: "t1", x: 52, y: 62, w: 34, r: -8, o: 0.85 },
  { n: 1, src: "t3", x: 4, y: 52, w: 36, r: 0, o: 0.8 },
  { n: 1, src: "t5", x: 58, y: 14, w: 26, r: 6, o: 0.8 },
  // Niveau 2 (s'ajoutent aux précédentes)
  { n: 2, src: "t2", x: 14, y: 66, w: 38, r: 12, o: 0.9 },
  { n: 2, src: "t4", x: 60, y: 34, w: 34, r: 0, o: 0.85 },
  { n: 2, src: "t6", x: 2, y: 22, w: 24, r: -10, o: 0.85 },
  { n: 2, src: "t8", x: 30, y: 8, w: 36, r: 20, o: 0.75 },
  { n: 2, src: "t1", x: 6, y: 80, w: 44, r: 170, o: 0.9 },
  { n: 2, src: "t3", x: 56, y: 70, w: 40, r: 190, o: 0.85 },
];

export function TachesSang({ niveau = 0 }) {
  if (!niveau) return null;
  return (
    <span className={`taches-sang taches-niveau-${niveau}`} aria-hidden="true">
      {TACHES.filter((t) => t.n <= niveau).map((t, i) => (
        <img
          key={i}
          src={`/assets/sang/${t.src}.webp`}
          alt=""
          style={{ left: `${t.x}%`, top: `${t.y}%`, width: `${t.w}%`, opacity: t.o, transform: `rotate(${t.r}deg)` }}
        />
      ))}
    </span>
  );
}
