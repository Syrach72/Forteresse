// Budget de la compagnie PARTAGÉ (table budget_poste, lue par tous, modifiée par
// l'administrateur seul via budget_modifier). Au début de chaque nouvelle
// instance (+1 Instance), le serveur ajoute au solde (recettes − dépenses) ; les
// dépenses = tous les postes + l'entretien calculé. Les postes autres que
// l'entretien sont fictifs pour le moment (Bruno choisira ceux qu'il garde).
// Forme d'affichage : { income, costs: [{ id, label, amount, auto }] }.
export const EMPTY_TREASURY = { income: 0, costs: [] };
export function buildTreasury(rows = []) {
  const tri = [...rows].sort((a, b) => (a.ordre ?? 0) - (b.ordre ?? 0));
  return {
    income: tri
      .filter((r) => r.nature === "recette")
      .reduce((somme, r) => somme + (Number(r.montant) || 0), 0),
    costs: tri
      .filter((r) => r.nature === "depense")
      .map((r) => ({
        id: r.code,
        label: r.libelle,
        amount: Number(r.montant) || 0,
        auto: !!r.auto,
      })),
  };
}
export function treasuryTotal(t) {
  return t.costs.reduce((sum, c) => sum + c.amount, 0);
}
// Ce que chaque nouvelle instance ajoute au solde (recettes − dépenses).
export function bilanInstance(t) {
  return t.income - treasuryTotal(t);
}
// Entretien de la compagnie (règle de Bruno) : 10 Po par point de vétérance de
// TOUS les mercenaires du dortoir (recrutés, actifs ou grisés). Poste calculé,
// pas saisi : le serveur (entretien_montant) le compte dans les dépenses de
// chaque instance ; cette fonction ne sert qu'à l'affichage.
export const ENTRETIEN_PAR_VETERANCE = 10;
export function entretienCompagnie(veterances = []) {
  return (
    veterances.reduce((somme, v) => somme + Math.max(0, Math.trunc(Number(v)) || 0), 0) *
    ENTRETIEN_PAR_VETERANCE
  );
}
