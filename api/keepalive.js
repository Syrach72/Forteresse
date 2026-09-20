// Maintient le projet Supabase actif. L'offre gratuite met un projet en pause
// après environ une semaine sans activité ; une partie jouée une fois par mois
// serait sinon coupée entre deux séances. Cette fonction est appelée chaque jour
// (vercel.json > crons, et .github/workflows/keepalive.yml en doublon) et lit
// une ligne de la table `categorie` (lecture publique du catalogue).
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
    const r = await fetch(`${url}/rest/v1/categorie?select=id&limit=1`, {
      headers: { apikey: key, Authorization: `Bearer ${key}` },
    });
    res.status(r.ok ? 200 : 502).json({ ok: r.ok, statut: r.status, le: new Date().toISOString() });
  } catch (e) {
    res.status(502).json({ ok: false, erreur: String(e?.message || e) });
  }
}
