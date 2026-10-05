// RD (résistance aux dégâts), Immunités et Vulnérabilités d'un mercenaire, lues dans le texte de ses
// compétences PASSIVES (aucune saisie séparée : c'est le descriptif du catalogue qui fait foi).
// Une compétence ne compte que si la vétérance qu'elle exige est atteinte ; dans un texte découpé par
// « [b]Vétérance N[/b] » (écoles arcaniques…), chaque palier ne compte qu'à partir de sa vétérance N.
// Formes reconnues : « RD Poison », « RD Foudre, Tonnerre », « Résistance au Feu », « Immunité aux sorts de
// Sommeil », « est Immunisé aux Maladies », « Vulnérabilité au Feu », « Vulnérable au Froid ».
// Une immunité conditionnelle (« les créatures qui seront Immunisées à l'effet… ») n'est pas reprise.
const TYPES = [
  "Acide", "Contondant", "Feu", "Foudre", "Force", "Froid", "Nécrotique", "Perforant", "Poison",
  "Psychique", "Radiant", "Tonnerre", "Tranchant",
];
const CLE = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
const PAR_CLE = new Map(TYPES.map((t) => [CLE(t), t]));

// Nom de type de dégâts normalisé (« Poisons » -> « Poison »).
function typeCanonique(mot) {
  const k = CLE(mot);
  return PAR_CLE.get(k) || PAR_CLE.get(k.replace(/s$/, "")) || mot;
}

const nettoyer = (t) => t.replace(/\[\/?(?:b|i|u|l)\]|\[\/?c(?:=#[0-9a-fA-F]{3,8})?\]/g, "");
const MAJ = "A-ZÉÈÀÂÎÔÛÇ";
const MOT = `[${MAJ}][^\\s,.;:()\\-]*`;
const LISTE = `${MOT}(?:(?:,\\s*|\\s+et\\s+|\\s+ou\\s+)${MOT})*`;
const FIN = "(?=\\s+-\\s|\\n|\\.\\s|\\.$|;|$)";

function ajouter(liste, valeur) {
  const v = valeur.trim().replace(/\s+/g, " ");
  if (v && !liste.includes(v)) liste.push(v);
}

// Cherche dans un fragment de texte (sans balises) ; les résultats s'ajoutent aux listes.
function lire(texte, rd, immunites, vulnerabilites) {
  for (const m of texte.matchAll(new RegExp(`\\bRD\\s+(${LISTE})`, "g")))
    for (const nom of m[1].split(/,\s*|\s+et\s+|\s+ou\s+/)) ajouter(rd, typeCanonique(nom));
  for (const m of texte.matchAll(
    new RegExp(`\\bR[ée]sistances?\\s+(?:aux?\\s+|à\\s+la\\s+)?(?:d[ée]g[âa]ts\\s+)?(?:de\\s+|d['’])?(${LISTE})`, "g"),
  ))
    for (const nom of m[1].split(/,\s*|\s+et\s+|\s+ou\s+/)) ajouter(rd, typeCanonique(nom));
  for (const m of texte.matchAll(new RegExp(`\\bImmunit[ée]s?\\s+([^\\n.;]*?)${FIN}`, "g"))) ajouter(immunites, m[1]);
  for (const m of texte.matchAll(new RegExp(`\\best\\s+Immunis[ée]e?s?\\s+((?:aux?|à)\\s+[^\\n.;]*?)${FIN}`, "g")))
    ajouter(immunites, m[1]);
  for (const m of texte.matchAll(new RegExp(`\\bVuln[ée]rabilit[ée]s?\\s+([^\\n.;]*?)${FIN}`, "g"))) ajouter(vulnerabilites, m[1]);
  for (const m of texte.matchAll(new RegExp(`\\bVuln[ée]rables?\\s+((?:aux?|à)\\s+[^\\n.;]*?)${FIN}`, "g")))
    ajouter(vulnerabilites, m[1]);
}

// Découpe un descriptif par paliers « [b]Vétérance N[/b] » : [{ min, texte }] (min 0 = avant le premier palier).
function paliers(description) {
  const re = /\[b\]\s*V[ée]t[ée]rance\s+(\d+)\s*\[\/b\]/gi;
  const morceaux = [];
  let dernier = 0;
  let min = 0;
  for (const m of description.matchAll(re)) {
    morceaux.push({ min, texte: description.slice(dernier, m.index) });
    min = Number(m[1]);
    dernier = m.index + m[0].length;
  }
  morceaux.push({ min, texte: description.slice(dernier) });
  return morceaux;
}

// `cellules` : [{ veterance, type, competence: { nom, description } }] ; renvoie les lignes à afficher
// (RD sur une ligne, puis une ligne par Immunité, puis une par Vulnérabilité). Vide si rien.
export function protectionsMercenaire(cellules = [], veterance = 1) {
  const rd = [];
  const immunites = [];
  const vulnerabilites = [];
  for (const c of cellules) {
    if (c.type !== "passive" || !(c.veterance <= veterance) || !c.competence?.description) continue;
    for (const p of paliers(c.competence.description)) {
      if (p.min > veterance) continue;
      lire(nettoyer(p.texte), rd, immunites, vulnerabilites);
    }
  }
  return [
    ...(rd.length ? [`RD ${rd.join(", ")}`] : []),
    ...immunites.map((x) => `Immunité ${x}`),
    ...vulnerabilites.map((x) => `Vulnérabilité ${x}`),
  ];
}
