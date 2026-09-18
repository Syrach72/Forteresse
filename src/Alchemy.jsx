import { useState } from 'react';
export function Alchemy({ alchemy, onChange }) {
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const occupied = alchemy.slots.filter(Boolean).length;
  function perform(action) {
    const result = onChange(action);
    setError(result?.error || '');
    if (result?.error) return false;
    setNotice(action.type === 'clear' ? 'Les cinq branches sont libérées.' : 'Pentagramme mis à jour.');
    return true;
  }
  return <section className="alchemy-workspace" aria-label="Atelier d’alchimie">
    <div className="alchemy-table">
      <section className="alchemy-circle-panel" aria-label="Pentagramme de fabrication">
        <div className="alchemy-circle-heading"><h2>Le pentagramme</h2><button className="text-button" disabled={!occupied} onClick={() => perform({ type: 'clear' })}>Tout retirer</button></div>
        <p className="alchemy-selection" role="status">{occupied} / 5 branches occupées</p>
        <div className="alchemy-sigil">
          <span className="sigil-art" aria-hidden="true"><img src="/assets/references/pentagram-star.png" alt="" draggable="false" /></span>
        </div>
        {error && <p role="alert" className="error alchemy-error">{error}</p>}
        <p className="sr-only" role="status" aria-live="polite">{notice}</p>
      </section>
    </div>
  </section>;
}
