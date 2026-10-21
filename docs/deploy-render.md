# Deploying on Render

`render.yaml` at the root is a Render Blueprint with two services:

| Service | What | Plan |
| --- | --- | --- |
| `roadto-site` | the companion site (`web/`), static, HTTPS | free |
| `roadto-relay` | a RoadTo relay (`relay/strfry`), `wss://roadto-relay.onrender.com` | free (testing) |

Everything is free for testing. A free web service sleeps after 15 minutes
without traffic and takes about a minute to wake on the next connection:
the app retries on its own, so alerts come through once it is up. For the
beta, move the relay to Starter (`plan: starter`) so it stays awake.
Without a disk, a redeploy or a sleep forgets the alerts, which expire
within 12 hours anyway.

## First deployment

1. In Render: **New > Blueprint**, connect GitHub and pick this repository
   (Render's GitHub app also reads private repositories).
2. Render lists the two services; set **ROADTO_CONTACT** (the beta contact
   address, shown on the home page) and **ROADTO_RELAYS**
   (`wss://roadto-relay.onrender.com`, the relay's public address shown on
   its page once created; adjust and redeploy the site if Render added a
   suffix) when asked, then **Apply**.
3. When both are live:
   - the site is at `https://roadto-site.onrender.com` (or the custom
     domain set in the service's settings);
   - its live map reads the relay listed in `ROADTO_RELAYS`;
   - in the app, Réglages > Relais: `wss://roadto-relay.onrender.com`.
4. Check the relay from the repository:
   `cd relay/strfry_policy && dart run tool/smoke.dart wss://roadto-relay.onrender.com wss://roadto-relay.onrender.com`

Every push to master redeploys what changed (`buildFilter`).

## What the configuration does

- The site's build runs `npm ci && npm run build` in `web/` (Node and
  Python 3, both in Render's build image). `ROADTO_RELAYS` and
  `ROADTO_CONTACT` end up in `config.js`.
- Strict headers on the site: a Content Security Policy allowing only the
  site itself, the OpenFreeMap tiles and `wss://` relays; no referrer;
  no camera, microphone or location.
- The relay listens on 7777 (`PORT`), behind Render's TLS. Its rate limit
  reads the client address from `X-Forwarded-For` (`REAL_IP_HEADER`) and
  never writes it out. Render's own request logs are outside our control:
  check the account's log settings, and mention Render in the privacy
  policy as the host.

## Later

- A custom domain for the site (and the relay), for links the apps can
  open directly.
- A second relay elsewhere (another region or host), listed in
  `ROADTO_RELAYS` and in the app, so alerts survive one host going down.
