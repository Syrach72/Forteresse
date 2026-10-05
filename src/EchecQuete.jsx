import { Modal } from "./Modal.jsx";

// Fenêtre d'échec de quête : annoncée à tous les joueurs quand le MJ déclare la quête échouée.
export function EchecQuete({ echec, onClose }) {
  return (
    <Modal title={`Quête échouée : ${echec.nom}`} onClose={onClose} className="recompense-quete">
      <p>
        La compagnie a échoué. Aucune récompense n’est accordée, mais vous pourrez revenir plus tard : la
        quête redevient disponible.
      </p>
      <button type="button" className="wood-button" onClick={onClose}>
        Compris
      </button>
    </Modal>
  );
}
