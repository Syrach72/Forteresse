import { useLayoutEffect, useState } from "react";
// Fenêtres transparentes dans un cadre en verre dépoli. `layerRef` est la couche
// de verre (absolue, plein cadre) posée dans `boardRef` ; chaque élément qui
// correspond à `selector` (un lit, une case à débloquer) devient un trou
// rectangulaire de cette couche. Renvoie le tracé SVG à donner à
// clip-path: path(evenodd, ...) ; il est recalculé quand le cadre change de
// taille.
export function useGlassWindows(boardRef, layerRef, selector) {
  const [path, setPath] = useState("");
  useLayoutEffect(() => {
    const board = boardRef.current;
    const layer = layerRef.current;
    if (!board || !layer) return undefined;
    const measure = () => {
      const l = layer.getBoundingClientRect();
      let d = `M0 0H${l.width}V${l.height}H0Z`;
      for (const el of board.querySelectorAll(selector)) {
        const r = el.getBoundingClientRect();
        const x = +(r.left - l.left).toFixed(1);
        const y = +(r.top - l.top).toFixed(1);
        d += `M${x} ${y}h${+r.width.toFixed(1)}v${+r.height.toFixed(1)}h${-(+r.width.toFixed(1))}Z`;
      }
      setPath((old) => (old === d ? old : d));
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(board);
    window.addEventListener("resize", measure);
    return () => {
      observer.disconnect();
      window.removeEventListener("resize", measure);
    };
  });
  return path;
}
