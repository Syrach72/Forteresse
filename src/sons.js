// Sons des fonds animés (Web Audio). La bande-son d'une vidéo est un petit MP3 (quelques dizaines de Ko) chargé à
// l'arrivée sur la page et joué en même temps que la vidéo, recalé en continu sur sa lecture (voir BackdropVideo
// dans App.jsx).
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

// Piste son attachée à UN élément vidéo : `maj(video, poids)` est appelée à chaque image. Elle démarre la bande-son
// à la position de la vidéo, la rejoue si elle dérive de plus de 0,1 s (reprise de la boucle, retard…), l'arrête
// quand la vidéo s'arrête, et règle son niveau sur `poids` (0 à 1 : visibilité de cette vidéo pendant le fondu).
export function creerPiste(tampon, { decalage = 0, gain = 1 } = {}) {
  const etat = { source: null, gain: null, t0: 0, depart: 0 };
  function arreter() {
    if (!etat.source) return;
    const c = contexte;
    try {
      etat.gain.gain.setTargetAtTime(0, c.currentTime, 0.015);
      etat.source.stop(c.currentTime + 0.1);
    } catch {
      // déjà arrêtée
    }
    etat.source = null;
    etat.gain = null;
  }
  function maj(video, poids) {
    const c = contexte;
    if (!c || c.state !== "running" || !tampon) return;
    if (video.paused || video.ended || poids < 0.02) {
      arreter();
      return;
    }
    const t = video.currentTime + decalage;
    if (etat.source && Math.abs(etat.depart + (c.currentTime - etat.t0) - t) > 0.1) arreter();
    if (!etat.source) {
      if (t < 0 || t >= tampon.duration - 0.05) return;
      const source = c.createBufferSource();
      source.buffer = tampon;
      const g = c.createGain();
      g.gain.value = 0;
      source.connect(g).connect(c.destination);
      source.start(0, t);
      source.onended = () => {
        if (etat.source === source) {
          etat.source = null;
          etat.gain = null;
        }
      };
      Object.assign(etat, { source, gain: g, t0: c.currentTime, depart: t });
    }
    etat.gain.gain.setTargetAtTime(volumeSon() * poids * gain, c.currentTime, 0.03);
  }
  return { maj, arreter };
}
