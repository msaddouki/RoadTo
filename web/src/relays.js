// A few Nostr relays read at once (NIP-01): one subscription, kept across
// reconnections, events handed over once whatever relay brings them.
export class RelayPool {
  #sockets = new Map();
  #filter = null;
  #seen = new Set();

  /**
   * @param {string[]} urls
   * @param {(event: object) => void} onEvent called once per verified event
   * @param {(event: object) => boolean} verify id and signature check
   * @param {(status: Map<string, string>) => void} onStatus "connecting" | "open" | "closed"
   */
  constructor(urls, { onEvent, verify, onStatus = () => {}, WebSocketImpl = globalThis.WebSocket } = {}) {
    this.urls = urls;
    this.onEvent = onEvent;
    this.verify = verify;
    this.onStatus = onStatus;
    this.WS = WebSocketImpl;
    this.status = new Map(urls.map((u) => [u, 'connecting']));
  }

  connect() {
    for (const url of this.urls) this.#open(url, 1000);
  }

  #open(url, delay) {
    let ws;
    try { ws = new this.WS(url); } catch { this.#set(url, 'closed'); return; }
    this.#sockets.set(url, ws);
    this.#set(url, 'connecting');
    ws.onopen = () => { this.#set(url, 'open'); delay = 1000; if (this.#filter) this.#req(ws); };
    ws.onmessage = (m) => this.#message(m.data);
    ws.onclose = () => {
      this.#set(url, 'closed');
      setTimeout(() => this.#open(url, Math.min(delay * 2, 30000)), delay);
    };
  }

  #set(url, s) { this.status.set(url, s); this.onStatus(this.status); }

  #req(ws) {
    if (ws.readyState !== 1) return;
    ws.send(JSON.stringify(['CLOSE', 'alerts']));
    ws.send(JSON.stringify(['REQ', 'alerts', this.#filter]));
  }

  subscribe(filter) {
    this.#filter = filter;
    for (const ws of this.#sockets.values()) this.#req(ws);
  }

  #message(data) {
    let msg;
    try { msg = JSON.parse(data); } catch { return; }
    if (!Array.isArray(msg) || msg[0] !== 'EVENT' || typeof msg[2] !== 'object') return;
    const e = msg[2];
    if (this.#seen.has(e.id)) return;
    if (!this.verify(e)) return;
    this.#seen.add(e.id);
    this.onEvent(e);
  }
}
