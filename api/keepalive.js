// Maintient le projet Supabase actif. L'offre gratuite met un projet en pause
// après environ une semaine sans activité ; une partie jouée une fois par mois
// serait sinon coupée entre deux séances. Cette fonction est appelée chaque jour
// (vercel.json > crons, et .github/workflows/keepalive.yml en doublon) et fait une
// ÉCRITURE dans la base : elle note l'heure du dernier passage (fonction
// enregistrer_maintien, table maintien, affichée dans l'administration). C'est de
// l'activité base de données ; le point /auth/v1/health, lui, ne compterait pas.
// N'utilise que les variables déjà présentes dans le projet Vercel (URL et clé
// « anon », publiques par nature) ; aucun secret n'est stocké dans le dépôt.
// Le rôle « anon » n'a le droit d'exécuter que cette fonction et invitation_valide
// (migration 20261005200000_durcissement_anon.sql) : plus de lecture de tables.
export default async function handler(req, res) {
  const url = process.env.VITE_SUPABASE_URL;
  const key = process.env.VITE_SUPABASE_ANON_KEY;
  if (!url || !key) {
    res.status(500).json({ ok: false, erreur: "Variables Supabase absentes du projet Vercel." });
    return;
  }
  try {
    // Origine de l'appel, pour le suivi affiché dans l'admin : la tâche
    // planifiée de Vercel s'annonce par son user-agent, celle de GitHub par
    // ?source=github ; tout le reste est « manuel ».
    const agent = String(req.headers["user-agent"] || "");
    const source = agent.includes("vercel-cron")
      ? "vercel"
      : req.query?.source === "github"
        ? "github"
        : "manuel";
    const r = await fetch(`${url}/rest/v1/rpc/enregistrer_maintien`, {
      method: "POST",
      headers: {
        apikey: key,
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ p_source: source }),
    });
    res.status(r.ok ? 200 : 502).json({
      ok: r.ok,
      source,
      statut: r.status,
      le: new Date().toISOString(),
    });
  } catch (e) {
    res.status(502).json({ ok: false, erreur: String(e?.message || e) });
  }
}
