import { useEffect, useRef } from "react";

// `verre` : fenêtre en verre dépoli (celle des pages de jeu), pour les fenêtres d'aide ouvertes par un « ? ».
// Le style vient de `.interior .parchment` : la fenêtre est donc placée dans une enveloppe `.interior` sans
// boîte propre (display: contents), ce qui lui donne le même aspect partout, même hors d'une page de jeu.
export function Modal({ title, children, onClose, className = "", verre = false }) {
  const ref = useRef(null);
  useEffect(() => {
    const prev = document.activeElement;
    ref.current.showModal();
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prevOverflow;
      prev?.focus();
    };
  }, []);
  const fenetre = (
    <dialog
      ref={ref}
      onCancel={(e) => {
        e.preventDefault();
        onClose();
      }}
      aria-labelledby="dialog-title"
      className={`parchment modal${className ? ` ${className}` : ""}`}
    >
      <div className="modal-heading">
        <h2 id="dialog-title">{title}</h2>
        <button className="text-button" onClick={onClose}>
          Fermer
        </button>
      </div>
      {children}
    </dialog>
  );
  return verre ? <div className="interior modal-verre-racine">{fenetre}</div> : fenetre;
}
