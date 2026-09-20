// Maintient le projet Supabase actif. L'offre gratuite met un projet en pause
// après environ une semaine sans activité ; une partie jouée une fois par mois
// serait sinon coupée entre deux séances. Cette fonction est appelée chaque jour
// (vercel.json > crons, et .github/workflows/keepalive.yml en doublon) et lit
// une ligne de trois tables du catalogue (lecture publique). Supabase compte
// comme activité les requêtes qui touchent la base : « quelques requêtes par
// jour » suffisent (docs : free-project-pausing) ; le point /auth/v1/health,
// lui, ne compterait pas.
// N'utilise que les variables déjà présentes dans le projet Vercel (URL et clé
// « anon », publiques par nature) ; aucun secret n'est stocké dans le dépôt.
export default async function handler(req, res) {
  const url = process.env.VITE_SUPABASE_URL;
  const key = process.env.VITE_SUPABASE_ANON_KEY;
  if (!url || !key) {
    res.status(500).json({ ok: false, erreur: "Variables Supabase absentes du projet Vercel." });
    return;
  }
  try {
    const reponses = [];
    for (const table of ["categorie", "classe", "objet_catalogue"]) {
      reponses.push(
        await fetch(`${url}/rest/v1/${table}?select=id&limit=1`, {
          headers: { apikey: key, Authorization: `Bearer ${key}` },
        }),
      );
    }
    const ok = reponses.every((r) => r.ok);
    // Origine de l'appel, pour le suivi affiché dans l'admin : la tâche
    // planifiée de Vercel s'annonce par son user-agent, celle de GitHub par
    // ?source=github ; tout le reste est « manuel ». Noté seulement si les
    // lectures ont réussi, pour que l'indicateur reflète un vrai succès.
    const agent = String(req.headers["user-agent"] || "");
    const source = agent.includes("vercel-cron")
      ? "vercel"
      : req.query?.source === "github"
        ? "github"
        : "manuel";
    let enregistre = false;
    if (ok) {
      try {
        const r = await fetch(`${url}/rest/v1/rpc/enregistrer_maintien`, {
          method: "POST",
          headers: {
            apikey: key,
            Authorization: `Bearer ${key}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ p_source: source }),
        });
        enregistre = r.ok;
      } catch {
        // le suivi est un confort : il ne doit jamais faire échouer le maintien
      }
    }
    res.status(ok ? 200 : 502).json({
      ok,
      source,
      enregistre,
      statuts: reponses.map((r) => r.status),
      le: new Date().toISOString(),
    });
  } catch (e) {
    res.status(502).json({ ok: false, erreur: String(e?.message || e) });
  }
}
