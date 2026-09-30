const fmt = (n) => new Intl.NumberFormat("fr-FR").format(n);
// Journal de la compagnie (partagé) : achats, fabrications, déblocages, budget de chaque
// instance, quêtes… du plus récent au plus ancien. Le serveur n'en garde que les activités des
// 3 dernières instances (l'instance en cours et les 2 précédentes) : les plus anciennes s'effacent.
// Chaque instance est séparée par un bandeau pour ne pas mélanger leurs évènements.
export function Journal({ log }) {
  const groupes = [];
  for (const l of log) {
    const dernier = groupes[groupes.length - 1];
    if (dernier && dernier.instance === l.instance) dernier.lignes.push(l);
    else groupes.push({ instance: l.instance, lignes: [l] });
  }
  return (
    <section className="journal-page parchment">
      <h2>Journal de la compagnie</h2>
      {groupes.length ? (
        groupes.map((g, i) => (
          <div className="journal-instance" key={g.instance}>
            <h3 className="journal-instance-titre">
              Instance {g.instance}
              {i === 0 && <em> · en cours</em>}
            </h3>
            {g.lignes.map((l) => (
              <div className="ledger-row" key={l.id}>
                <span>{l.message}</span>
                <strong>
                  {l.amount ? `${l.amount > 0 ? "+" : ""}${fmt(l.amount)} Po` : "—"}
                </strong>
              </div>
            ))}
          </div>
        ))
      ) : (
        <p>Aucun mouvement pour le moment.</p>
      )}
      <p className="muted">
        Seules les activités des 3 dernières instances sont conservées : les plus anciennes
        s’effacent. Le solde regroupe les achats, les déblocages et le budget de chaque instance.
      </p>
    </section>
  );
}
