// Sons des fonds animés (Web Audio). La bande-son d'une vidéo est un petit MP3 (quelques dizaines de Ko) chargé à
// l'arrivée sur la page et joué en même temps que la vidéo, recalé en continu sur sa lecture (voir BackdropVideo
// dans App.jsx). UN SEUL son joue à la fois : à chaque reprise de la boucle, le précédent est coupé aussitôt.
//
// Les navigateurs interdisent le son tant que le visiteur n'a pas agi sur le site (clic, touche) : le
// contexte audio est réveillé au premier geste. Après la connexion ou un clic dans le menu, le son démarre donc
// dès l'arrivée sur la page ; seul un rechargement direct sur la page attend le premier clic.
// Le volume est lu dans le navigateur (clé ci-dessous, 0 à 1) : la future commande de volume n'aura qu'à l'écrire.
const CLE_VOLUME = "forteresse-son-volume";
const VOLUME_DEFAUT = 0.6;

let contexte = null;
const cache = new Map();
// Toutes les sources en cours de lecture : on peut ainsi tout couper d'un coup (changement de page, onglet masqué).
const actives = new Set();

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

// Coupe tout de suite (fondu de 40 ms pour éviter le claquement) toutes les sources en cours.
export function arreterTout() {
  const c = contexte;
  if (!c) return;
  for (const { source, gain } of [...actives]) {
    try {
      gain.gain.cancelScheduledValues(c.currentTime);
      gain.gain.setTargetAtTime(0, c.currentTime, 0.01);
      source.stop(c.currentTime + 0.06);
    } catch {
      // déjà arrêtée
    }
  }
  actives.clear();
}

if (typeof window !== "undefined") {
  // Réveil du son au premier geste du visiteur.
  const reveiller = () => {
    const c = obtenirContexte();
    if (c && c.state === "suspended") c.resume().catch(() => {});
  };
  for (const evenement of ["pointerdown", "keydown", "touchstart"]) {
    window.addEventListener(evenement, reveiller, { passive: true });
  }
  // Sécurité : changer de page ou masquer l'onglet coupe tout (la page suivante relance son propre son si elle en a).
  window.addEventListener("hashchange", arreterTout);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) arreterTout();
  });
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

// Piste son d'une vidéo de fond : `maj(video)` est appelée à chaque image avec la vidéo « de tête » (la plus récemment
// relancée). Elle démarre la bande-son à la position de cette vidéo, la rejoue si elle dérive de plus de 0,1 s (reprise
// de la boucle, changement de vidéo de tête…) en coupant l'ancienne, et l'arrête quand plus rien ne joue.
export function creerPiste(tampon, { decalage = 0, gain = 1 } = {}) {
  const etat = { entree: null, t0: 0, depart: 0 };
  function arreter() {
    const c = contexte;
    const entree = etat.entree;
    etat.entree = null;
    if (!entree || !c) return;
    try {
      entree.gain.gain.cancelScheduledValues(c.currentTime);
      entree.gain.gain.setTargetAtTime(0, c.currentTime, 0.01);
      entree.source.stop(c.currentTime + 0.06);
    } catch {
      // déjà arrêtée
    }
    actives.delete(entree);
  }
  function maj(video) {
    const c = contexte;
    if (!c || c.state !== "running" || !tampon || document.hidden) return;
    // l'entrée a pu être coupée de l'extérieur (arreterTout) : on repart de zéro
    if (etat.entree && !actives.has(etat.entree)) etat.entree = null;
    const t = video.currentTime + decalage;
    if (etat.entree && Math.abs(etat.depart + (c.currentTime - etat.t0) - t) > 0.1) arreter();
    if (!etat.entree) {
      if (t < 0 || t >= tampon.duration - 0.05) return;
      const source = c.createBufferSource();
      source.buffer = tampon;
      const g = c.createGain();
      g.gain.value = volumeSon() * gain;
      source.connect(g).connect(c.destination);
      source.start(0, t);
      const entree = { source, gain: g };
      source.onended = () => {
        actives.delete(entree);
        if (etat.entree === entree) etat.entree = null;
      };
      actives.add(entree);
      Object.assign(etat, { entree, t0: c.currentTime, depart: t });
    } else {
      etat.entree.gain.gain.setTargetAtTime(volumeSon() * gain, c.currentTime, 0.03);
    }
  }
  return { maj, arreter };
}
