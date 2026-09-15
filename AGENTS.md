# Prototype Instructions

Run the local server yourself and open the preview in the browser available to this environment. Do not give the user server-start instructions when you can run it.

Before making substantial visual changes, use the Product Design plugin's `get-context` skill when the visual source is unclear or no longer matches the current goal. When the user gives durable prototype-specific design feedback, preferences, or decisions, record them in `AGENTS.md`.

When implementing from a selected generated mock, treat that image as the source of truth for layout, component anatomy, density, spacing, color, typography, visible content, and hierarchy.

Build app UI in `src/`. Keep `.openai/hosting.json`, `worker/index.js`, `scripts/prepare-sites-build.mjs`, and `tests/sites-worker.test.mjs` intact so the same local prototype can be handed to Sites. Before a Sites handoff, run `npm run build` and `npm run test:sites`; the build must leave `dist/client/index.html`, `dist/server/index.js`, and `dist/.openai/hosting.json`.

## Préférences de Tim — 9 septembre 2026
L’accueil et son château occupent toute la largeur de la fenêtre, sans container limité à 1120 px. Les blocs gardent leur taille plafonnée. Les autres pages conservent leur cadre compact. Supprimer le footer décoratif ; conserver le bouton global +10 minutes dans le header. Utiliser Aniron fourni par Tim.
Tim souhaite des transitions et animations soignées, en gardant UX et UI prioritaires : mouvements courts, actions immédiates, respect de la réduction des animations.

Accueil : Arsenal (ancien Stock) en haut à gauche, Dortoirs à l’ancienne place du Stock en bas à gauche. Quêtes ancré sous le groupe solde/+10 minutes à droite, indépendamment des coordonnées du château.

Réduire le défilement des pages métier : emplacements compacts mais lisibles, hauteur dictée par les actions ; recadrer les décors vers le bas en coupant le haut, notamment à l’infirmerie. Ne pas masquer les actions dans un conteneur à défilement interne.

Laboratoire : inventaire directement visible, ingrédients déplaçables vers les cinq branches du pentagramme. Recettes initiales explicitement illustratives ; ne pas les présenter comme les règles définitives de Bruno.
