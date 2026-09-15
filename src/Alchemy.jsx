import { useState } from 'react';
import { INGREDIENTS, ALCHEMY_RECIPES, availableIngredient, findAlchemyRecipe } from './alchemy.js';
const MIME = 'application/x-forteresse-ingredient';
const POINTS = [[50, 27], [79, 49], [68, 83], [32, 83], [21, 49]];
export function IngredientArt({ ingredient }) {
  if (ingredient.image) return <span className="ingredient-art"><img src={ingredient.image} alt="" /></span>;
  const [x,y,w,h] = ingredient.crop;
  return <span className="ingredient-art ingredient-crop" style={{ aspectRatio: `${w}/${h}` }}><img src="/assets/references/alchemy-workbench.png" alt="" draggable="false" style={{ width: `${1256/w*100}%`, left: `${-x/w*100}%`, top: `${-y/h*100}%` }} /></span>;
}
export function Alchemy({ alchemy, inventory, onChange }) {
  const [selected, setSelected] = useState(null);
  const [hover, setHover] = useState(null);
  const [error, setError] = useState('');
  const [lastBrew, setLastBrew] = useState(null);
  const [notice, setNotice] = useState('');
  const recipe = findAlchemyRecipe(alchemy.slots);
  const occupied = alchemy.slots.filter(Boolean).length;
  function perform(action) {
    const result = onChange(action);
    setError(result?.error || '');
    if (result?.error) return false;
    setSelected(null);
    setLastBrew(null);
    if (result?.recipe) {
      setLastBrew({ ...result.recipe, key: crypto.randomUUID() });
      setNotice(`${result.recipe.name} ajoutée à l’arsenal. Les ingrédients ont été consommés.`);
    } else setNotice(action.type === 'clear' ? 'Les cinq branches sont libérées.' : action.type === 'remove' ? 'Ingrédient rendu à l’inventaire.' : 'Pentagramme mis à jour.');
    return true;
  }
  function deposit(slot, payload = selected) {
    if (!payload) { setNotice('Choisissez d’abord un ingrédient dans l’inventaire.'); return; }
    if (payload.kind === 'slot') perform({ type: 'move', from: payload.slot, to: slot });
    else if (payload.kind === 'inventory') perform({ type: 'place', slot, id: payload.id });
  }
  function startDrag(e, payload) {
    e.dataTransfer.setData(MIME, JSON.stringify(payload));
    e.dataTransfer.effectAllowed = payload.kind === 'slot' ? 'move' : 'copy';
    setSelected(payload);
  }
  function readDrop(e) {
    e.preventDefault(); setHover(null);
    try { return JSON.parse(e.dataTransfer.getData(MIME)); } catch { return null; }
  }
  const selectedName = selected && INGREDIENTS.find(i => i.id === selected.id)?.name;
  return <section className="alchemy-workspace" aria-label="Atelier d’alchimie" onKeyDown={e => { if (e.key === "Escape") { setSelected(null); setNotice("Sélection annulée."); } }}>
    <div className="alchemy-intro">
      <p>Glissez les ingrédients sur les branches, ou sélectionnez-les puis touchez un emplacement.</p>
      <span>Recettes de démonstration · ordre libre · 1 ingrédient par branche</span>
    </div>
    <div className="alchemy-table">
      <section className="alchemy-circle-panel" aria-label="Pentagramme de fabrication">
        <div className="alchemy-circle-heading"><h2>Le pentagramme</h2><button className="text-button" disabled={!occupied} onClick={() => perform({ type: 'clear' })}>Tout retirer</button></div>
        <p className="alchemy-selection" role="status">{selectedName ? `${selectedName} sélectionné · choisissez une branche` : `${occupied} / 5 branches occupées`}</p>
        <div className={`alchemy-sigil ${recipe ? 'recipe-ready' : ''}`} style={{ '--potion-color': recipe?.color || '#b3cd91' }}>
          <span className="sigil-art" aria-hidden="true"><img src="/assets/references/alchemy-workbench.png" alt="" draggable="false" /></span>
          {POINTS.map(([x,y], slot) => {
            const id = alchemy.slots[slot];
            const ingredient = INGREDIENTS.find(i => i.id === id);
            return <div className="sigil-branch" key={slot} style={{ left: `${x}%`, top: `${y}%` }}>
              <button className={`sigil-target ${id ? 'filled' : ''} ${hover === slot ? 'drop-active' : ''} ${selected?.kind === 'slot' && selected.slot === slot ? 'selected' : ''}`}
                aria-label={`Branche ${slot + 1} : ${ingredient?.name || 'vide'}`} aria-pressed={selected?.kind === 'slot' && selected.slot === slot}
                draggable={!!id} onDragStart={e => id && startDrag(e, { kind: 'slot', slot, id })} onDragEnd={() => setHover(null)}
                onDragOver={e => { if (e.dataTransfer.types.includes(MIME)) { e.preventDefault(); setHover(slot); } }} onDragLeave={() => setHover(null)}
                onDrop={e => deposit(slot, readDrop(e))}
                onClick={() => { if (selected) deposit(slot); else if (id) setSelected({ kind: 'slot', slot, id }); else deposit(slot); }}>
                {ingredient ? <IngredientArt ingredient={ingredient} /> : <span aria-hidden="true">{slot + 1}</span>}
              </button>
              {ingredient && <button className="sigil-remove" aria-label={`Retirer ${ingredient.name} de la branche ${slot + 1}`} onClick={() => perform({ type: 'remove', slot })}>×</button>}
            </div>;
          })}
          <div className="sigil-center" aria-hidden="true">{recipe ? '✦' : '◇'}</div>
        </div>
        <div className={`alchemy-result ${lastBrew ? 'brew-success' : ''}`} key={lastBrew?.key || 'preview'}>
          <div><span className="alchemy-result-label">{lastBrew ? 'Ajoutée à l’arsenal' : 'Résultat de la préparation'}</span><h3>{lastBrew?.name || recipe?.name || (occupied ? 'Combinaison inconnue' : 'Choisissez vos ingrédients')}</h3>
          <p>{lastBrew ? 'Votre potion est prête.' : recipe ? `${recipe.ingredients.length} ingrédients seront consommés.` : occupied ? 'Consultez les recettes ci-contre. Rien n’est consommé.' : 'Une recette apparaît dès que la combinaison est complète.'}</p></div>
          <button className="primary alchemy-brew" disabled={!recipe} onClick={() => perform({ type: 'brew' })}>Fabriquer la potion</button>
        </div>
        {error && <p role="alert" className="error alchemy-error">{error}</p>}
        <p className="sr-only" role="status" aria-live="polite">{notice}</p>
      </section>
      <aside className="alchemy-inventory parchment" aria-label="Inventaire des ingrédients"
        onDragOver={e => { if (selected?.kind === 'slot' && e.dataTransfer.types.includes(MIME)) e.preventDefault(); }}
        onDrop={e => { const payload = readDrop(e); if (payload?.kind === 'slot') perform({ type: 'remove', slot: payload.slot }); }}>
        <header><h2>Ingrédients</h2><span>Quantités disponibles</span></header>
        <div className="ingredient-grid">{INGREDIENTS.map(ingredient => {
          const count = availableIngredient(alchemy, ingredient.id);
          return <button key={ingredient.id} className={`ingredient-tile ${selected?.kind === 'inventory' && selected.id === ingredient.id ? 'selected' : ''}`}
            aria-label={`${ingredient.name}, ${count} disponibles`} aria-pressed={selected?.kind === 'inventory' && selected.id === ingredient.id} disabled={count < 1}
            draggable={count > 0} onDragStart={e => startDrag(e, { kind: 'inventory', id: ingredient.id })} onDragEnd={() => setHover(null)}
            onClick={() => { setSelected(selected?.kind === 'inventory' && selected.id === ingredient.id ? null : { kind: 'inventory', id: ingredient.id }); setError(''); }}>
            <IngredientArt ingredient={ingredient} /><b>{count}</b><span className="ingredient-name">{ingredient.name}</span>
          </button>;
        })}</div>
        <details className="alchemy-recipes" open><summary>Grimoire · 3 recettes</summary><div>{ALCHEMY_RECIPES.map(r => <button type="button" key={r.id} className="alchemy-recipe-card" onClick={() => perform({ type: 'fill', recipeId: r.id })}><h3>{r.name} <small>×{inventory.find(i => i.id === r.output)?.quantity || 0} à l’arsenal</small></h3><p>{r.ingredients.map(id => INGREDIENTS.find(i => i.id === id).name).join(' + ')}</p></button>)}</div></details>
      </aside>
    </div>
  </section>;
}
