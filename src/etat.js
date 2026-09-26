import { supabase } from "./supabaseClient";

// Le catalogue (mercenaires, quêtes…) est commun à toutes les sessions ; ce qui évolue en jeu est
// propre à la session active : vétérance d'un mercenaire (mercenaire_etat, repli sur la valeur de la
// fiche) et avancement d'une quête (quete_etat). Ces fonctions relisent le catalogue et y
// superposent l'état de la session courante.

// Mercenaires du catalogue avec la vétérance de la session.
export async function chargerMercenaires(colonnes = "*") {
  const [m, e] = await Promise.all([
    supabase.from("mercenaire").select(colonnes).order("nom"),
    supabase.from("mercenaire_etat").select("mercenaire_id, veterance, energie_actuelle, sante_actuelle"),
  ]);
  if (m.error) return { error: m.error };
  const parId = new Map((e.data || []).map((x) => [x.mercenaire_id, x]));
  return {
    data: m.data.map((x) => {
      const etat = parId.get(x.id);
      return etat
        ? { ...x, veterance: etat.veterance, energie_actuelle: etat.energie_actuelle, sante_actuelle: etat.sante_actuelle }
        : x;
    }),
  };
}

// Énergie et santé actuelles de chaque mercenaire pour la session courante :
// Map id -> { energie, sante } (null = pas encore modifiée : la fiche affiche le maximum).
export async function chargerActuels() {
  const { data, error } = await supabase
    .from("mercenaire_etat")
    .select("mercenaire_id, energie_actuelle, sante_actuelle");
  if (error) return { error };
  return {
    data: new Map(
      data.map((x) => [x.mercenaire_id, { energie: x.energie_actuelle ?? null, sante: x.sante_actuelle ?? null }]),
    ),
  };
}

// Vétérance de chaque mercenaire pour la session courante : Map id -> vétérance.
export async function chargerVeterances() {
  const { data, error } = await chargerMercenaires("id, veterance");
  if (error) return { error };
  return { data: new Map(data.map((m) => [m.id, m.veterance ?? 1])) };
}

// Quêtes du catalogue avec leur état dans la session : en_cours, instances_restantes, terminee_le.
export async function chargerQuetes() {
  const [q, e] = await Promise.all([
    supabase.from("quete").select("*").order("nom"),
    supabase.from("quete_etat").select("quete_id, en_cours, instances_restantes, terminee_le"),
  ]);
  if (q.error) return { error: q.error };
  const parId = new Map((e.data || []).map((x) => [x.quete_id, x]));
  return {
    data: q.data.map((x) => {
      const s = parId.get(x.id);
      return {
        ...x,
        en_cours: !!s?.en_cours,
        instances_restantes: s?.instances_restantes ?? null,
        terminee_le: s?.terminee_le ?? null,
      };
    }),
  };
}

// Quête en cours dans la session (ou null).
export async function chargerQueteEnCours() {
  const { data, error } = await chargerQuetes();
  if (error) return { error };
  const q = data.find((x) => x.en_cours);
  return {
    data: q
      ? {
          id: q.id,
          nom: q.nom,
          en_cours: true,
          instances_requises: q.instances_requises,
          instances_restantes: q.instances_restantes,
        }
      : null,
  };
}
