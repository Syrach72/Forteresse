// Bruitages des fonds animés (Web Audio). Les sons sont de petits MP3 (quelques dizaines de Ko) chargés à
// l'arrivée sur la page ; ils se déclenchent à des instants précis de la vidéo (voir BackdropVideo dans App.jsx).
//
// Les navigateurs interdisent le son tant que le visiteur n'a pas agi sur le site (clic, touche) : le
// contexte audio est réveillé au premier geste. Après la connexion ou un clic dans le menu, le son démarre donc
// dès l'arrivée sur la page ; seul un rechargement direct sur la page attend le premier clic.
// Le volume est lu dans le navigateur (clé ci-dessous, 0 à 1) : la future commande de volume n'aura qu'à l'écrire.
const CLE_VOLUME = "forteresse-son-volume";
const VOLUME_DEFAUT = 0.6;

let contexte = null;
const cache = new Map();

export function volumeSon() {
  try {
    const v = parseFloat(localStorage.getItem(CLE_VOLUME));
    return Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : VOLUME_DEFAUT;
  } catch {
    return VOLUME_DEFAUT;
  }
}

function obtenirContexte() {
  if (contexte) return contexte;
  const AC = typeof window !== "undefined" && (window.AudioContext || window.webkitAudioContext);
  if (!AC) return null;
  contexte = new AC();
  return contexte;
}

// Réveil du son au premier geste du visiteur.
if (typeof window !== "undefined") {
  const reveiller = () => {
    const c = obtenirContexte();
    if (c && c.state === "suspended") c.resume().catch(() => {});
  };
  for (const evenement of ["pointerdown", "keydown", "touchstart"]) {
    window.addEventListener(evenement, reveiller, { passive: true });
  }
}

// Charge et décode un son (une seule fois par adresse). Renvoie null en cas d'échec : le jeu reste muet.
export function chargerSon(url) {
  if (cache.has(url)) return cache.get(url);
  const promesse = (async () => {
    const c = obtenirContexte();
    if (!c) return null;
    const reponse = await fetch(url);
    if (!reponse.ok) return null;
    return await c.decodeAudioData(await reponse.arrayBuffer());
  })().catch(() => null);
  cache.set(url, promesse);
  return promesse;
}

// Joue un son décodé ; `poids` (0 à 1) règle son niveau relatif. Rien ne se joue tant que le contexte n'est pas
// réveillé (on évite d'empiler des sons en retard).
export function jouerSon(tampon, poids = 1) {
  const c = contexte;
  if (!c || !tampon || c.state !== "running") return;
  const niveau = volumeSon() * poids;
  if (niveau < 0.005) return;
  const source = c.createBufferSource();
  source.buffer = tampon;
  const gain = c.createGain();
  gain.gain.value = niveau;
  source.connect(gain).connect(c.destination);
  source.start();
}
