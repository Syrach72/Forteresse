import test from 'node:test';
import assert from 'node:assert/strict';
import { initialGame, transact } from '../src/game.js';
import { changeAlchemy, availableIngredient, ALCHEMY_RECIPES } from '../src/alchemy.js';
const apply = (game, action) => { const result = changeAlchemy(game, action); assert.equal(result.error, undefined); return result.state; };
test('une branche réserve un exemplaire ; remplacement, échange et retrait ne consomment rien', () => {
  const original = initialGame();
  let game = apply(original, { type:'place', slot:0, id:'mushroom' });
  assert.equal(availableIngredient(game.alchemy, 'mushroom'), 5);
  assert.equal(game.alchemy.stock.mushroom, 6);
  assert.equal(original.alchemy.slots[0], null);
  game = apply(game, { type:'place', slot:1, id:'salt' });
  game = apply(game, { type:'move', from:0, to:1 });
  assert.deepEqual(game.alchemy.slots.slice(0,2), ['salt','mushroom']);
  game = apply(game, { type:'place', slot:0, id:'slime' });
  assert.equal(availableIngredient(game.alchemy, 'salt'), 6);
  game = apply(game, { type:'remove', slot:1 });
  assert.equal(availableIngredient(game.alchemy, 'mushroom'), 6);
  game = apply(game, { type:'clear' });
  assert.deepEqual(game.alchemy, original.alchemy);
});
test('un stock limité refuse la surréservation et les coordonnées ou ingrédients inconnus', () => {
  let game = initialGame(); game.alchemy.stock.mushroom = 1;
  game = apply(game, { type:'place', slot:0, id:'mushroom' });
  const before = JSON.stringify(game);
  for (const action of [{type:'place',slot:1,id:'mushroom'}, {type:'place',slot:5,id:'salt'}, {type:'place',slot:0,id:'fake'}, {type:'move',from:4,to:0}, {type:'remove',slot:-1}]) assert.ok(changeAlchemy(game, action).error);
  assert.equal(JSON.stringify(game), before);
});
test('les trois recettes fonctionnent dans un ordre libre et produisent une potion utilisable', () => {
  for (const recipe of ALCHEMY_RECIPES) {
    let game = initialGame();
    for (const [slot,id] of [...recipe.ingredients].reverse().entries()) game = apply(game, { type:'place', slot, id });
    const quantity = game.inventory.find(i=>i.id===recipe.output)?.quantity || 0;
    const ready = JSON.stringify(game);
    const result = changeAlchemy(game,{type:'brew'});
    assert.equal(result.recipe.id, recipe.id);
    assert.equal(JSON.stringify(game),ready);
    game=result.state;
    assert.equal(game.inventory.find(i=>i.id===recipe.output).quantity,quantity+1);
    for(const id of recipe.ingredients) assert.equal(game.alchemy.stock[id],5);
    assert.deepEqual(game.alchemy.slots,Array(5).fill(null));
    assert.equal(game.gold,905);
    assert.equal(game.log[0].amount,0);
    assert.ok(changeAlchemy(game,{type:'brew'}).error);
    const used=transact(game,{type:'use',id:recipe.output});
    assert.equal(used.error,undefined);
    assert.equal(used.state.inventory.find(i=>i.id===recipe.output)?.quantity || 0,quantity);
    assert.equal(used.state.health,game.health);
  }
});
test('une combinaison inconnue ou un stock devenu insuffisant ne perd aucun composant', () => {
  let game=apply(initialGame(),{type:'place',slot:0,id:'mushroom'});
  let before=JSON.stringify(game);
  assert.ok(changeAlchemy(game,{type:'brew'}).error);
  assert.equal(JSON.stringify(game),before);
  game=apply(game,{type:'place',slot:1,id:'slime'});
  game=apply(game,{type:'place',slot:2,id:'salt'});
  game.alchemy.stock.salt=0;
  before=JSON.stringify(game);
  assert.ok(changeAlchemy(game,{type:'brew'}).error);
  assert.equal(JSON.stringify(game),before);
});
