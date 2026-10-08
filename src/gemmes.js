// Gemmes serties portées par un mercenaire (équipement ET sac à dos, armes et armures confondues) et limite = son
// Mental (Mental saisi + bonus permanents de race ; un effet temporaire de mission ne compte pas). Le serveur applique la
// même règle (_gemmes_portees, sac_dos_envoyer) : ce calcul sert à l'affichage et à l'avertir avant l'envoi.
export function gemmesPortees(equip, sac) {
  let n = 0;
  for (const liste of Object.values(equip || {})) {
    for (const o of liste || []) n += o?.gemmes?.length || 0;
  }
  for (const o of sac || []) n += (o?.gemmes?.length || 0) * (o?.quantite || 1);
  return n;
}
export const limiteGemmes = (merc) => (merc?.mental ?? 0) + (merc?.bonusMental ?? 0);
