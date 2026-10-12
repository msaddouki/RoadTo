# RoadTo

Navigation et alertes routières communautaires, sans compte ni traceur.
Une seule app Flutter pour **Android et iOS**, des alertes qui circulent sur
des relais Nostr fédérés et qui expirent seules.

> État : **POC fonctionnel** (jalon J0 et début de J1 du plan). Carte,
> recherche et itinéraire utilisent des services publics en ligne. Le hors
> ligne arrive au J2.

## Ce que fait le POC

- Carte MapLibre (tuiles OpenStreetMap via OpenFreeMap), thème nuit.
- Recherche d'adresse (Photon) ou appui long sur la carte pour choisir une destination.
- Itinéraire Valhalla, guidage pas à pas avec annonces vocales en français,
  heure d'arrivée, recalcul hors route.
- **Conduite simulée** activée par défaut : le trajet est rejoué le long de
  l'itinéraire, pour tout tester sans conduire.
- **Signaler en un geste** : six grandes cases, 5 s pour annuler. Le type
  police reste désactivé tant que le canal L130-11 n'existe pas.
- Alertes reçues en direct des relais, affichées sur la carte et annoncées
  quand elles sont sur la route (« Accident dans 800 m »).
- **« Toujours là ? »** en passant près d'une alerte : oui ou non, et la
  fiabilité se recalcule. Une route fermée signalée devant vous déclenche un
  recalcul qui l'évite.
- Identité générée sur le téléphone (Keystore ou Keychain), clé jetable par
  trajet pour signer les alertes.

## Organisation du dépôt

```
app/                    App Flutter (Android + iOS)
packages/roadto_core/   Cœur en Dart pur : géo, géohash, Nostr, alertes, guidage, simulation
relay/dev_relay/        Relais Nostr de dev, avec la politique d'écriture RoadTo
docs/adr/               Décisions d'architecture
docs/poc.md             Lancer et tester le POC
tool/                   Scripts de CI
```

## Démarrage rapide

```bash
# 1. Relais de dev (dans un terminal)
cd relay/dev_relay && dart pub get && dart run bin/dev_relay.dart

# 2. App, sur un émulateur Android ou un simulateur iOS
cd app && flutter pub get && flutter run
```

Détails, test à deux téléphones et limites : [docs/poc.md](docs/poc.md).

## Tests

```bash
cd packages/roadto_core && dart test   # géo, Nostr, alertes, politique, guidage
cd relay/dev_relay && dart test        # bout en bout : publication, réception < 5 s, expiration
cd app && flutter test                 # écran de signalement, couches de carte
```

La CI construit aussi l'APK Android et l'app iOS (simulateur) à chaque PR ;
les deux sont téléchargeables dans les artefacts du workflow.

## Règle de sécurité

Tests sur route **toujours avec un passager** qui manipule le téléphone.
Tenir son téléphone en conduisant est interdit (art. R412-6-1 du code de la
route). Tout passe d'abord par la simulation.
