import { RichText } from "./RichText.jsx";
import { Fragment, useState } from "react";

// Fiche d'un mercenaire : emplacements d'équipement (3 armes, 1 armure,
// 3 objets) et tableau de compétences (10 lignes de vétérance, 3 cellules
// passives puis 5 actives). Partagé entre la fiche joueur (Characters.jsx) et
// l'éditeur de l'administration (Admin.jsx).

// Icône de base d'une arme quand le catalogue n'en précise pas : celle de Puissance.
export const ICONE_ARME_PAR_DEFAUT = "/assets/icons/puissance.webp";

export const NIVEAUX_VETERANCE = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

// Une cellule du tableau : le cadre fourni, la vétérance requise de sa ligne
// et, si le MJ en a placé une, l'icône de la compétence. Grisée tant que la
// vétérance du mercenaire n'atteint pas celle de la ligne ; toujours cliquable.
export function CelluleCompetence({ niveau, type, position, competence, grisee, onClick, selectionnee }) {
  const nom = competence?.nom;
  return (
    <button
      type="button"
      className={`comp-cell${grisee ? " comp-cell-grisee" : ""}${selectionnee ? " comp-cell-selectionnee" : ""}`}
      onClick={onClick}
      aria-label={`Compétence ${type === "passive" ? "passive" : "active"} ${position + 1}, vétérance ${niveau}${nom ? ` : ${nom}` : " : vide"}`}
      title={nom ? `${nom} (vétérance ${niveau})` : `Vétérance ${niveau}`}
    >
      {competence?.icone && <img className="comp-icone" src={competence.icone} alt="" loading="lazy" decoding="async" />}
      <span className="comp-niveau" aria-hidden="true">
        {niveau}
      </span>
    </button>
  );
}

// `cellules` : [{ veterance, type, position, competence: { nom, description, icone } }].
// `veterance` : vétérance en cours du mercenaire (les lignes au-dessus sont grisées) ;
// null = aucune ligne grisée (éditeur de l'administration).
// `apresLigne(niveau)` : contenu optionnel inséré sous une ligne (l'éditeur de l'administration y
// place son choix de compétence, à côté de la cellule cliquée).
export function TableauCompetences({ cellules = [], veterance = null, onCell, selection = null, apresLigne = null }) {
  const parCle = new Map(cellules.map((c) => [`${c.veterance}:${c.type}:${c.position}`, c]));
  const cellule = (niveau, type, position) => (
    <CelluleCompetence
      key={`${type}${position}`}
      niveau={niveau}
      type={type}
      position={position}
      competence={parCle.get(`${niveau}:${type}:${position}`)?.competence}
      grisee={veterance !== null && niveau > veterance}
      selectionnee={selection?.niveau === niveau && selection?.type === type && selection?.position === position}
      onClick={() => onCell?.({ niveau, type, position, competence: parCle.get(`${niveau}:${type}:${position}`)?.competence || null })}
    />
  );
  return (
    <div className="comp-table">
      <div className="comp-legendes">
        <span className="comp-legende comp-legende-passives">Compétences passives</span>
        <span className="comp-legende comp-legende-actives">Compétences actives</span>
      </div>
      {NIVEAUX_VETERANCE.map((niveau) => (
        <Fragment key={niveau}>
          <div className="comp-ligne">
            {[0, 1, 2].map((p) => cellule(niveau, "passive", p))}
            <span className="comp-espace" aria-hidden="true" />
            {[0, 1, 2, 3, 4].map((p) => cellule(niveau, "active", p))}
          </div>
          {apresLigne?.(niveau)}
        </Fragment>
      ))}
    </div>
  );
}

// Niveau de parade : I, II ou III (les chiffres 1 à 3 sont acceptés). Renvoie 0 si absent.
export function rangParade(p) {
  const t = String(p ?? "").trim().toUpperCase();
  return { I: 1, II: 2, III: 3, 1: 1, 2: 2, 3: 3 }[t] || 0;
}
// Les parades de l'arme et du bouclier ne se cumulent pas : seule la plus élevée compte.
export function meilleureParade(equip) {
  if (!equip) return null;
  const candidats = [...(equip.arme || []), ...(equip.bouclier || [])].map((o) => o?.parade).filter(Boolean);
  let meilleur = null;
  for (const p of candidats) if (rangParade(p) > rangParade(meilleur)) meilleur = String(p).trim().toUpperCase();
  return meilleur;
}
// Allonge 0 (ou vide) : rien à indiquer.
const aUneValeur = (v) => v !== null && v !== undefined && String(v).trim() !== "" && Number(v) !== 0;
// Orbe de santé (rouge) ou d'énergie (bleue) : la valeur actuelle en grand, le maximum dessous.
// Éditable (le joueur qui a recruté le mercenaire, ou le MJ) : l'actuelle est un champ de saisie.
// Jamais plus de 3 chiffres ; les tailles suivent la largeur de l'orbe (unités de conteneur).
export function Orbe({ type, libelle, id, actuelle, max, editable = false, valeur = "", onChange }) {
  return (
    <div className={`orbe orbe-${type}`}>
      <div className="orbe-image">
        <div className="orbe-contenu">
          {editable ? (
            <input
              id={id}
              className="orbe-actuelle orbe-saisie"
              type="number"
              inputMode="numeric"
              min="0"
              max="999"
              step="1"
              value={valeur}
              aria-label={`${libelle} actuelle`}
              onChange={(e) => onChange?.(e.target.value.slice(0, 3))}
            />
          ) : (
            <span className="orbe-actuelle" aria-label={`${libelle} actuelle`}>
              {actuelle ?? "—"}
            </span>
          )}
          <span className="orbe-max" aria-label={`${libelle} maximum`}>
            Max : {max ?? "—"}
          </span>
        </div>
      </div>
      <label className="orbe-libelle" htmlFor={editable ? id : undefined}>
        {libelle}
      </label>
    </div>
  );
}

const valeur = (v) => (v === null || v === undefined || v === "" ? "—" : v);

// Emplacements d'équipement : `equip` = { arme: [3], armure: [1], objet: [3] }
// (chaque entrée : fiche de l'objet ou null). Déséquiper renvoie l'objet au sac.
// Badges F / D à côté de la mention « Parade » d'une arme ou d'un bouclier équipé. F (blanc, puis rouge au
// clic, et inversement) déverrouille D ; D demande une confirmation puis détruit l'objet : il est retiré du
// mercenaire et la moitié de ses composants (arrondie à l'inférieur) rejoint l'arsenal.
function BadgesParade({ emplacement, position, nom, actif, onDetruire, onBasculerF, busy }) {
  const f = !!actif;
  const [confirmer, setConfirmer] = useState(false);
  if (!onDetruire) return null;
  return (
    <span className="badges-parade">
      <button
        type="button"
        className={`badge-parade badge-f${f ? " actif" : ""}`}
        aria-pressed={f}
        title={f ? "F activé (cliquer pour désactiver)" : "F : déverrouille la destruction (D)"}
        disabled={busy}
        onClick={() => {
          setConfirmer(false);
          onBasculerF?.(emplacement, position, !f);
        }}
      >
        F
      </button>
      <button
        type="button"
        className="badge-parade badge-d"
        disabled={!f || busy}
        title={f ? `D : détruire ${nom}` : "D est verrouillé tant que F n’est pas rouge"}
        onClick={() => setConfirmer(true)}
      >
        D
      </button>
      {confirmer && (
        <span className="badges-parade-confirm" role="alertdialog" aria-label="Confirmer la destruction">
          Détruire {nom} ? Irréversible.{" "}
          <button
            type="button"
            className="text-button"
            disabled={busy}
            onClick={() => {
              setConfirmer(false);
              onDetruire(emplacement, position, nom);
            }}
          >
            Confirmer
          </button>{" "}
          <button type="button" className="text-button" onClick={() => setConfirmer(false)}>
            Annuler
          </button>
        </span>
      )}
    </span>
  );
}

export function EquipementMercenaire({ equip, onDesequiper, onDetruire = null, onBasculerF = null, onVoirFiche = null, busy = false }) {
  const e = equip || { arme: [null, null, null], armure: [null], bouclier: [null], objet: [null, null, null] };
  // Équipement de base d'un mercenaire non recruté : lecture seule, pas de bouton Déséquiper.
  const bouton = (emplacement, position, nom) =>
    !onDesequiper ? null : (
    <button
      type="button"
      className="text-button equip-retirer"
      disabled={busy}
      onClick={() => onDesequiper?.(emplacement, position, nom)}
    >
      Déséquiper
    </button>
  );
  const voir = (o) => onVoirFiche?.(o);
  const lien = (o) =>
    onVoirFiche
      ? {
          onClick: () => voir(o),
          onKeyDown: (ev) => {
            if (ev.key === "Enter" || ev.key === " ") {
              ev.preventDefault();
              voir(o);
            }
          },
          role: "button",
          tabIndex: 0,
          title: "Voir la fiche complète",
          style: { cursor: "pointer" },
        }
      : {};
  const icone = (o) => (
    <span className="equip-icone" {...lien(o)}>
      {o.icone && <img src={o.icone} alt="" loading="lazy" decoding="async" />}
      {o.badgeF && (
        <span className="equip-badge-f" title="Badge F actif" aria-label="Badge F actif">
          F
        </span>
      )}
      {o.gemmesIcones?.length > 0 && (
        <span className="equip-gemmes">
          {o.gemmesIcones.map((g, k) => (
            <img key={k} src={g} alt="Gemme sertie" />
          ))}
        </span>
      )}
    </span>
  );
  const vide = (libelle) => (
    <div className="equip-slot equip-slot-vide">
      <span>{libelle}</span>
    </div>
  );
  return (
    <div className="equip-grille">
      <div className="equip-groupe">
        <h3>Armes</h3>
        {[0, 1, 2].map((i) => {
          const o = e.arme?.[i];
          return o ? (
            <div className="equip-slot equip-slot-arme" key={i}>
              {icone(o)}
              <div className="equip-texte">
                <strong className="equip-nom" {...lien(o)}>
                  {o.nom}
                  {/* Icônes liées à l'arme (catalogue) : jusqu'à deux, côte à côte ; non modifiables ici. */}
                  <span className="equip-arme-icones">
                    {[o.armeIcone1 || ICONE_ARME_PAR_DEFAUT, o.armeIcone2].filter(Boolean).map((src, k) => (
                      <img key={k} src={src} alt="" />
                    ))}
                  </span>
                </strong>
                {o.description && <p className="equip-description"><RichText text={o.description} /></p>}
                <dl className="equip-stats">
                  {aUneValeur(o.portee) && (
                    <div>
                      <dt>Portée</dt>
                      <dd>{o.portee}</dd>
                    </div>
                  )}
                  {aUneValeur(o.allonge) && (
                    <div>
                      <dt>Allonge</dt>
                      <dd>{o.allonge}</dd>
                    </div>
                  )}
                  <div>
                    <dt>Dégâts</dt>
                    <dd>{valeur(o.typeDegats)}</dd>
                  </div>
                </dl>
                {o.parade && (
                  <p className="equip-etiquettes">
                    <span className="equip-oui">Parade {o.parade}</span>
                    <BadgesParade emplacement="arme" position={i} nom={o.nom} actif={o.badgeF} onDetruire={onDetruire} onBasculerF={onBasculerF} busy={busy} />
                  </p>
                )}
                {(o.legere || o.deuxMains) && (
                  <p className="equip-etiquettes">
                    {o.legere && <span className="equip-oui">Arme légère</span>}
                    {o.deuxMains && <span className="equip-oui">Deux mains</span>}
                  </p>
                )}
                {bouton("arme", i, o.nom)}
              </div>
            </div>
          ) : (
            <div key={i}>{vide(`Arme ${i + 1}`)}</div>
          );
        })}
      </div>
      {/* Armure, puis le bouclier juste dessous : une seule colonne. */}
      <div className="equip-colonne">
      <div className="equip-groupe">
        <h3>Armure</h3>
        {e.armure?.[0] ? (
          <div className="equip-slot">
            {icone(e.armure[0])}
            <div className="equip-texte">
              <strong {...lien(e.armure[0])}>{e.armure[0].nom}</strong>
              <dl className="equip-stats">
                <div>
                  <dt>Protection</dt>
                  <dd>
                    {valeur(e.armure[0].protection)}
                    {aUneValeur(e.armure[0].protection) && (
                      <BadgesParade
                        emplacement="armure"
                        position={0}
                        nom={e.armure[0].nom}
                        actif={e.armure[0].badgeF}
                        onDetruire={onDetruire}
                        onBasculerF={onBasculerF}
                        busy={busy}
                      />
                    )}
                  </dd>
                </div>
                <div>
                  <dt>Type</dt>
                  <dd>{valeur(e.armure[0].typeArmure)}</dd>
                </div>
                <div>
                  <dt>Discrétion</dt>
                  <dd>{valeur(e.armure[0].malusDiscretion)}</dd>
                </div>
                <div>
                  <dt>Vitesse</dt>
                  <dd>{valeur(e.armure[0].malusVitesse)}</dd>
                </div>
              </dl>
              {bouton("armure", 0, e.armure[0].nom)}
            </div>
          </div>
        ) : (
          vide("Armure")
        )}
      </div>
      <div className="equip-groupe">
        <h3>Bouclier</h3>
        {e.bouclier?.[0] ? (
          <div className="equip-slot">
            {icone(e.bouclier[0])}
            <div className="equip-texte">
              <strong {...lien(e.bouclier[0])}>{e.bouclier[0].nom}</strong>
              <dl className="equip-stats">
                <div>
                  <dt>Parade</dt>
                  <dd>
                    {valeur(e.bouclier[0].parade)}
                    {aUneValeur(e.bouclier[0].parade) && (
                      <BadgesParade
                        emplacement="bouclier"
                        position={0}
                        nom={e.bouclier[0].nom}
                        actif={e.bouclier[0].badgeF}
                        onDetruire={onDetruire}
                        onBasculerF={onBasculerF}
                        busy={busy}
                      />
                    )}
                  </dd>
                </div>
                <div>
                  <dt>Esquive</dt>
                  <dd>{valeur(e.bouclier[0].malusEsquive)}</dd>
                </div>
                <div>
                  <dt>Discrétion</dt>
                  <dd>{valeur(e.bouclier[0].malusDiscretion)}</dd>
                </div>
                <div>
                  <dt>Vitesse</dt>
                  <dd>{valeur(e.bouclier[0].malusVitesse)}</dd>
                </div>
              </dl>
              {bouton("bouclier", 0, e.bouclier[0].nom)}
            </div>
          </div>
        ) : (
          vide("Bouclier")
        )}
      </div>
      </div>
      <div className="equip-groupe">
        <h3>Objets</h3>
        {[0, 1, 2].map((i) => {
          const o = e.objet?.[i];
          return o ? (
            <div className="equip-slot" key={i}>
              {icone(o)}
              <div className="equip-texte">
                <strong {...lien(o)}>{o.nom}</strong>
                {o.description && <p className="equip-description"><RichText text={o.description} /></p>}
                {bouton("objet", i, o.nom)}
              </div>
            </div>
          ) : (
            <div key={i}>{vide(`Objet ${i + 1}`)}</div>
          );
        })}
      </div>
    </div>
  );
}

// Fiche d'un objet consultée depuis le sac à dos (lecture seule) : image, description, puis les
// statistiques propres à sa rubrique (armes, armures, boucliers) seulement si elles sont renseignées.
export function FicheObjet({ objet }) {
  const o = objet;
  const ligne = (libelle, v) =>
    v === null || v === undefined || String(v).trim() === "" ? null : (
      <div className="stat-line" key={libelle}>
        <span>{libelle}</span>
        <strong>{v}</strong>
      </div>
    );
  const arme = o.categorie === "Armes";
  const armure = o.categorie === "Armures" && !o.estBouclier;
  const bouclier = o.categorie === "Armures" && o.estBouclier;
  return (
    <div className="fiche-objet">
      <div className="fiche-objet-image">
        <span className="equip-icone fiche-objet-icone">
          {o.icone && <img src={o.icone} alt="" />}
          {o.gemmesIcones?.length > 0 && (
            <span className="equip-gemmes">
              {o.gemmesIcones.map((g, k) => (
                <img key={k} src={g} alt="Gemme sertie" />
              ))}
            </span>
          )}
        </span>
        {arme && (
          <span className="equip-arme-icones">
            {[o.armeIcone1 || ICONE_ARME_PAR_DEFAUT, o.armeIcone2].filter(Boolean).map((src, k) => (
              <img key={k} src={src} alt="" />
            ))}
          </span>
        )}
      </div>
      <p className="fiche-objet-description"><RichText text={o.description || "Aucune description pour le moment."} /></p>
      <div className="fiche-objet-stats">
        {(arme || armure) && ligne("Vétérance requise", o.veteranceRequise)}
        {o.categorie === "Produits Alchimiques" && aUneValeur(o.portee) && ligne("Portée", o.portee)}
        {arme && (
          <>
            {aUneValeur(o.portee) && ligne("Portée", o.portee)}
            {aUneValeur(o.allonge) && ligne("Allonge", o.allonge)}
            {ligne("Type de dégâts", o.typeDegats)}
            {ligne("Parade", o.parade)}
            {o.legere && ligne("Arme légère", "Oui")}
            {o.deuxMains && ligne("Deux mains", "Oui")}
          </>
        )}
        {armure && (
          <>
            {ligne("Protection", o.protection)}
            {ligne("Type", o.typeArmure)}
            {ligne("Discrétion", o.malusDiscretion)}
            {ligne("Vitesse", o.malusVitesse)}
          </>
        )}
        {bouclier && (
          <>
            {ligne("Parade", o.parade)}
            {ligne("Esquive", o.malusEsquive)}
            {ligne("Discrétion", o.malusDiscretion)}
            {ligne("Vitesse", o.malusVitesse)}
          </>
        )}
      </div>
    </div>
  );
}

// Fenêtre d'une cellule de compétence (fiche joueur).
// Compétence active utilisable (vétérance atteinte) par le joueur qui a recruté le mercenaire : un
// compteur de 1 à 10 permet de dépenser cette énergie, après une validation explicite.
// Paliers de « Restauration Arcanique » : vétérance requise -> énergie rendue.
const PALIERS_RESTAURATION = [
  [1, 2],
  [4, 3],
  [7, 4],
  [10, 5],
];
export function DetailCompetence({ cellule, veterance, energie = null, onDepenser = null, onRestaurer = null }) {
  const { niveau, type, competence } = cellule;
  const atteinte = veterance >= niveau;
  const [choix, setChoix] = useState(null);
  const [enCours, setEnCours] = useState(false);
  const [erreur, setErreur] = useState("");
  const [depense, setDepense] = useState(null);
  const restauration = competence?.nom?.trim().toLowerCase() === "restauration arcanique";
  const compteur = !!competence && type !== "passive" && atteinte && !!onDepenser && !restauration;
  // Restauration Arcanique : un seul palier utilisable, le plus haut atteint, et une fois par ouverture
  // de la fenêtre (le bouton reste grisé jusqu'à sa fermeture).
  const [restaure, setRestaure] = useState(null);
  const palierActif = restauration
    ? PALIERS_RESTAURATION.filter(([n]) => veterance >= n).at(-1)?.[0] ?? null
    : null;
  async function restaurer() {
    setEnCours(true);
    const res = await onRestaurer();
    setEnCours(false);
    if (res?.error) {
      setErreur(res.error);
      return;
    }
    setErreur("");
    setRestaure(res?.montant ?? true);
  }
  async function valider() {
    setEnCours(true);
    const res = await onDepenser(choix);
    setEnCours(false);
    if (res?.error) {
      setErreur(res.error);
      return;
    }
    setErreur("");
    setDepense(choix);
    setChoix(null);
  }
  return (
    <div className="comp-detail">
      {competence ? (
        <>
          {competence.icone && <img className="comp-detail-icone" src={competence.icone} alt="" />}
          <p className="comp-detail-meta">
            Compétence {type === "passive" ? "passive" : "active"} · Vétérance requise {niveau}
          </p>
          <p><RichText text={competence.description || "Aucune description pour le moment."} /></p>
        </>
      ) : (
        <>
          <p className="comp-detail-meta">
            Cellule {type === "passive" ? "passive" : "active"} · Vétérance requise {niveau}
          </p>
          <p>Aucune compétence n’a encore été placée dans cette cellule.</p>
        </>
      )}
      <p className={atteinte ? "comp-detail-ok" : "comp-detail-non"}>
        {atteinte ? "Vétérance atteinte : utilisable." : `Vétérance ${niveau} requise (actuelle : ${veterance}).`}
      </p>
      {restauration && !!onRestaurer && (
        <div className="energie-compteur">
          <p className="energie-compteur-titre">
            Restaurer de l’énergie <span className="muted">(disponible : {energie ?? "—"})</span>
          </p>
          <div className="energie-compteur-chiffres restauration-paliers" role="group" aria-label="Restauration Arcanique">
            {PALIERS_RESTAURATION.map(([niveau, gain]) => (
              <button
                key={niveau}
                type="button"
                className="energie-chiffre restauration-palier"
                disabled={enCours || restaure !== null || niveau !== palierActif}
                onClick={restaurer}
              >
                Vétérance {niveau} : +{gain} énergies
              </button>
            ))}
          </div>
          {restaure !== null && (
            <p className="comp-detail-ok" role="status">
              Énergie restaurée{typeof restaure === "number" ? " : +" + restaure : ""}. Fermez la fenêtre pour pouvoir l’utiliser de nouveau.
            </p>
          )}
          {erreur && (
            <p className="error" role="alert">
              {erreur}
            </p>
          )}
        </div>
      )}
      {compteur && (
        <div className="energie-compteur">
          <p className="energie-compteur-titre">
            Dépenser de l’énergie <span className="muted">(disponible : {energie ?? "—"})</span>
          </p>
          <div className="energie-compteur-chiffres" role="group" aria-label="Énergie à dépenser">
            {Array.from({ length: 10 }, (_, i) => i + 1).map((n) => (
              <button
                key={n}
                type="button"
                className="energie-chiffre"
                aria-pressed={choix === n}
                disabled={enCours || (energie !== null && n > energie)}
                onClick={() => {
                  setChoix(n);
                  setErreur("");
                  setDepense(null);
                }}
              >
                {n}
              </button>
            ))}
          </div>
          {choix !== null && (
            <p className="energie-compteur-valider">
              <button type="button" className="wood-button" disabled={enCours} onClick={valider}>
                Valider : dépenser {choix} énergie{choix > 1 ? "s" : ""}
              </button>{" "}
              <button type="button" className="text-button" disabled={enCours} onClick={() => setChoix(null)}>
                Annuler
              </button>
            </p>
          )}
          {depense !== null && (
            <p className="comp-detail-ok" role="status">
              {depense} énergie{depense > 1 ? "s" : ""} dépensée{depense > 1 ? "s" : ""}.
            </p>
          )}
          {erreur && (
            <p className="error" role="alert">
              {erreur}
            </p>
          )}
        </div>
      )}
    </div>
  );
}
