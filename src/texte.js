// Vocabulaire : le « dortoir » s'appelle « Caserne » partout où le joueur lit du texte. Les messages écrits
// par le serveur (erreurs, journal de la compagnie) sont traduits ici, sans toucher à l'historique de la base.
export function caserne(texte) {
  if (typeof texte !== "string" || !/dortoir/i.test(texte)) return texte;
  return texte
    .replace(/\bAu dortoir/g, "À la caserne")
    .replace(/\bAu Dortoir/g, "À la Caserne")
    .replace(/\bau dortoir/g, "à la caserne")
    .replace(/\bau Dortoir/g, "à la Caserne")
    .replace(/\bdu dortoir/g, "de la caserne")
    .replace(/\bdu Dortoir/g, "de la Caserne")
    .replace(/\bDu dortoir/g, "De la caserne")
    .replace(/\ble dortoir/g, "la caserne")
    .replace(/\ble Dortoir/g, "la Caserne")
    .replace(/\bLe dortoir/g, "La caserne")
    .replace(/\bLe Dortoir/g, "La Caserne")
    .replace(/\bdortoirs\b/g, "casernes")
    .replace(/\bDortoirs\b/g, "Casernes")
    .replace(/\bdortoir\b/g, "caserne")
    .replace(/\bDortoir\b/g, "Caserne");
}

// Traduit récursivement les textes d'une réponse du serveur (message d'erreur, champ `message`…).
export function caserneReponse(r) {
  if (!r || typeof r !== "object") return r;
  let sortie = r;
  if (r.error && typeof r.error.message === "string") {
    const m = caserne(r.error.message);
    if (m !== r.error.message) sortie = { ...sortie, error: { ...r.error, message: m } };
  }
  if (r.data && typeof r.data === "object" && typeof r.data.message === "string") {
    const m = caserne(r.data.message);
    if (m !== r.data.message) sortie = { ...sortie, data: { ...r.data, message: m } };
  }
  return sortie;
}
