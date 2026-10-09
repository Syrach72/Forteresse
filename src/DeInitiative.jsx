import { forwardRef, useEffect, useImperativeHandle, useRef } from "react";

// Dé à 20 faces en 3D (three.js, chargé à la demande) : `ref.lancer(valeur)` anime un lancer qui rebondit sur les
// bordures comme une bille de billard, ralentit et s'arrête au centre sur la face `valeur` (1 à 20), puis rend la
// main. Le nombre est toujours tiré par le serveur ; ce composant ne fait que le montrer. Durée : 2,3 s.
const DUREE = 2300;
const CASE = 256, COLS = 5, LIGNES = 4;
const TRI = [[0.5, 0.04], [0.04, 0.94], [0.96, 0.94]]; // sommets du triangle dans une case : haut, bas-gauche, bas-droite
const ECHELLE_ROULE = 0.78, ECHELLE_FINALE = 1.1;

// Rebond sur les bordures : replie une abscisse du plan déplié dans [-L, L] (triangle de période 4L).
function replier(u, L) {
  let w = (((u + L) % (4 * L)) + 4 * L) % (4 * L);
  if (w > 2 * L) w = 4 * L - w;
  return w - L;
}

function fabriquerAtlas(nombres) {
  const atlas = document.createElement("canvas");
  atlas.width = CASE * COLS;
  atlas.height = CASE * LIGNES;
  const g = atlas.getContext("2d");
  const bruit = (x, y, n, couleur, taille) => {
    g.fillStyle = couleur;
    for (let i = 0; i < n; i++) {
      g.globalAlpha = 0.05 + Math.random() * 0.2;
      g.beginPath();
      g.arc(x + Math.random() * CASE, y + Math.random() * CASE, Math.random() * taille + 1, 0, 7);
      g.fill();
    }
    g.globalAlpha = 1;
  };
  nombres.forEach((nombre, i) => {
    const x = (i % COLS) * CASE, y = Math.floor(i / COLS) * CASE;
    g.save();
    g.beginPath();
    g.rect(x, y, CASE, CASE);
    g.clip();
    g.fillStyle = "#3b2d22";
    g.fillRect(x, y, CASE, CASE);
    bruit(x, y, 500, "#14100c", 14);
    bruit(x, y, 260, "#8a4a22", 9); // rouille
    bruit(x, y, 120, "#b5683a", 5);
    g.strokeStyle = "rgba(190,150,110,.35)";
    g.lineWidth = 5;
    for (let k = 0; k < 3; k++) {
      g.beginPath();
      g.arc(x + CASE * (0.3 + 0.2 * k), y + CASE * 0.78, 22 + k * 8, Math.PI, Math.PI * 2.1);
      g.stroke();
    }
    const cx = x + CASE * 0.5, cy = y + CASE * 0.6;
    g.font = "bold 104px Georgia, serif";
    g.textAlign = "center";
    g.textBaseline = "middle";
    g.lineWidth = 6;
    g.strokeStyle = "#3a2509";
    g.strokeText(String(nombre), cx, cy);
    g.fillStyle = "#e0b04a";
    g.fillText(String(nombre), cx, cy);
    if (nombre === 6 || nombre === 9) g.fillRect(cx - 28, cy + 52, 56, 7); // repère 6 / 9
    g.restore();
  });
  return atlas;
}

export const DeInitiative = forwardRef(function DeInitiative({ largeur = 460, hauteur = 380 }, ref) {
  const canvasRef = useRef(null);
  const etat = useRef(null); // { THREE, rendu, scene, camera, groupe, nombres, normales, pos, LX, LY, enCours }

  useEffect(() => {
    let annule = false;
    let rendu = null;
    (async () => {
      let THREE;
      try {
        THREE = await import("three");
      } catch {
        return;
      }
      if (annule || !canvasRef.current) return;
      try {
        rendu = new THREE.WebGLRenderer({ canvas: canvasRef.current, antialias: true, alpha: true });
      } catch {
        return; // pas de WebGL : lancer() se contentera d'attendre
      }
      rendu.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
      rendu.setSize(largeur, hauteur, false);
      const geo = new THREE.IcosahedronGeometry(1, 0).toNonIndexed();
      const pos = geo.attributes.position;
      const normales = [];
      for (let f = 0; f < 20; f++) {
        const a = new THREE.Vector3().fromBufferAttribute(pos, f * 3);
        const b = new THREE.Vector3().fromBufferAttribute(pos, f * 3 + 1);
        const c = new THREE.Vector3().fromBufferAttribute(pos, f * 3 + 2);
        normales.push(new THREE.Vector3().subVectors(c, b).cross(new THREE.Vector3().subVectors(a, b)).normalize());
      }
      // Numérotation : faces opposées = total 21.
      const nombres = new Array(20).fill(0);
      let suivant = 1;
      for (let f = 0; f < 20; f++) {
        if (nombres[f]) continue;
        const opp = normales.findIndex((n, k) => k !== f && n.dot(normales[f]) < -0.99);
        nombres[f] = suivant;
        nombres[opp] = 21 - suivant;
        suivant++;
      }
      const uv = new Float32Array(20 * 3 * 2);
      for (let f = 0; f < 20; f++) {
        const cx = f % COLS, cy = Math.floor(f / COLS);
        for (let v = 0; v < 3; v++) {
          uv[(f * 3 + v) * 2] = (cx + TRI[v][0]) / COLS;
          uv[(f * 3 + v) * 2 + 1] = 1 - (cy + TRI[v][1]) / LIGNES;
        }
      }
      geo.setAttribute("uv", new THREE.BufferAttribute(uv, 2));
      geo.computeVertexNormals();
      const texture = new THREE.CanvasTexture(fabriquerAtlas(nombres));
      texture.colorSpace = THREE.SRGBColorSpace;
      texture.anisotropy = 4;
      const de = new THREE.Mesh(
        geo,
        new THREE.MeshStandardMaterial({ map: texture, bumpMap: texture, bumpScale: 2.2, roughness: 0.85, metalness: 0.25 }),
      );
      const aretes = new THREE.LineSegments(new THREE.EdgesGeometry(geo), new THREE.LineBasicMaterial({ color: 0x7b5233 }));
      const groupe = new THREE.Group();
      groupe.add(de, aretes);
      const scene = new THREE.Scene();
      scene.add(groupe, new THREE.AmbientLight(0xffe7c2, 1.6));
      const lampe = new THREE.DirectionalLight(0xfff0d0, 2.6);
      lampe.position.set(2, 3, 4);
      scene.add(lampe);
      const camera = new THREE.PerspectiveCamera(32, largeur / hauteur, 0.1, 20);
      camera.position.set(0, 0, 5.2);
      const demiH = camera.position.z * Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));
      const e = {
        THREE, rendu, scene, camera, groupe, nombres, normales, pos,
        LY: demiH - ECHELLE_ROULE,
        LX: demiH * camera.aspect - ECHELLE_ROULE,
        enCours: false,
      };
      etat.current = e;
      groupe.quaternion.copy(orientationFace(e, nombres.indexOf(20)));
      groupe.scale.setScalar(ECHELLE_FINALE);
      rendu.render(scene, camera);
    })();
    return () => {
      annule = true;
      etat.current = null;
      rendu?.dispose();
    };
  }, [largeur, hauteur]);

  // Orientation finale : la face tirée regarde la caméra, son chiffre à l'endroit.
  function orientationFace(e, f) {
    const { THREE, normales, pos } = e;
    const q1 = new THREE.Quaternion().setFromUnitVectors(normales[f], new THREE.Vector3(0, 0, 1));
    const haut = new THREE.Vector3().fromBufferAttribute(pos, f * 3).applyQuaternion(q1);
    const centre = new THREE.Vector3();
    for (let v = 0; v < 3; v++) centre.add(new THREE.Vector3().fromBufferAttribute(pos, f * 3 + v));
    centre.divideScalar(3).applyQuaternion(q1);
    const d = haut.sub(centre);
    const tour = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 0, 1), Math.PI / 2 - Math.atan2(d.y, d.x));
    return tour.multiply(q1);
  }

  useImperativeHandle(ref, () => ({
    lancer(valeur) {
      return new Promise((resolve) => {
        const e = etat.current;
        if (!e) return setTimeout(resolve, 600); // dé pas prêt / pas de WebGL : on passe directement au résultat
        const { THREE, rendu, scene, camera, groupe, nombres, LX, LY } = e;
        const final = orientationFace(e, nombres.indexOf(valeur));
        const axe = new THREE.Vector3(Math.random() - 0.5, Math.random() - 0.5, Math.random() - 0.5).normalize();
        const tours = Math.PI * (7 + Math.random() * 3);
        const signe = () => (Math.random() < 0.5 ? -1 : 1);
        // Trajectoire « billard » : droite dans le plan déplié, repliée par les bordures ; l'arrivée repliée = centre.
        const depart = { x: signe() * LX * (0.6 + Math.random() * 0.4), y: signe() * LY * (0.6 + Math.random() * 0.4) };
        const arrivee = {
          x: signe() * 2 * LX * (2 + Math.floor(Math.random() * 2)),
          y: signe() * 2 * LY * (2 + Math.floor(Math.random() * 2)),
        };
        const debut = performance.now();
        const image = (t) => {
          if (!etat.current) return resolve();
          const p = Math.min(1, (t - debut) / DUREE);
          const ease = 1 - Math.pow(1 - p, 3);
          const reste = new THREE.Quaternion().setFromAxisAngle(axe, tours * (1 - ease));
          groupe.quaternion.copy(reste).multiply(final);
          groupe.position.x = replier(depart.x + (arrivee.x - depart.x) * ease, LX);
          groupe.position.y = replier(depart.y + (arrivee.y - depart.y) * ease, LY);
          groupe.scale.setScalar(ECHELLE_ROULE + (ECHELLE_FINALE - ECHELLE_ROULE) * Math.pow(p, 4));
          if (p >= 1) {
            groupe.position.set(0, 0, 0);
            groupe.scale.setScalar(ECHELLE_FINALE);
          }
          rendu.render(scene, camera);
          if (p < 1) requestAnimationFrame(image);
          else resolve();
        };
        requestAnimationFrame(image);
      });
    },
  }));

  return <canvas ref={canvasRef} className="de-canvas" width={largeur} height={hauteur} aria-hidden="true" />;
});
