const fmt = (n) => new Intl.NumberFormat("fr-FR").format(n);
// Journal de la compagnie (partagé) : achats, fabrications, déblocages, budget de chaque
// instance, quêtes… du plus récent au plus ancien. Le serveur n'en garde que les activités des
// 5 dernières instances (l'instance en cours et les 4 précédentes) : les plus anciennes s'effacent.
export function Journal({ log }) {
  return (
    <section className="journal-page parchment">
      <h2>Journal de la compagnie</h2>
      {log.length ? (
        log.map((l) => (
          <div className="ledger-row" key={l.id}>
            <span>{l.message}</span>
            <strong>
              {l.amount ? `${l.amount > 0 ? "+" : ""}${fmt(l.amount)} Po` : "—"}
            </strong>
          </div>
        ))
      ) : (
        <p>Aucun mouvement pour le moment.</p>
      )}
      <p className="muted">
        Seules les activités des 5 dernières instances sont conservées : les plus anciennes
        s’effacent. Le solde regroupe les achats, les déblocages et le budget de chaque instance.
      </p>
    </section>
  );
}
