import { useLayoutEffect, useRef } from "react";

// Mise en forme légère des textes (descriptifs, scénarios) : le texte reste une simple chaîne en base,
// avec des balises [b]gras[/b], [i]italique[/i], [u]souligné[/u] et [c=#d4a017]couleur[/c].
// Un texte sans balise s'affiche comme avant. L'affichage fabrique des éléments React (jamais de HTML
// brut) et n'accepte que ces quatre balises avec des couleurs hexadécimales : pas de risque d'injection.
const BALISE = /\[(\/?)(b|i|u|c)(?:=(#[0-9a-fA-F]{3,8}))?\]/g;
const STYLE = {
  b: { fontWeight: "bold" },
  i: { fontStyle: "italic" },
  u: { textDecoration: "underline" },
};

function analyser(texte) {
  const racine = { enfants: [] };
  const pile = [racine];
  let fin = 0;
  const ajouter = (t) => t && pile[pile.length - 1].enfants.push(t);
  for (const m of texte.matchAll(BALISE)) {
    const [brut, fermante, type, couleur] = m;
    ajouter(texte.slice(fin, m.index));
    fin = m.index + brut.length;
    if (fermante) {
      // Une fermeture sans ouverture correspondante reste affichée telle quelle.
      const i = pile.map((n) => n.type).lastIndexOf(type);
      if (i > 0) pile.length = i;
      else ajouter(brut);
    } else if (type === "c" && !couleur) {
      ajouter(brut);
    } else if (type !== "c" && couleur) {
      ajouter(brut);
    } else {
      const noeud = { type, couleur, enfants: [] };
      pile[pile.length - 1].enfants.push(noeud);
      pile.push(noeud);
    }
  }
  ajouter(texte.slice(fin));
  return racine.enfants;
}

function rendre(noeuds) {
  return noeuds.map((n, i) =>
    typeof n === "string" ? (
      n
    ) : (
      <span key={i} style={n.type === "c" ? { color: n.couleur } : STYLE[n.type]}>
        {rendre(n.enfants)}
      </span>
    ),
  );
}

export function RichText({ text }) {
  if (!text) return null;
  return <span style={{ whiteSpace: "pre-wrap" }}>{rendre(analyser(String(text)))}</span>;
}

const COULEURS = [
  ["Rouge", "#b3261e"],
  ["Orange", "#c4651a"],
  ["Or", "#b8860b"],
  ["Vert", "#2e7d32"],
  ["Bleu", "#1f5f99"],
  ["Violet", "#7b3fa0"],
  ["Gris", "#666666"],
];

// Zone de texte avec barre de mise en forme : sélectionner du texte puis cliquer G / I / S / une couleur
// l'entoure de la balise correspondante. `grow` : la hauteur suit le texte (aucune limite).
export function RichTextarea({ id, value, onChange, rows = 3, grow = false }) {
  const ref = useRef(null);
  useLayoutEffect(() => {
    const el = ref.current;
    if (grow && el) {
      el.style.height = "auto";
      el.style.height = `${el.scrollHeight}px`;
    }
  }, [value, grow]);

  function entourer(ouvrante, fermante) {
    const el = ref.current;
    if (!el) return;
    const debut = el.selectionStart;
    const fin = el.selectionEnd;
    onChange(value.slice(0, debut) + ouvrante + value.slice(debut, fin) + fermante + value.slice(fin));
    requestAnimationFrame(() => {
      el.focus();
      el.setSelectionRange(debut + ouvrante.length, fin + ouvrante.length);
    });
  }
  const avecBalises = /\[\/?[biuc](=#[0-9a-fA-F]{3,8})?\]/.test(value || "");

  return (
    <div className="richtext">
      <div className="richtext-barre" role="toolbar" aria-label="Mise en forme du texte">
        <button type="button" title="Gras" aria-label="Gras" onClick={() => entourer("[b]", "[/b]")}>
          <b>G</b>
        </button>
        <button type="button" title="Italique" aria-label="Italique" onClick={() => entourer("[i]", "[/i]")}>
          <i>I</i>
        </button>
        <button type="button" title="Souligné" aria-label="Souligné" onClick={() => entourer("[u]", "[/u]")}>
          <u>S</u>
        </button>
        <span className="richtext-sep" aria-hidden="true" />
        {COULEURS.map(([nom, hex]) => (
          <button
            type="button"
            key={hex}
            className="richtext-couleur"
            style={{ background: hex }}
            title={`Couleur : ${nom}`}
            aria-label={`Couleur ${nom}`}
            onClick={() => entourer(`[c=${hex}]`, "[/c]")}
          />
        ))}
      </div>
      <textarea
        id={id}
        ref={ref}
        rows={rows}
        style={grow ? { overflow: "hidden", resize: "vertical" } : undefined}
        value={value}
        onChange={(e) => onChange(e.target.value)}
      />
      {avecBalises && (
        <p className="richtext-apercu">
          <small>Aperçu :</small> <RichText text={value} />
        </p>
      )}
    </div>
  );
}
