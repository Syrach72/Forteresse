import { useState } from "react";
const fmt = (n) => new Intl.NumberFormat("fr-FR").format(n);
const fmtDate = (d) =>
  d ? new Date(d).toLocaleString("fr-FR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" }) : "";
// Trésorerie PARTAGÉE, refondue le 2026-09-28 (règle de Bruno) : seule une
// recette manuelle reste éditable (par le MJ) ; le reste est calculé en direct
// — entretien mercenaires (dortoir), entretien de la Collecte, achats/embauches/
// déblocages faits depuis le dernier +1 Instance, dernière quête accomplie et
// dernier tribut du village. Chaque nouvelle instance applique ces montants et
// tire un nouveau tribut aléatoire (15 à 30 Po × vétérance moyenne des mercenaires). Présentation en livre
// comptable : deux panneaux de même largeur (Dépenses / Recettes), chacun avec
// son total, et le Solde dans un encart séparé.
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
  const totalDepenses = entretienMercenaires + entretienCollecte + achatsTotal;
  const totalRecettes =
    treasury.income + (derniereQuete?.montant || 0) + (dernierTribut?.montant || 0);
  return (
    <section className="treasury-workspace">
      <div className="treasury-panel parchment">
        <h2>Dépenses</h2>
        <div className="treasury-cost">
          <span>
            Entretien mercenaires
            <small className="treasury-auto">
              {entretienDetail?.mercenaires ?? 0} mercenaire
              {(entretienDetail?.mercenaires ?? 0) > 1 ? "s" : ""} à la caserne ·
              vétérance × 10 · prélevé à chaque instance
            </small>
          </span>
          <strong>{fmt(entretienMercenaires)}</strong>
        </div>
        <div className="treasury-cost">
          <span>
            Entretien Collecte
            <small className="treasury-auto">
              {treasuryLive.entretienCollecte.effectif} employé
              {treasuryLive.entretienCollecte.effectif > 1 ? "s" : ""} (Bûcheron, Mineur,
              Tanneur…) · prélevé à chaque instance
            </small>
          </span>
          <strong>{fmt(entretienCollecte)}</strong>
        </div>
        <div className="treasury-cost treasury-cost-achats">
          <span>
            Achats de l’instance en cours
            <small className="treasury-auto">
              Armes, armures, embauches, déblocages… depuis le dernier +1 Instance
            </small>
            {achatsLignes.length > 0 && (
              <button
                type="button"
                className="treasury-detail-toggle"
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
        </div>
        <div className="treasury-panel-total">
          <span>Total dépenses</span>
          <strong className="expenses">{fmt(totalDepenses)} Po</strong>
        </div>
      </div>
      <div className="treasury-panel parchment">
        <h2>Recettes</h2>
        <div className="treasury-cost">
          <span>
            Autre recette (MJ)
            {estAdmin && (
              <button
                type="button"
                className="treasury-detail-toggle"
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
          </span>
          <strong>{fmt(treasury.income)}</strong>
        </div>
        <div className="treasury-cost">
          <span>
            Dernière quête
            {derniereQuete && (
              <small className="treasury-auto">
                {derniereQuete.message} · {fmtDate(derniereQuete.date)}
              </small>
            )}
          </span>
          <strong>{derniereQuete ? `+${fmt(derniereQuete.montant)}` : "—"}</strong>
        </div>
        <div className="treasury-cost">
          <span>
            Tribut du village
            {dernierTribut && (
              <small className="treasury-auto">
                {dernierTribut.message} · {fmtDate(dernierTribut.date)}
              </small>
            )}
          </span>
          <strong>{dernierTribut ? `+${fmt(dernierTribut.montant)}` : "—"}</strong>
        </div>
        <div className="treasury-panel-total">
          <span>Total recettes</span>
          <strong>{fmt(totalRecettes)} Po</strong>
        </div>
      </div>
      <aside className="treasury-final parchment">
        <h2>Solde</h2>
        <strong>{fmt(gold)} Po</strong>
        <p className="muted">
          La prochaine instance appliquera : −{fmt(entretienMercenaires + entretienCollecte)} Po
          d’entretien, +{fmt(treasury.income)} Po d’autre recette, et un tribut du village
          aléatoire (15 à 30 Po × la vétérance moyenne des mercenaires de la Caserne) — plus la récompense de la quête en cours si elle se termine.
        </p>
        {gold < 0 && (
          <p className="error">
            Solde négatif : les achats sont indisponibles tant qu’il n’est
            pas revenu au-dessus de zéro.
          </p>
        )}
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
