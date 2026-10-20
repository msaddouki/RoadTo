// Alert icons, drawn here (24×24, white on the alert's colour), so the site
// loads no icon font from a third party.
const svg = (body) =>
  `<svg viewBox="0 0 24 24" width="100%" height="100%" aria-hidden="true" fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;

export const ICONS = {
  // A car with a mark.
  accident: svg('<path d="M4 15l1.6-4.5A2 2 0 0 1 7.5 9h6a2 2 0 0 1 1.9 1.4L17 15"/><rect x="3" y="15" width="15" height="4" rx="1.2"/><circle cx="7" cy="19.5" r="0.6" fill="#fff"/><circle cx="14" cy="19.5" r="0.6" fill="#fff"/><path d="M20 3v5"/><circle cx="20" cy="11" r="0.4" fill="#fff"/>'),
  // A traffic light.
  traffic: svg('<rect x="8" y="2.5" width="8" height="19" rx="3"/><circle cx="12" cy="7" r="1.3" fill="#fff"/><circle cx="12" cy="12" r="1.3" fill="#fff"/><circle cx="12" cy="17" r="1.3" fill="#fff"/>'),
  // A warning triangle.
  hazard: svg('<path d="M12 3.5L21.5 20h-19z"/><path d="M12 10v4.5"/><circle cx="12" cy="17.3" r="0.5" fill="#fff"/>'),
  // No entry.
  closure: svg('<circle cx="12" cy="12" r="8.5"/><path d="M6.5 6.5l11 11"/>'),
  // A traffic cone.
  roadworks: svg('<path d="M9.5 4h5l4 15h-13z"/><path d="M8.2 10h7.6M7 15h10"/><path d="M3.5 20h17"/>'),
};
