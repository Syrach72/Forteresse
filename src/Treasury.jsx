import { useState } from "react";
const fmt = (n) => new Intl.NumberFormat("fr-FR").format(n);
const fmtDate = (d) =>
  d ? new Date(d).toLocaleString("fr-FR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) : "";
// Trésorerie PARTAGÉE, refondue le 2026-09-28 (règle de Bruno) : seule une
// recette manuelle reste éditable (par le MJ) ; le reste est calculé en direct
// — entretien mercenaires (dortoir), entretien de la Collecte, achats/embauches/
// déblocages faits depuis le dernier +1 Instance, dernière quête accomplie et
// dernier tribut du village. Chaque nouvelle instance applique ces montants et
// tire un nouveau tribut aléatoire (50 à 100 Po).
export function Treasury({
  treasury,
  treasuryLive,
  entretienDetail,
  estAdmin = false,
  gold,
  onChange,
  Modal,
}) {
  const [edit, setEdit] = useState(null);
  const [error, setError] = useState("");
  const [detailAchats, setDetailAchats] = useState(false);
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
  const entretienMercenaires = entretienDetail?.montant ?? 0;
  const entretienCollecte = treasuryLive.entretienCollecte.montant;
  const { total: achatsTotal, lignes: achatsLignes } = treasuryLive.achatsInstance;
  const { derniereQuete, dernierTribut } = treasuryLive;
  return (
    <section className="treasury-workspace">
      <div className="treasury-costs">
        <h2 className="sr-only">Dépenses</h2>
        <div className="treasury-cost parchment">
          <span>
            Entretien mercenaires
            <small className="treasury-auto">
              {entretienDetail?.mercenaires ?? 0} mercenaire
              {(entretienDetail?.mercenaires ?? 0) > 1 ? "s" : ""} au dortoir ·
              vétérance × 10 · prélevé à chaque instance
            </small>
          </span>
          <strong>{fmt(entretienMercenaires)}</strong>
          <span aria-hidden="true" />
        </div>
        <div className="treasury-cost parchment">
          <span>
            Entretien Collecte
            <small className="treasury-auto">
              {treasuryLive.entretienCollecte.effectif} employé
              {treasuryLive.entretienCollecte.effectif > 1 ? "s" : ""} (Bûcheron, Mineur,
              Tanneur…) · prélevé à chaque instance
            </small>
          </span>
          <strong>{fmt(entretienCollecte)}</strong>
          <span aria-hidden="true" />
        </div>
        <div className="treasury-cost treasury-cost-achats parchment">
          <span>
            Achats de l’instance en cours
            <small className="treasury-auto">
              Armes, armures, embauches, déblocages… depuis le dernier +1 Instance
            </small>
            {achatsLignes.length > 0 && (
              <button
                type="button"
                className="text-button"
                onClick={() => setDetailAchats((v) => !v)}
              >
                {detailAchats ? "Masquer le détail" : "Voir le détail"}
              </button>
            )}
            {detailAchats && (
              <ul className="treasury-achats-detail">
                {achatsLignes.map((l) => (
                  <li key={l.id}>
                    {l.message} <span className="muted">{fmtDate(l.date)}</span>
                  </li>
                ))}
              </ul>
            )}
          </span>
          <strong>{fmt(achatsTotal)}</strong>
          <span aria-hidden="true" />
        </div>
      </div>
      <aside className="treasury-summary parchment">
        <div>
          <h2>Recettes</h2>
          <div className="treasury-recette-ligne">
            <span>Autre recette (MJ)</span>
            <strong>{fmt(treasury.income)} Po</strong>
          </div>
          {estAdmin && (
            <button
              className="text-button"
              onClick={() => {
                setError("");
                setEdit({
                  id: "income",
                  label: "Autre recette (MJ)",
                  amount: treasury.income,
                });
              }}
            >
              Modifier
            </button>
          )}
          <div className="treasury-recette-ligne">
            <span>Dernière quête</span>
            <strong>
              {derniereQuete ? `+${fmt(derniereQuete.montant)} Po` : "—"}
            </strong>
          </div>
          {derniereQuete && (
            <p className="muted treasury-recette-detail">
              {derniereQuete.message} · {fmtDate(derniereQuete.date)}
            </p>
          )}
          <div className="treasury-recette-ligne">
            <span>Tribut du village</span>
            <strong>
              {dernierTribut ? `+${fmt(dernierTribut.montant)} Po` : "—"}
            </strong>
          </div>
          {dernierTribut && (
            <p className="muted treasury-recette-detail">
              {dernierTribut.message} · {fmtDate(dernierTribut.date)}
            </p>
          )}
        </div>
        <div className="treasury-final">
          <h2>Solde</h2>
          <strong>{fmt(gold)} Po</strong>
          <p className="muted">
            La prochaine instance appliquera : −{fmt(entretienMercenaires + entretienCollecte)} Po
            d’entretien, +{fmt(treasury.income)} Po d’autre recette, et un tribut du village
            aléatoire (50 à 100 Po) — plus la récompense de la quête en cours si elle se termine.
          </p>
          {gold < 0 && (
            <p className="error">
              Solde négatif : les achats sont indisponibles tant qu’il n’est
              pas revenu au-dessus de zéro.
            </p>
          )}
        </div>
      </aside>
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
