import { useState } from 'react';
import { INGREDIENTS, findAlchemyRecipe } from './alchemy.js';
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
    <div className="alchemy-table">
      <section className="alchemy-circle-panel" aria-label="Pentagramme de fabrication">
        <div className="alchemy-circle-heading"><h2>Le pentagramme</h2><button className="text-button" disabled={!occupied} onClick={() => perform({ type: 'clear' })}>Tout retirer</button></div>
        <p className="alchemy-selection" role="status">{selectedName ? `${selectedName} sélectionné · choisissez une branche` : `${occupied} / 5 branches occupées`}</p>
        <div className={`alchemy-sigil ${recipe ? 'recipe-ready' : ''}`} style={{ '--potion-color': recipe?.color || '#b3cd91' }}>
          <span className="sigil-art" aria-hidden="true"><img src="/assets/references/pentagram-star.png" alt="" draggable="false" /></span>
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
        {error && <p role="alert" className="error alchemy-error">{error}</p>}
        <p className="sr-only" role="status" aria-live="polite">{notice}</p>
      </section>
    </div>
  </section>;
}
