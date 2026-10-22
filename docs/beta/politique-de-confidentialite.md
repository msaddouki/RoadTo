# Politique de confidentialité de RoadTo (bêta)

> **Brouillon à faire relire.** Ce texte décrit fidèlement ce que fait l'app
> au moment de la bêta fermée ; il ne remplace pas l'avis d'un juriste. Les
> mentions entre crochets sont à compléter.

Dernière mise à jour : [date de publication]

## En bref

- RoadTo n'a **pas de compte**, pas de publicité, pas de traceur ni d'outil
  de mesure d'audience, et ne revend rien.
- Votre position **reste sur votre téléphone**. Elle n'en sort que dans les
  cas décrits plus bas, et toujours arrondie ou limitée à ce qui est
  nécessaire.
- Les signalements sont publiés de façon **anonyme** : une clé jetable par
  trajet, une position arrondie à environ 150 m, aucun texte libre.

## Qui est responsable

[Nom ou raison sociale], [adresse], joignable à [adresse e-mail de contact].

## Ce qui reste sur votre téléphone

- Votre position, vos trajets, vos destinations et vos favoris (Maison,
  Travail…).
- Votre identité RoadTo : une clé générée sur le téléphone et gardée dans
  son coffre (Keystore Android, Trousseau iOS). Elle ne signe pas vos
  signalements. Vous seul détenez sa phrase de récupération.
- Les régions hors ligne (carte, recherche, itinéraires).
- Les rapports d'erreur : ils sont enregistrés sur le téléphone, débarrassés
  des positions, des clés et des adresses réseau, et **ne sont jamais
  envoyés**. Vous pouvez choisir de nous en transmettre un vous-même.

Sur Android, ces données sont exclues des sauvegardes Google Drive. Sur iOS,
les réglages et favoris font partie de la sauvegarde de l'appareil ; les
régions en sont exclues.

## Ce qui sort de votre téléphone, et pourquoi

### Signalements et réponses « Toujours là ? »

Quand vous signalez un événement (accident, bouchon, danger, route fermée,
travaux) ou répondez à « Toujours là ? », l'app publie sur les relais
RoadTo :
- le type d'événement ;
- la maille géographique d'environ 150 m × 150 m qui le contient, jamais
  votre position exacte ;
- éventuellement votre cap, arrondi à 10° ;
- une heure d'expiration (de 30 minutes à 12 heures selon le type) ;
- une signature par une clé jetable, renouvelée à chaque trajet : deux
  trajets ne peuvent pas être reliés entre eux par la clé.

Ces messages sont **publics** : n'importe qui peut les lire sur les relais.
Ils sont effacés à leur expiration. Ils ne contiennent ni texte libre, ni
identifiant de votre appareil.

### Abonnement aux alertes

Pour recevoir les alertes, l'app demande aux relais celles des zones
d'environ 5 km × 5 km autour de vous et, pendant un trajet, le long de votre
itinéraire. Le relais connaît donc, le temps de la connexion, ces zones et
votre adresse IP. Les relais RoadTo ne conservent pas les adresses IP : elles
sont retirées de leurs journaux, et la limite anti-abus (30 messages par
minute et par adresse) ne les garde qu'en mémoire.

Vous pouvez choisir d'autres relais dans les réglages, y compris le vôtre.
Un relais que nous n'exploitons pas suit ses propres règles.

### Services en ligne utilisés hors des régions installées

Quand aucune région hors ligne ne couvre ce dont vous avez besoin, l'app
s'adresse à des services publics fondés sur OpenStreetMap :

| Service | Ce qu'il reçoit | Quand |
| --- | --- | --- |
| Tuiles de carte OpenFreeMap | les zones de carte affichées, votre adresse IP | carte en ligne |
| Recherche Photon (Komoot) | le texte recherché, une position approximative pour classer les résultats | recherche hors région |
| Itinéraires Valhalla (FOSSGIS) | le départ, l'arrivée et votre cap | itinéraire hors région, et toujours sur iPhone pendant la bêta |

Sur le site, la page **Itinéraire** utilise les mêmes services, depuis
votre navigateur : Photon reçoit le texte tapé dans les champs de départ et
d'arrivée, Valhalla le départ et l'arrivée choisis, puis le tracé de
l'itinéraire (pour les limitations de vitesse). « Ma position » n'est
demandée qu'à l'appui sur le bouton, ne sert qu'au calcul et ne figure pas
dans le lien à copier. Pendant le **guidage** dans le navigateur, votre
position reste dans la page ; seul un recalcul (sortie de l'itinéraire,
route bloquée signalée) envoie à Valhalla votre position et votre cap du
moment, comme l'app. Le site lui-même ne reçoit ni les lieux, ni le
trajet, ni votre position : ils restent dans votre navigateur et dans
l'adresse de la page, après le `#`.

Ces services ont leurs propres politiques de confidentialité. [Liens à
ajouter.]

### Info trafic des capteurs publics

Des alertes « Bouchon » viennent aussi des capteurs du réseau routier
national (données ouvertes Bison Futé, Licence Ouverte), publiées sur nos
relais par le robot de RoadTo. Elles indiquent leur source. Elles ne
concernent aucun conducteur et le robot ne reçoit rien de vous.

### Téléchargements

Les régions hors ligne et les prix des carburants sont téléchargés depuis
[hébergement : GitHub pendant la bêta], qui reçoit votre adresse IP comme
pour tout téléchargement. Ils sont signés : l'app vérifie qu'ils viennent
bien de RoadTo.

## Ce que nous ne faisons pas

Pas de compte, pas d'historique de vos trajets sur nos serveurs, pas de
profilage, pas de publicité, pas de vente ni de partage de données, pas de
SDK tiers de mesure ou de publicité. L'app Android ne contient pas les
services Google Play.

## Permissions demandées

- **Localisation** (pendant l'utilisation) : guidage, alertes autour de vous.
  Pendant un trajet seulement, elle continue écran éteint ; Android affiche
  alors la notification « Guidage en cours », iOS l'indicateur bleu.
- **Android Auto** : afficher le guidage sur l'écran de la voiture.

## Base légale et durées

Les signalements reposent sur votre action volontaire et sur l'intérêt
légitime d'informer les autres conducteurs ; ils expirent en 12 heures au
plus. Le reste des données ne quitte pas votre téléphone et y reste jusqu'à
ce que vous les effaciez ou désinstalliez l'app.

## Vos droits

Comme nous ne tenons aucun compte et ne relions aucun signalement à une
personne, nous ne pouvons généralement pas retrouver de données vous
concernant. Pour toute question, ou pour exercer vos droits (accès,
effacement, opposition), écrivez à [adresse e-mail]. Vous pouvez aussi
saisir la CNIL (www.cnil.fr).

## Bêta

Pendant la bêta fermée, vous pouvez nous envoyer des retours et des rapports
d'erreur ; vous choisissez ce que vous envoyez, et nous ne nous en servons
que pour corriger l'app.

## Modifications

Nous vous préviendrons dans l'app de tout changement important de cette
politique.
