# ADR 0005 — Alertes sur Nostr, relais fédérés

- Statut : accepté (POC) ; kinds provisoires à figer avant la bêta
- Date : 2026-10-12

## Décision

Les alertes et les réponses à « toujours là ? » sont des événements Nostr
(NIP-01) publiés sur plusieurs relais. Les relais de production seront
strfry avec un plugin de write-policy (J3). Le dépôt fournit un relais de
dev en Dart (`relay/dev_relay`) qui applique **la même politique**
(`checkWritePolicy` du cœur).

### Événement d'alerte (kind 4550, provisoire)

| Tag | Valeur | Rôle |
| --- | --- | --- |
| `t` | `accident`, `traffic`, `hazard`, `closure`, `roadworks` (`police` coupé) | type |
| `g` | géohash à 4, 5, 6 et 7 caractères | abonnement par maille, position |
| `expiration` | horodatage Unix (NIP-40) | durée de vie selon le type |
| `bearing` | cap arrondi à 10° (facultatif) | sens de circulation |
| `nonce` | NIP-13 | preuve de travail, 12 bits |

Le contenu est vide : pas de texte libre. La position publiée est la maille
géohash 7 (environ 150 m × 150 m), jamais la position exacte.

### Réponse « toujours là ? » (kind 4551, provisoire)

Tags `e` (alerte visée), `g` (mêmes mailles que l'alerte), `still`
(`yes` ou `no`), `expiration` (celle de l'alerte), PoW 8 bits.

### Durées de vie

Bouchon 30 min, danger 45 min, accident 60 min, travaux 12 h, route fermée
6 h.

### Fiabilité

Calculée sur chaque téléphone (`AlertStore.reliability`) : une alerte neuve
vaut 1 et s'use avec le temps ; chaque « oui » la rafraîchit, chaque « non »
pèse plus qu'un « oui » ; une seule réponse par clé ; l'auteur ne peut pas
confirmer sa propre alerte. Sous 0,35, l'alerte est masquée.

### Vie privée

- Une clé jetable par trajet signe les alertes : deux trajets ne peuvent pas
  être reliés par leur clé.
- L'identité durable (clé dans le Keystore ou le Keychain) ne signe pas les
  alertes.
- Le relais de dev ne journalise aucune adresse IP.

### Politique d'écriture des relais

Liste blanche de kinds, signature valide, PoW minimale, expiration
obligatoire et bornée par type, géohash valides et cohérents (préfixes les
uns des autres, 7 caractères au plus), type connu, refus du type police tant
que le flag est coupé, limite de débit par connexion.
