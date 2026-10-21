// The beta contact, when the deployment sets one (config.js).
const contact = window.ROADTO_CONFIG?.contact;
if (contact) {
  const p = document.getElementById('contact');
  p.textContent = 'Pour rejoindre la bêta, écrivez à ';
  const a = document.createElement('a');
  a.href = `mailto:${contact}`;
  a.textContent = contact;
  p.append(a, '.');
}
