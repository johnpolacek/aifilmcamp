/**
 * Rendered in <head>, so it runs before any content paints. Marks the
 * document so CSS can hold intro state under the mark, and skips the mark
 * entirely under reduced motion. If no page controller claims the document in
 * time (a bundle that never arrived), the mark is removed so the page stays
 * readable.
 */
const code = `(function(){var d=document.documentElement;if(window.matchMedia("(prefers-reduced-motion: reduce)").matches)return;d.dataset.motion="js";setTimeout(function(){if(!("motionClaimed" in d.dataset))delete d.dataset.motion},1800)})();`;

export function MotionMark() {
  // biome-ignore lint/security/noDangerouslySetInnerHtml: static inline script, no user input
  return <script dangerouslySetInnerHTML={{ __html: code }} />;
}
