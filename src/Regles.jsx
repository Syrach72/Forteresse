// Page « Règles » : fond blanc. Texte rédigé par le MJ (Bruno), orthographe relue.
const REGLES = [
  [
    "Attaques Physiques",
    "La règle principale repose sur les jets de D6 (🎲). L’attaquant lance autant de 🎲 que la valeur de caractéristique requise pour cette attaque. Ce jet est modifié par les informations, bonus et malus de l’arme utilisée. Selon les moyens de défense de l’adversaire, celui-ci lance également un certain nombre de 🎲. Le principe général : l’attaquant inflige un point d’Impact pour chaque résultat « 5-6 » à son jet, mais le défenseur ignore un Impact par « 6 » obtenu à son jet. Cela peut avoir pour conséquence que l’attaque échoue ou que ses dégâts soient minorés. Une attaque Avantagée crée des Impacts sur « 4-6 », Désavantagée, seulement sur « 6 ». Les Avantages et Désavantages ne s’appliquent qu’à l’attaquant ; ainsi, un défenseur Avantagé crée un Désavantage à l’attaquant. Les Avantages et Désavantages se cumulent, y compris avec d’autres effets, mais en tout état de cause, aucune attaque ne peut obtenir mieux que « 4-6 » ni moins bien que « 6 ». Les attaques Physiques sont généralement effectuées avec la Puissance, certaines avec la Vélocité.",
  ],
  [
    "Attaquer, Parer, Esquiver",
    "Attaquer, Parer, Esquiver ne dépense pas d’Énergie. Sous certaines conditions, un perso peut tenter d’Esquiver ou de Parer une attaque, mais pas les deux à la fois. Un perso Surpris, Inconscient, Étourdi, Paralysé… ne peut pas utiliser ces capacités. Une RD (Résistance aux Dégâts) ou une RM (Résistance à la Magie) permet de ne comptabiliser comme Impact potentiel que les « 6 » des dégâts Énergétiques des armes Gemmées et des sorts.",
  ],
  [
    "La Carac. mentale et les attaques spéciales",
    "Un Incantateur – mais pas seulement – se sert généralement de la valeur brute de sa Carac. mentale pour utiliser ses compétences, mais d’autres compétences nécessitent la Puissance ou la Vélocité. La compétence activée dépense de l’Énergie et indique quelle Carac. le défenseur doit utiliser pour se défendre. L’attaque échoue généralement (ou est minorée) si le défenseur obtient plus de « 6 » que le nombre de 🎲 d’Impact de l’attaquant. L’Énergie se recharge automatiquement de 1 Pt par Rd. La Carac. mentale détermine aussi le nombre de Gemmes qu’un Mercenaire peut porter (Armes et Armures confondues), à savoir autant que sa valeur de Mental.",
  ],
  [
    "Armes Gemmées et Dégâts Énergétiques",
    "Les armes portant une gemme magique ajoutent 1 à 3 🎲 à leur jet (selon le niveau de puissance de la gemme). Ce dé doit être d’une couleur différente des dés génériques. Il touche généralement sur « 5-6 » et ignore les armures et parades, mais pas les Esquives. S’il touche, il inflige un dégât de l’énergie correspondante à la gemme. Les créatures immunisées à cette énergie ne sont pas affectées par l’impact. Les créatures Résistantes (naturellement ou grâce à un bijou ou objet magique) ne sont touchées que sur « 6 ». Deux RD de sources différentes mais contre une même énergie ne se cumulent pas. De plus, les PJ ne peuvent pas posséder plus de deux RD différentes.",
  ],
  [
    "Armes",
    "Certaines armes ne peuvent être utilisées que par certaines classes : Armes de Guerre (classes Guerrier, Paladin et assimilés, Prêtres de Guerre) / Armes de Moine (Moines, Ninjas, Samouraïs, etc.). Les Druides n’utilisent que des armes en bois et quelques autres spécifiques autorisées, y compris de Guerre. Les Incantateurs n’utilisent que les armes courantes légères ou à distance. Les Moines combattent à Mains Nues (létales) ou avec des Armes de Moine.",
  ],
  [
    "Note : les Intangibles",
    "Les Intangibles ne peuvent être touchés que par la Magie et les armes Gemmées (PTK inclus dans ce cas, car le fait de porter une gemme rend automatiquement l’arme magique), et, dans les deux cas, seulement sur « 6 ». PTK : dégâts Perforants, Tranchants ou Contondants.",
  ],
  [
    "Santé",
    "Les PV d’un perso joueur sont égaux à 3 + 2 fois sa valeur de PUISSANCE. [Le maximum d’une Carac. étant 9, le maximum de PV d’un PJ de niveau 10 est 9 × 2 + 3 = 21 PV ; la moyenne, pour des Carac. à peu près équilibrées (7-8 à chaque Carac.), serait de 3 + (7-8 × 2) = 17-19 PV.] Les PV sont les principaux éléments modifiés directement par chaque joueur pendant une Instance.",
  ],
  [
    "Énergie",
    "L’Énergie d’un joueur est égale à 2 fois sa valeur de MENTAL. Elle se recharge de 1 Pt par Rd. Les classes essentiellement incantatrices ont une capacité activable permettant de recharger davantage. [Le maximum est de 9 × 2 = 18.]",
  ],
  [
    "Vétérance",
    "Au moment de son recrutement, un Mercenaire possède 5 Pts répartis entre ses trois Carac. Aucune Carac. ne peut être à zéro. Par la suite, certaines compétences passives augmentent automatiquement des Carac., et, à chaque augmentation de vétérance, le joueur peut dépenser 1 Pt pour augmenter la Carac. de son choix (donc 9 fois sur une carrière complète). Chaque Carac. est cependant plafonnée à 9 Pts.",
  ],
  [
    "Règles spéciales",
    "Les Tenailles ou Soutiens (cible déjà au corps à corps avec un allié qui n’est ni Incapable d’agir ni pris à partie par un autre adversaire) procurent un Avantage à l’attaquant.",
  ],
  [
    "Critiques (💥)",
    "Certaines armes ou effets permettent de remplacer ou d’ajouter un 🎲💥. Un 💥 ne peut en général pas être annulé. Son effet ajoute +1 Pt d’Impact. À partir de 5 🎲 ordinaires lancés en attaque (ou sort), toujours remplacer l’un d’eux par un 🎲💥 (qui s’ajoute éventuellement à un autre 🎲💥 dû à une autre cause ; en tout état de cause, le nombre de 🎲💥 est plafonné à 2 pour un même lancer). Si au moins un de ces 🎲💥 obtient « 6 » et que n’importe quel autre dé obtient aussi « 6 », le coup est un critique (si 2 🎲💥 obtiennent 6, ils se « vérifient » l’un l’autre et sont tous les deux des Critiques), y compris si ce « 6 » de validation a été annulé par la défense.",
  ],
  [
    "Maladresses",
    "À partir de 5 dés d’attaque ou de sort lancés, si aucun dé n’obtient « 5-6 » et qu’il y a un « 1 » parmi ces dés, l’attaque est une Maladresse : le PJ s’inflige autant de dégâts que de « 1 » obtenus.",
  ],
];

export function Regles() {
  return (
    <section className="regles-page">
      <p className="regles-intro">
        Vous pouvez retrouver la plupart des éléments de règle en cliquant sur les{" "}
        <span className="pave-aide pave-aide-inline" aria-label="point d’interrogation">
          ?
        </span>{" "}
        des différentes pages.
      </p>
      {REGLES.map(([titre, texte]) => (
        <div className="regles-bloc" key={titre}>
          <h3>{titre}</h3>
          <p>{texte}</p>
        </div>
      ))}
    </section>
  );
}
