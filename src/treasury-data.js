export const INITIAL_TREASURY = {
  income: 3000,
  costs: [
    { id: "entretien", label: "Entretien", amount: 150 },
    { id: "dortoir", label: "Lits Dortoir", amount: 1000 },
    { id: "infirmerie", label: "Lits Infirmerie", amount: 150 },
    { id: "medecin", label: "Médecin", amount: 80 },
    { id: "maitre", label: "Maître d’Armes", amount: 200 },
    { id: "entrainement", label: "Entraînement", amount: 120 },
    { id: "forgeron", label: "Forgeron", amount: 100 },
    { id: "armurier", label: "Armurier", amount: 150 },
    { id: "mage", label: "Mage", amount: 60 },
    { id: "reste", label: "Autres frais à détailler", amount: 85 },
  ],
};
export function treasuryTotal(t) {
  return t.costs.reduce((sum, c) => sum + c.amount, 0);
}
export function changeTreasury(current, change) {
  if (
    !Number.isSafeInteger(change.amount) ||
    change.amount < 0 ||
    change.amount > 10000000
  )
    return { error: "Saisissez un entier de 0 à 10 000 000." };
  if (change.id !== "income" && !current.costs.some((c) => c.id === change.id))
    return { error: "Poste inconnu." };
  const next =
    change.id === "income"
      ? { ...current, income: change.amount }
      : {
          ...current,
          costs: current.costs.map((c) =>
            c.id === change.id ? { ...c, amount: change.amount } : c,
          ),
        };
  return {
    state: next,
    delta:
      next.income -
      treasuryTotal(next) -
      (current.income - treasuryTotal(current)),
  };
}
