# Lancer et tester le POC

## Prérequis

- Flutter 3.47 (stable) : <https://docs.flutter.dev/get-started/install>
- Android : Android Studio (JDK 21, exigé par MapLibre) et un émulateur, ou un téléphone en mode développeur.
- iOS : un Mac avec Xcode (simulateur ou iPhone).

Sans poste de dev mobile, chaque PR produit dans GitHub Actions :

- `roadto-android-apk` : APK à installer sur un téléphone Android ;
- `roadto-ios-simulator` : app pour le simulateur iOS d'un Mac
  (`xcrun simctl install booted Runner.app`).

## 1. Le relais de dev

```bash
cd relay/dev_relay
dart pub get
dart run bin/dev_relay.dart            # écoute sur 0.0.0.0:7777
```

Le relais garde les alertes en mémoire, applique la politique d'écriture
RoadTo et journalise les refus. Les adresses par défaut de l'app :

| Où tourne l'app | Adresse du relais |
| --- | --- |
| Émulateur Android | `ws://10.0.2.2:7777` (par défaut) |
| Simulateur iOS | `ws://127.0.0.1:7777` (par défaut) |
| Vrai téléphone, même Wi-Fi | `ws://<IP du poste>:7777`, à saisir dans Réglages |

## 2. L'app

```bash
cd app
flutter pub get
flutter run
```

1. **Où allez-vous ?** : tapez une adresse (« Part-Dieu, Lyon »), ou faites
   un appui long sur la carte puis **Y aller**.
2. La conduite simulée démarre (50 km/h, réglable). Le bandeau du haut
   affiche la prochaine manœuvre ; la barre du bas, l'heure d'arrivée.
3. **Signaler** (gros bouton orange) : choisissez un type ; l'envoi part
   après 5 s, sauf si vous annulez.

Sans simulation (Réglages > Conduite simulée), l'app suit le GPS : à faire
uniquement avec un passager.

## 3. Deux téléphones, une alerte

Critère du jalon J3, à la main :

1. Lancez le relais sur le poste, et deux instances de l'app (deux émulateurs,
   ou un émulateur et un simulateur) pointant sur le relais.
2. Sur A, lancez un trajet et signalez **Route fermée**.
3. Sur B, lancez un trajet qui passe au même endroit : l'alerte apparaît sur
   la carte, puis « Route fermée dans … ». B recalcule pour l'éviter.
4. Quand B passe à moins de 150 m d'une alerte, **toujours là ?** s'affiche.
   Deux « Non » la font disparaître.

Le même scénario tourne automatiquement dans `relay/dev_relay/test/`.

## Limites du POC

| Sujet | POC | Cible |
| --- | --- | --- |
| Carte | tuiles OpenFreeMap en ligne | PMTiles de la région, hors ligne (J2) |
| Itinéraire | Valhalla public FOSSGIS | valhalla-mobile embarqué (J2) |
| Recherche | Photon en ligne | index SQLite FTS5 du paquet région (J2) |
| Guidage | moteur Dart maison | maison ou Ferrostar (spike C) |
| Relais | relais de dev en mémoire | strfry + plugin, deux relais synchronisés (J3) |
| Identité | clé dans Keystore / Keychain | + phrase de récupération BIP-39 (J3) |
| Localisation Android | geolocator, LocationManager forcé | plugin sans services Google (J2) |
| Voiture | — | Android Auto (J4), CarPlay (après accord d'Apple) |
| Alertes police | désactivées | après le canal L130-11 (J6) |

Les serveurs publics (OpenFreeMap, FOSSGIS, Komoot) sont des services
gracieux : usage de test raisonnable uniquement.
