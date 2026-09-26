// Fiche d'un mercenaire : emplacements d'équipement (3 armes, 1 armure,
// 3 objets) et tableau de compétences (10 lignes de vétérance, 3 cellules
// passives puis 5 actives). Partagé entre la fiche joueur (Characters.jsx) et
// l'éditeur de l'administration (Admin.jsx).

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
export function TableauCompetences({ cellules = [], veterance = null, onCell, selection = null }) {
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
        <div className="comp-ligne" key={niveau}>
          {[0, 1, 2].map((p) => cellule(niveau, "passive", p))}
          <span className="comp-espace" aria-hidden="true" />
          {[0, 1, 2, 3, 4].map((p) => cellule(niveau, "active", p))}
        </div>
      ))}
    </div>
  );
}

const valeur = (v) => (v === null || v === undefined || v === "" ? "—" : v);

// Emplacements d'équipement : `equip` = { arme: [3], armure: [1], objet: [3] }
// (chaque entrée : fiche de l'objet ou null). Déséquiper renvoie l'objet au sac.
export function EquipementMercenaire({ equip, onDesequiper, busy = false }) {
  const e = equip || { arme: [null, null, null], armure: [null], bouclier: [null], objet: [null, null, null] };
  const bouton = (emplacement, position, nom) => (
    <button
      type="button"
      className="text-button equip-retirer"
      disabled={busy}
      onClick={() => onDesequiper?.(emplacement, position, nom)}
    >
      Déséquiper
    </button>
  );
  const icone = (o) => (
    <span className="equip-icone">
      {o.icone && <img src={o.icone} alt="" loading="lazy" decoding="async" />}
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
            <div className="equip-slot" key={i}>
              {icone(o)}
              <div className="equip-texte">
                <strong>{o.nom}</strong>
                {o.description && <p className="equip-description">{o.description}</p>}
                <dl className="equip-stats">
                  <div>
                    <dt>Portée</dt>
                    <dd>{valeur(o.portee)}</dd>
                  </div>
                  <div>
                    <dt>Allonge</dt>
                    <dd>{valeur(o.allonge)}</dd>
                  </div>
                  <div>
                    <dt>Dégâts</dt>
                    <dd>{valeur(o.typeDegats)}</dd>
                  </div>
                </dl>
                <p className="equip-etiquettes">
                  <span className={o.legere ? "equip-oui" : "equip-non"}>{o.legere ? "Arme légère" : "Pas légère"}</span>
                  <span className={o.deuxMains ? "equip-oui" : "equip-non"}>{o.deuxMains ? "Deux mains" : "Une main"}</span>
                </p>
                {bouton("arme", i, o.nom)}
              </div>
            </div>
          ) : (
            <div key={i}>{vide(`Arme ${i + 1}`)}</div>
          );
        })}
      </div>
      <div className="equip-groupe">
        <h3>Armure</h3>
        {e.armure?.[0] ? (
          <div className="equip-slot">
            {icone(e.armure[0])}
            <div className="equip-texte">
              <strong>{e.armure[0].nom}</strong>
              <dl className="equip-stats">
                <div>
                  <dt>Protection</dt>
                  <dd>{valeur(e.armure[0].protection)}</dd>
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
              <strong>{e.bouclier[0].nom}</strong>
              <dl className="equip-stats">
                <div>
                  <dt>Parade</dt>
                  <dd>{valeur(e.bouclier[0].parade)}</dd>
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
      <div className="equip-groupe">
        <h3>Objets</h3>
        {[0, 1, 2].map((i) => {
          const o = e.objet?.[i];
          return o ? (
            <div className="equip-slot" key={i}>
              {icone(o)}
              <div className="equip-texte">
                <strong>{o.nom}</strong>
                {o.description && <p className="equip-description">{o.description}</p>}
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

// Fenêtre d'une cellule de compétence (fiche joueur).
export function DetailCompetence({ cellule, veterance }) {
  const { niveau, type, competence } = cellule;
  const atteinte = veterance >= niveau;
  return (
    <div className="comp-detail">
      {competence ? (
        <>
          {competence.icone && <img className="comp-detail-icone" src={competence.icone} alt="" />}
          <p className="comp-detail-meta">
            Compétence {type === "passive" ? "passive" : "active"} · Vétérance requise {niveau}
          </p>
          <p>{competence.description || "Aucune description pour le moment."}</p>
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
    </div>
  );
}
