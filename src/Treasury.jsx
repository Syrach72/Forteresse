import { useState } from "react";
import { bilanInstance, treasuryTotal } from "./treasury-data.js";
const fmt = (n) => new Intl.NumberFormat("fr-FR").format(n);
// Budget PARTAGÉ : chaque nouvelle instance ajoute (recettes − dépenses) au
// solde ; seul l'administrateur modifie les montants (le serveur le revérifie).
export function Treasury({
  treasury,
  entretienDetail,
  estAdmin = false,
  gold,
  log,
  onChange,
  Modal,
}) {
  const [edit, setEdit] = useState(null);
  const [error, setError] = useState("");
  async function submit(e) {
    e.preventDefault();
    const value = String(
      new FormData(e.currentTarget).get("amount") || "",
    ).trim();
    if (!value) {
      setError("Saisissez un montant.");
      return;
    }
    const result = await onChange({ id: edit.id, amount: Number(value) });
    if (result?.error) setError(result.error);
    else setEdit(null);
  }
  return (
    <section className="treasury-workspace">
      <div className="treasury-costs">
        <h2 className="sr-only">Frais d’entretien</h2>
        {treasury.costs.map((c) => (
          <div className="treasury-cost parchment" key={c.id}>
            <span>
              {c.label}
              {c.auto && (
                // Entretien calculé : 10 Po par point de vétérance de tous les
                // mercenaires du dortoir, prélevé à chaque nouvelle instance.
                <small className="treasury-auto">
                  {entretienDetail?.mercenaires ?? 0} mercenaire
                  {(entretienDetail?.mercenaires ?? 0) > 1 ? "s" : ""} au dortoir ·
                  vétérance × 10 · prélevé à chaque instance
                </small>
              )}
            </span>
            <strong>{fmt(c.amount)}</strong>
            {c.auto || !estAdmin ? (
              <span aria-hidden="true" />
            ) : (
              <button
                onClick={() => {
                  setError("");
                  setEdit(c);
                }}
                aria-label={`Modifier ${c.label}`}
              >
                Mod.
              </button>
            )}
          </div>
        ))}
      </div>
      <aside className="treasury-summary parchment">
        <div>
          <h2>Dépenses</h2>
          <strong className="expenses">
            {fmt(treasuryTotal(treasury))} Po
          </strong>
        </div>
        <div>
          <h2>Recettes</h2>
          <strong>{fmt(treasury.income)} Po</strong>
          {estAdmin && (
            <button
              className="text-button"
              onClick={() => {
                setError("");
                setEdit({
                  id: "income",
                  label: "Recettes",
                  amount: treasury.income,
                });
              }}
            >
              Modifier les recettes
            </button>
          )}
        </div>
        <div className="treasury-final">
          <h2>Solde</h2>
          <strong>{fmt(gold)} Po</strong>
          <p className="muted">
            Chaque nouvelle instance ajoute recettes − dépenses :{" "}
            <strong>
              {bilanInstance(treasury) > 0 ? "+" : ""}
              {fmt(bilanInstance(treasury))} Po
            </strong>
          </p>
          {gold < 0 && (
            <p className="error">
              Solde négatif : les achats sont indisponibles tant qu’il n’est
              pas revenu au-dessus de zéro.
            </p>
          )}
        </div>
      </aside>
      <section className="treasury-journal parchment">
        <h2>Journal de la compagnie</h2>
        {log.length ? (
          log.slice(0, 15).map((l) => (
            <div className="ledger-row" key={l.id}>
              <span>{l.message}</span>
              <strong>
                {l.amount
                  ? `${l.amount > 0 ? "+" : ""}${fmt(l.amount)} Po`
                  : "—"}
              </strong>
            </div>
          ))
        ) : (
          <p>Aucun mouvement pour le moment.</p>
        )}
        <p className="muted">
          Le solde regroupe les achats, les déblocages et le budget de chaque
          instance.
        </p>
      </section>
      {edit && (
        <Modal title={`Modifier ${edit.label}`} onClose={() => setEdit(null)}>
          <form className="rest-form" onSubmit={submit} noValidate>
            <label htmlFor="treasury-amount">Montant en pièces d’or</label>
            <input
              id="treasury-amount"
              name="amount"
              type="number"
              min="0"
              max="10000000"
              step="1"
              defaultValue={edit.amount}
              aria-invalid={!!error}
              aria-describedby={error ? "treasury-error" : undefined}
            />
            {error && (
              <p className="error" role="alert" id="treasury-error">
                {error}
              </p>
            )}
            <p>Le nouveau montant s’applique à partir de la prochaine instance.</p>
            <div className="rest-actions">
              <button
                type="button"
                className="text-button"
                onClick={() => setEdit(null)}
              >
                Annuler
              </button>
              <button className="primary">Enregistrer le montant</button>
            </div>
          </form>
        </Modal>
      )}
    </section>
  );
}
