import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../data/models.dart';
import '../services/nearby_alerts.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'brand.dart';
import 'icons.dart';
import 'sheets.dart';
import 'widgets.dart';

/// Tests swap in a tile provider without the on-disk cache.
TileProvider? debugTileProvider;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final _map = MapController();
  bool _ready = false;
  String? _flownTo;
  AnimationController? _fly;
  Timer? _loadDebounce, _searchDebounce;
  String _lastQuery = '';
  List<Cafe> _searchHits = [];

  // Direction
  String? _routeFor;
  List<LatLng> _route = [];
  double _routeM = 0;

  // demo walk
  Ticker? _walk;
  bool _rings = false;
  String _lastWalked = '';

  // swipe animation on the place card
  int _slideDir = 0;
  late final _bump = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));

  static const _zoom = 15.0;

  @override
  void dispose() {
    _fly?.dispose();
    _bump.dispose();
    _walk?.dispose();
    _loadDebounce?.cancel();
    _searchDebounce?.cancel();
    super.dispose();
  }

  LatLng _ll(Cafe c) => LatLng(c.lat, c.lng);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    // something selected a cafe (Home rail, search, popup): fly to it
    if (app.selectedId != _flownTo) {
      _flownTo = app.selectedId;
      final c = app.selectedId == null ? null : app.registry[app.selectedId];
      if (c != null && _ready) _flyTo(_ll(c), pinAbove: true);
    }
    if (app.query != _lastQuery) {
      _lastQuery = app.query;
      _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 250), () async {
        final q = app.query.trim();
        final hits = q.isEmpty ? <Cafe>[] : await app.repo.searchCafes(q).catchError((_) => <Cafe>[]);
        for (final c in hits) {
          app.registry.putIfAbsent(c.id, () => c);
        }
        if (mounted) setState(() => _searchHits = hits);
      });
    }
    if (app.routeId != _routeFor) {
      _routeFor = app.routeId;
      _loadRoute();
    }
  }

  /// Animates the camera. With [pinAbove], the point ends up 90 px above
  /// centre so the place card doesn't cover it (as in the mock).
  void _flyTo(LatLng target, {bool pinAbove = false, double? zoom}) {
    final cam = _map.camera;
    final z = zoom ?? math.max(cam.zoom, 14.5);
    final to = pinAbove ? cam.unprojectAtZoom(cam.projectAtZoom(target, z) + const Offset(0, 90), z) : target;
    final from = cam.center, z0 = cam.zoom;
    _fly?.dispose();
    final ctl = _fly = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    final curve = CurvedAnimation(parent: ctl, curve: Curves.easeOutCubic);
    ctl.addListener(() {
      final t = curve.value;
      _map.move(LatLng(from.latitude + (to.latitude - from.latitude) * t, from.longitude + (to.longitude - from.longitude) * t), z0 + (z - z0) * t);
    });
    ctl.forward();
  }

  void recenter() {
    final y = AppScope.read(context).you;
    if (y != null) _flyTo(LatLng(y.lat, y.lng));
  }

  void _onMoved(MapCamera cam) {
    _loadDebounce?.cancel();
    _loadDebounce = Timer(const Duration(milliseconds: 400), () {
      final b = cam.visibleBounds;
      final r = distanceM(b.north, b.west, b.south, b.east) / 2;
      AppScope.read(context).loadAround(cam.center.latitude, cam.center.longitude, r.round() + 500);
    });
    setState(() {}); // area label follows the camera
  }

  Future<void> _loadRoute() async {
    final app = AppScope.read(context);
    final c = app.routeId == null ? null : app.registry[app.routeId];
    final y = app.you;
    if (c == null || y == null) {
      setState(() => _route = []);
      return;
    }
    final from = LatLng(y.lat, y.lng), to = _ll(c);
    // straight line until (or unless) a routing server answers
    setState(() {
      _route = [from, to];
      _routeM = distanceM(y.lat, y.lng, c.lat, c.lng) * 1.25;
    });
    // show both ends between the header and the place card
    final top = MediaQuery.paddingOf(context).top;
    final fit = CameraFit.coordinates(coordinates: [from, to], padding: EdgeInsets.fromLTRB(56, 200 + top, 56, 470)).fit(_map.camera);
    _flyTo(fit.center, zoom: math.min(fit.zoom, 17));
    if (Config.routingUrl.isEmpty) return;
    try {
      final r = await http
          .get(Uri.parse('${Config.routingUrl}/route/v1/foot/${y.lng},${y.lat};${c.lng},${c.lat}?overview=full&geometries=geojson'))
          .timeout(const Duration(seconds: 6));
      final route = (jsonDecode(r.body)['routes'] as List).first as Map<String, dynamic>;
      final coords = (route['geometry']['coordinates'] as List).cast<List>();
      if (!mounted || app.routeId != c.id) return;
      setState(() {
        _route = [for (final p in coords) LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble())];
        _routeM = (route['distance'] as num).toDouble();
      });
    } catch (_) {}
  }

  // ------------------------------------------------------------ demo walk

  /// Demo: walks the blue dot toward a partner cafe until its geofence fires.
  void simulateWalk() {
    final app = AppScope.read(context);
    if (_walk != null || app.you == null) return;
    const far = NearbyAlerts.radiusM + 40;
    final all = app.registry.values.where((c) => app.distanceTo(c) > far).toList()..sort((a, b) => app.distanceTo(a).compareTo(app.distanceTo(b)));
    final c = all.where((c) => c.id != _lastWalked).firstOrNull ?? all.firstOrNull;
    if (c == null) return;
    _lastWalked = c.id;
    app.select(null);
    app.toast('Walking toward ${c.name}…');
    setState(() => _rings = true);
    var last = Duration.zero;
    _walk = createTicker((now) {
      final dt = math.min(64, (now - last).inMilliseconds) / 1000;
      last = now;
      final y = app.you!;
      final d = distanceM(y.lat, y.lng, c.lat, c.lng), stepM = 220 * dt;
      final f = d - stepM <= NearbyAlerts.radiusM ? (d - NearbyAlerts.radiusM) / d : stepM / d;
      final next = (lat: y.lat + (c.lat - y.lat) * f, lng: y.lng + (c.lng - y.lng) * f);
      app.moveYou(next);
      _map.move(LatLng(next.lat, next.lng), _map.camera.zoom);
      if (d - stepM <= NearbyAlerts.radiusM) {
        _walk!.dispose();
        _walk = null;
        app.onGeofence(c.id);
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _rings = false);
        });
      }
    })..start();
  }

  // ---------------------------------------------------------------- build

  String _areaLabel(AppState app) {
    if (app.noPartnersHere) return 'No partner cafes in ${app.city ?? 'this area'}';
    if (!_ready) return app.city ?? '';
    final cen = _map.camera.center;
    Cafe? best;
    var bd = 1500.0;
    for (final c in app.registry.values) {
      final d = distanceM(cen.latitude, cen.longitude, c.lat, c.lng);
      if (d < bd) {
        bd = d;
        best = c;
      }
    }
    return best?.area ?? app.city ?? '';
  }

  bool _matches(Cafe c, String q) => q.isEmpty || '${c.name} ${c.area} ${c.kind}'.toLowerCase().contains(q);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), p = Palette.of(context);
    final pad = MediaQuery.paddingOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final you = app.you;
    if (you == null) {
      return ColoredBox(
        color: p.card2,
        child: Center(
          child: Text('Locating…', style: ts(14, color: p.ink2)),
        ),
      );
    }

    final q = app.query.trim().toLowerCase();
    final places = app.noPartnersHere
        ? <Cafe>[]
        : (app.registry.values.toList()..sort((a, b) => (a.id == app.selectedId ? 1 : 0) - (b.id == app.selectedId ? 1 : 0)));

    return Stack(
      children: [
        Positioned.fill(
          child: Semantics(
            label: 'Map of nearby partner cafes. Drag to explore.',
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: LatLng(you.lat, you.lng),
                initialZoom: _zoom,
                minZoom: 4,
                maxZoom: 19,
                backgroundColor: p.card2,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onMapReady: () {
                  _ready = true;
                  final c = app.selectedId == null ? null : app.registry[app.selectedId];
                  if (c != null) _flyTo(_ll(c), pinAbove: true);
                  _onMoved(_map.camera);
                },
                onPositionChanged: (cam, _) => _onMoved(cam),
                onTap: (_, _) {
                  if (app.selectedId != null) app.select(null);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: dark && Config.tileUrlDark.isNotEmpty ? Config.tileUrlDark : Config.tileUrl,
                  userAgentPackageName: Config.packageName,
                  tileProvider: debugTileProvider,
                  tileBuilder: dark && Config.tileUrlDark.isEmpty ? darkModeTileBuilder : null,
                  retinaMode: RetinaMode.isHighDensity(context),
                ),
                if (_rings)
                  CircleLayer(
                    circles: [
                      for (final c in places)
                        CircleMarker(
                          point: _ll(c),
                          radius: NearbyAlerts.radiusM,
                          useRadiusInMeter: true,
                          color: p.you.withValues(alpha: .1),
                          borderColor: p.you.withValues(alpha: .7),
                          borderStrokeWidth: 1.5,
                        ),
                    ],
                  ),
                if (_route.length > 1 && app.routeId != null)
                  PolylineLayer(
                    polylines: [Polyline(points: _route, strokeWidth: 5, color: p.you, borderColor: p.bg, borderStrokeWidth: 2.5)],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(you.lat, you.lng),
                      width: 48,
                      height: 48,
                      child: _YouDot(color: p.you),
                    ),
                    for (final c in places)
                      Marker(
                        point: _ll(c),
                        width: 48,
                        height: 48,
                        child: _Pin(
                          cafe: c,
                          joined: app.cardFor(c.id) != null,
                          selected: c.id == app.selectedId,
                          dim: !_matches(c, q),
                          onTap: () => app.select(c.id),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: gutter,
          right: gutter,
          top: 112 + pad.top,
          child: IgnorePointer(
            // a halo in the page colour keeps the title readable over busy streets
            child: Text(
              _areaLabel(app),
              textAlign: TextAlign.center,
              style: heading(28).copyWith(
                shadows: [
                  for (final r in [2.0, 6.0, 12.0]) Shadow(color: p.bg, blurRadius: r),
                ],
              ),
            ),
          ),
        ),
        // OSM attribution, in the strip under the nav
        Positioned(
          right: gutter + pad.right,
          bottom: 2 + pad.bottom,
          child: Text(
            Config.tileAttribution,
            style: ts(10, color: p.ink2).copyWith(shadows: [Shadow(color: p.bg, blurRadius: 4)]),
          ),
        ),
        Positioned(
          right: gutter + pad.right,
          top: 158 + pad.top,
          child: _Fab(svg: Ico.recenter, label: 'Back to my location', onTap: recenter),
        ),
        if (Config.demo)
          Positioned(
            right: gutter + pad.right,
            top: 212 + pad.top,
            child: _Fab(svg: Ico.walk, label: 'Simulate walking past a cafe', onTap: simulateWalk),
          ),
        Positioned(
          left: gutter + pad.left,
          right: gutter + pad.right,
          bottom: 98 + pad.bottom,
          child: Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: _dock(app, q)),
          ),
        ),
      ],
    );
  }

  Widget _dock(AppState app, String q) {
    if (app.noPartnersHere) return const SizedBox.shrink();
    if (q.isNotEmpty) {
      final res = {
        for (final c in [...app.registry.values.where((c) => _matches(c, q)), ..._searchHits]) c.id: c,
      }.values.toList()..sort((a, b) => app.distanceTo(a).compareTo(app.distanceTo(b)));
      final top = res.take(5).toList();
      return _Pop(
        child: top.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(6),
                child: Text('No cafe or restaurant matches that search.', style: ts(15)),
              )
            : Column(
                children: [
                  for (final (i, c) in top.indexed)
                    ResultRow(
                      title: c.name,
                      note: '${c.kind} · ${fmtDistance(app.distanceTo(c))}',
                      last: i == top.length - 1,
                      onTap: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        app.select(c.id);
                      },
                    ),
                ],
              ),
      );
    }
    final c = app.selectedId == null ? null : app.registry[app.selectedId];
    if (c == null) return const SizedBox.shrink();
    final dir = _slideDir;
    return AnimatedBuilder(
      animation: _bump,
      builder: (context, child) {
        final t = _bump.value;
        final dx = t < .4
            ? -8 * t / .4
            : t < .7
            ? -8 + 13 * (t - .4) / .3
            : 5 * (1 - t) / .3;
        return Transform.translate(offset: Offset(_bump.isAnimating ? dx : 0, 0), child: child);
      },
      child: GestureDetector(
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() > 200) _swipe(v < 0 ? 1 : -1);
        },
        child: TweenAnimationBuilder<double>(
          key: ValueKey(c.id),
          tween: Tween(begin: dir == 0 ? 0 : 1, end: 0),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          builder: (_, t, child) => Opacity(
            opacity: 1 - .7 * t,
            child: Transform.translate(offset: Offset(40 * t * dir, 0), child: child),
          ),
          child: _PlaceCard(cafe: c, routeM: app.routeId == c.id ? _routeM : null),
        ),
      ),
    );
  }

  /// Swipe the place card to the next or previous of the 12 nearest places.
  void _swipe(int dir) {
    final app = AppScope.read(context);
    final l = app.nearList;
    var i = l.indexWhere((c) => c.id == app.selectedId);
    if (i < 0) i = dir > 0 ? -1 : l.length;
    final n = i + dir;
    if (n < 0 || n >= l.length) {
      _bump.forward(from: 0);
      return;
    }
    _slideDir = dir;
    app.select(l[n].id);
  }
}

// ------------------------------------------------------------- pieces

class _Pop extends StatelessWidget {
  const _Pop({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.sheet,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: Color(0x2E000000), offset: Offset(0, 10), blurRadius: 30)],
      ),
      child: child,
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.cafe, this.routeM});
  final Cafe cafe;
  final double? routeM;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), p = Palette.of(context);
    final joined = app.cardFor(cafe.id) != null, routed = app.routeId == cafe.id;
    final offer = app.offers.where((o) => o.cafeId == cafe.id).firstOrNull;
    final near = app.nearList, idx = near.indexWhere((c) => c.id == cafe.id);
    return _Pop(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 92,
              child: ColoredBox(color: p.card2, child: Storefront(cafe)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Flexible(
                child: OpenBadge(open: cafe.isOpen, text: cafe.hoursLabel),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${cafe.kind} · ${fmtDistance(app.distanceTo(cafe))}',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(13, color: p.ink2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(cafe.name, style: heading(21, height: 1.15).copyWith(letterSpacing: -.21)),
          if (offer != null) ...[const SizedBox(height: 10), Text(offer.title, style: ts(14, color: p.ink2))],
          if (routed && routeM != null) ...[
            const SizedBox(height: 10),
            Text('Route · ${fmtDistance(routeM!)} · ${walkMinutes(routeM!)} min walk', style: ts(14, weight: FontWeight.w700)),
          ],
          const SizedBox(height: 12),
          Actions2(
            primary: joined ? 'Show Card' : 'Join Loyalty',
            onPrimary: () => joined ? openCard(context, cafe.id) : openJoin(context, cafe.id),
            secondary: 'Direction',
            secondaryOn: routed,
            onSecondary: () => app.toggleRoute(cafe.id),
          ),
          if (idx >= 0) ...[
            const SizedBox(height: 12),
            ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var k = 0; k < near.length; k++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      width: k == idx ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: p.ink.withValues(alpha: k == idx ? 1 : .2),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A cafe on the map: filled ink when you hold its card, outlined otherwise.
class _Pin extends StatelessWidget {
  const _Pin({required this.cafe, required this.joined, required this.selected, required this.dim, required this.onTap});
  final Cafe cafe;
  final bool joined, selected, dim;
  final VoidCallback onTap;

  // the mock's ICON_C (cup) and ICON_R (fork and knife), centred on 0,0
  static const _cup = 'M-6 -4h9v5a4.5 4.5 0 0 1-9 0zM3 -3h2a2.2 2.2 0 0 1 0 4.4H3';
  static const _fork = 'M-4.5 -7v5a2.5 2.5 0 0 0 5 0v-5M-2 -7v14M6 7v-14c-3.2 2-3.2 7.5 0 9.5';

  static String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final fill = joined ? p.ink : p.bg, stroke = joined ? p.bg : p.ink;
    final svg =
        '<svg viewBox="-20 -20 40 40"><circle r="17" fill="${_hex(fill)}" stroke="${_hex(stroke)}" stroke-width="3"/>'
        '<path d="${cafe.isRestaurant ? _fork : _cup}" fill="none" stroke="${_hex(stroke)}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    return Tap(
      onTap: onTap,
      label: '${cafe.name}${joined ? ', card in your wallet' : ''}',
      selected: selected,
      child: Opacity(
        opacity: dim ? .25 : 1,
        child: AnimatedScale(
          scale: selected ? 1.3 : 1,
          duration: const Duration(milliseconds: 150),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: selected ? const [BoxShadow(color: Color(0x59000000), blurRadius: 10, offset: Offset(0, 3))] : null,
            ),
            child: SvgPicture.string(svg, width: 40, height: 40),
          ),
        ),
      ),
    );
  }
}

class _YouDot extends StatelessWidget {
  const _YouDot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'You are here',
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .18)),
        ),
        Container(
          width: 21,
          height: 21,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
      ],
    ),
  );
}

class _Fab extends StatelessWidget {
  const _Fab({required this.svg, required this.label, required this.onTap});
  final String svg, label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Tap(
      onTap: onTap,
      label: label,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: p.sheet,
          border: Border.all(color: p.line),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x29000000), offset: Offset(0, 6), blurRadius: 18)],
        ),
        alignment: Alignment.center,
        child: Ico(svg, size: 22, color: p.ink),
      ),
    );
  }
}
