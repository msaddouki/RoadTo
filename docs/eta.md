# Time to arrival

The routing engine (Valhalla) has no traffic data: it times each road from
its kind and limit, cautiously in town. RoadTo corrects that time three
ways (`packages/roadto_core/lib/src/routing/eta.dart`, `EtaEstimator`), the
same in the app and on the web site (`web/src/eta.js`):

1. **The driver's own pace** (`LearnedPace`). During a trip, each stretch
   driven adds its planned and actual time to its kind of road, by the
   engine's planned speed: town (< 40 km/h), road (< 75), fast. When the
   trip ends, that joins what was learned before. A kind of road counts
   after 10 min of driving on it, and fully after about an hour; the
   correction stays between 0.7 and 1.5 times the engine's time, and old
   trips fade (4 h kept per kind). Waiting before moving off, positions off
   the route, gaps over a minute and simulated drives teach nothing. It
   stays on the phone (Réglages > Temps de trajet, with "Oublier") or in the
   browser.
2. **The pace of the last minutes** (`LivePace`): actual over planned time
   over the last 5 min, applied to the next 10 min of the trip only (a jam
   now says little about the end of a long trip), trusted up to 80 %. It
   carries over a reroute.
3. **Reported jams** (`trafficDelays`): each "Bouchon" alert on the route,
   reported heading the same way (within 60°), counts as about 500 m at
   10 km/h instead of the planned speed. When jams lie on the route, the
   engine's alternatives are asked for and the fastest with its jams is
   taken, if it saves at least 2 min and 5 % (`fastestWithJams`); a jam
   reported during a trip looks for such a detour the same way.

On Android, alternatives come from the engine on the phone through
valhalla-mobile's raw call (`routeRaw`), the typed answer having no room for
them; a failure falls back to one route.

Not done on purpose: live traffic from measured speeds (paid data, or
speeds sent by RoadTo's users, which the privacy promises rule out).
