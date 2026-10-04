import { useState } from "react";
import { Modal } from "./Modal.jsx";

// « ? » en haut à droite du pavé d'un lieu : ouvre une fenêtre qui explique son fonctionnement. Les textes
// reprennent les règles réellement appliquées par le jeu ; les prix de déblocage n'y figurent pas.
// Le pavé qui l'accueille doit être positionné (position: relative) : le bouton se place en absolu.
export function BoutonAide({ aide }) {
  const [ouvert, setOuvert] = useState(false);
  if (!aide) return null;
  return (
    <>
      <button
        type="button"
        className="pave-aide"
        aria-label={`Explication : ${aide.titre}`}
        title="Comment ça fonctionne ?"
        onClick={() => setOuvert(true)}
      >
        ?
      </button>
      {ouvert && (
        <Modal verre title={aide.titre} onClose={() => setOuvert(false)}>
          <div className="aide-defense">
            {aide.rubriques.map(([titre, texte]) => (
              <section className="aide-defense-rubrique" key={titre}>
                <h3>{titre}</h3>
                <p>{texte}</p>
              </section>
            ))}
          </div>
        </Modal>
      )}
    </>
  );
}

// Fabrication commune aux quatre ateliers : forge, armurerie, laboratoire, tour du mage.
const fabrication = (verbe, lieu) => [
  [
    "Lancer une fabrication",
    `Ouvrez un catalogue, choisissez un objet puis cliquez sur « ${verbe} ». Les ressources de sa recette sont prélevées dans l’arsenal dès le lancement : si elles manquent, la fabrication est refusée. ${lieu} ne fabrique qu’un objet à la fois.`,
  ],
  [
    "La durée",
    "Chaque « +1 Instance » du maître du jeu fait baisser la durée d’instance restante. À 0, la fabrication est terminée, mais l’objet n’est pas livré tout seul : cliquez sur « Envoyer à l’Arsenal » pour le récupérer et libérer l’atelier.",
  ],
];

export const AIDES = {
  forge: {
    titre: "La Forge : mode d’emploi",
    rubriques: [
      [
        "À quoi ça sert",
        "La forge fabrique les armes. Le catalogue des armes et le catalogue des objets (qu’on peut fabriquer ici ou à l’armurerie) donnent pour chaque objet sa fiche, son coût et sa recette.",
      ],
      ...fabrication("Envoyer à la forge", "La forge"),
      [
        "Le sertissage",
        "Le panneau situé sous la fabrication permet de sertir des gemmes sur une arme. Son « ? » l’explique.",
      ],
    ],
  },
  armurerie: {
    titre: "L’Armurerie : mode d’emploi",
    rubriques: [
      [
        "À quoi ça sert",
        "L’armurerie fabrique les armures. Le catalogue des armures et le catalogue des objets (qu’on peut fabriquer ici ou à la forge) donnent pour chaque objet sa fiche, son coût et sa recette.",
      ],
      ...fabrication("Envoyer à l’armurerie", "L’armurerie"),
      [
        "Le sertissage",
        "Le panneau situé sous la fabrication permet de sertir des gemmes sur une armure. Son « ? » l’explique.",
      ],
    ],
  },
  alchimie: {
    titre: "Le Laboratoire : mode d’emploi",
    rubriques: [
      [
        "À quoi ça sert",
        "Le laboratoire fabrique les produits alchimiques. Le catalogue donne pour chacun sa fiche et sa recette, faite de composants pris dans l’arsenal. Ces composants proviennent du Marché ou de certaines Quêtes.",
      ],
      ...fabrication("Fabriquer", "Le laboratoire"),
    ],
  },
  mage: {
    titre: "La Tour du Mage : mode d’emploi",
    rubriques: [
      [
        "À quoi ça sert",
        "La tour du mage fabrique les gemmes. Elles servent ensuite au sertissage : sur les armes à la forge, sur les armures à l’armurerie.",
      ],
      ...fabrication("Fabriquer", "La tour du mage"),
    ],
  },
  entrainement: {
    titre: "L’Entraînement : mode d’emploi",
    rubriques: [
      [
        "À quoi ça sert",
        "Un instructeur forme des élèves de sa classe : chaque instance fait gagner un niveau de vétérance à l’élève.",
      ],
      [
        "L’instructeur",
        "Il se choisit depuis la fiche d’un mercenaire de la Caserne, avec le bouton « Instructeur ». Il reste en place jusqu’à ce que son recruteur le renvoie, et le renvoyer ramène aussi ses élèves à la Caserne, avec leur niveau actuel.",
      ],
      [
        "Les élèves",
        "Il faut d’abord un instructeur. Un élève est de la même classe que lui, a au moins 3 points de vétérance de moins et est disponible à la Caserne. Cliquez sur « Choisir un élève » pour en placer un.",
      ],
      [
        "La progression",
        "À chaque « +1 Instance » du maître du jeu, l’élève gagne 1 niveau de vétérance. Dès qu’il atteint celle de son instructeur, il retourne à la Caserne. S’il est renvoyé avant, il garde le niveau déjà acquis.",
      ],
      [
        "Bon à savoir",
        "Un mercenaire à l’entraînement ne peut être ni à l’infirmerie ni en quête. Les cases verrouillées se débloquent par le maître du jeu seul.",
      ],
    ],
  },
  dortoirs: {
    titre: "La Caserne : mode d’emploi",
    rubriques: [
      [
        "À quoi ça sert",
        "La Caserne loge les mercenaires recrutés par les joueurs de la compagnie. Chaque mercenaire recruté y a sa place, avec le nom de son joueur.",
      ],
      [
        "Recruter",
        "Ouvrez la fiche d’un mercenaire, inscrivez votre nom de joueur et cliquez sur « Recruter ». Le recrutement coûte 100 Po × sa vétérance, prélevés sur la trésorerie ; le premier recrutement de chaque joueur est gratuit. Le mercenaire prend la première place libre.",
      ],
      [
        "Renvoyer",
        "Renvoyer un mercenaire libère sa place et efface le nom du joueur. Il garde sa vétérance, son équipement et ses PV (seule son énergie revient au maximum). Le recruter de nouveau se paie.",
      ],
      [
        "Les absents",
        "Un mercenaire parti à l’entraînement, à l’infirmerie ou en quête est grisé, mais il garde sa place.",
      ],
      [
        "L’entretien",
        "À chaque « +1 Instance », la compagnie paie 10 Po × la vétérance de chaque mercenaire de la Caserne. Les places supplémentaires se débloquent par le maître de jeu seul et en réussissant certaines quêtes.",
      ],
    ],
  },
  quetes: {
    titre: "Les Quêtes : mode d’emploi",
    rubriques: [
      [
        "Choisir une quête",
        "Une seule quête peut être en cours à la fois : « Choisir cette quête » la lance, « Annuler le choix » la libère.",
      ],
      [
        "Engager des mercenaires",
        "Cliquez sur un emplacement libre sous « Mercenaires engagés » : la quête est choisie et la Caserne s’ouvre. Ouvrez la fiche d’un de vos mercenaires et cliquez sur « Quête ». Jusqu’à 6 mercenaires peuvent partir ; ils sont grisés à la Caserne pendant la quête. La jauge de difficulté compare leur vétérance à la puissance de la quête.",
      ],
      [
        "Faire avancer",
        "Chaque « +1 Instance » du maître du jeu fait baisser le nombre d’instances restantes. À 0, la quête est accomplie.",
      ],
      [
        "Les récompenses",
        "À la fin, l’or et les objets s’affichent dans une fenêtre et rejoignent la compagnie quand on la ferme. Un « ? » cache une récompense mystère jusqu’à ce moment.",
      ],
      [
        "Les mercenaires",
        "Chaque mercenaire engagé gagne 1 niveau de vétérance, sauf si sa vétérance dépasse la puissance de la quête. Son énergie revient au maximum et il retrouve sa place à la Caserne.",
      ],
    ],
  },
};
