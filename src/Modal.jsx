import { useEffect, useRef } from "react";

export function Modal({ title, children, onClose }) {
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
  return (
    <dialog
      ref={ref}
      onCancel={(e) => {
        e.preventDefault();
        onClose();
      }}
      aria-labelledby="dialog-title"
      className="parchment modal"
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
}
