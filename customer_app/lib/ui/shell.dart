import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'auth_sheet.dart';
import 'home_screen.dart';
import 'icons.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'sheets.dart';
import 'wallet_screen.dart';
import 'widgets.dart';

/// One phone screen: fixed header, the current tab, and the floating pill nav.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.onAlertsChanged});
  final Future<void> Function(bool on) onAlertsChanged;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _mapKey = GlobalKey<MapScreenState>();
  StreamSubscription<UiEvent>? _events;
  Timer? _clock;
  bool _mapOpened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _events ??= AppScope.read(context).events.listen(_onEvent);
    // the signed-out greeting follows the time of day
    _clock ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && !AppScope.read(context).signedIn) setState(() {});
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  void _onEvent(UiEvent e) {
    if (!mounted) return;
    switch (e) {
      case ToastEvent(:final message):
        Toaster.show(context, message);
      case NearbyEvent(:final cafe):
        showNearbyPopup(
          context,
          cafe,
          onDirections: () {
            final app = AppScope.read(context);
            app.select(cafe.id);
            app.toggleRoute(cafe.id);
          },
        );
    }
  }

  void _simulateWalk() {
    AppScope.read(context).setTab(AppTab.map);
    WidgetsBinding.instance.addPostFrameCallback((_) => _mapKey.currentState?.simulateWalk());
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), p = Palette.of(context);
    final t = app.tab;
    // the map loads tiles, so build it the first time someone opens it
    _mapOpened |= t == AppTab.map;
    return Scaffold(
      backgroundColor: p.bg,
      resizeToAvoidBottomInset: false,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Stack(
            children: [
              // keep each tab alive so scroll positions and the map survive switching
              Positioned.fill(
                child: IndexedStack(
                  index: t.index,
                  children: [
                    const HomeScreen(),
                    _mapOpened
                        ? TickerMode(
                            enabled: t == AppTab.map,
                            child: MapScreen(key: _mapKey),
                          )
                        : const SizedBox.shrink(),
                    const WalletScreen(),
                    ProfileScreen(onSimulateWalk: _simulateWalk, onAlertsChanged: widget.onAlertsChanged),
                  ],
                ),
              ),
              Positioned(left: 0, right: 0, top: 0, child: _Header(over: t == AppTab.map)),
              Positioned(left: 0, right: 0, bottom: 0, child: _Nav(tab: t)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.over});
  final bool over;

  static String greet() {
    final h = DateTime.now().hour;
    return h < 12
        ? 'Good morning'
        : h < 17
        ? 'Good afternoon'
        : 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), p = Palette.of(context);
    final pad = MediaQuery.paddingOf(context);
    final prof = app.tab == AppTab.profile;
    final title = prof ? 'Profile' : (app.signedIn && app.me != null ? 'Hi, ${app.me!.name}' : greet());
    final bg = over ? p.bg.withValues(alpha: .78) : p.bg;

    Widget body = Container(
      padding: EdgeInsets.fromLTRB(gutter + pad.left, 14 + pad.top, gutter + pad.right, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bg, bg, bg.withValues(alpha: 0)],
          stops: [0, over ? .6 : .7, 1],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(28)),
                ),
                if (!prof)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Tap(
                      onTap: () => openLocation(context),
                      label: 'Location, ${app.locating ? 'locating' : app.city ?? 'not set'}. Tap to change',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Ico(Ico.pin, size: 16, color: p.ink),
                          const SizedBox(width: 6),
                          Opacity(
                            opacity: app.locating ? .5 : 1,
                            child: Text(app.locating ? 'Locating…' : app.city ?? 'Choose location', style: ts(14, weight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 6),
                          Opacity(opacity: .6, child: Ico(Ico.chevDown, size: 14, color: p.ink)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Tap(
            onTap: () {
              if (prof) {
                app.closeProfile();
              } else if (app.signedIn) {
                app.setTab(AppTab.profile);
              } else {
                openAuth(context);
              }
            },
            label: prof
                ? 'Close profile'
                : app.signedIn
                ? 'Profile'
                : 'Sign up or log in',
            child: prof
                ? Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16)),
                    alignment: Alignment.center,
                    child: Ico(Ico.x, size: 18, color: p.ink),
                  )
                : app.signedIn && app.me != null
                ? Avatar(size: 48, radius: 16, bg: p.card, fg: p.ink)
                : Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16)),
                    alignment: Alignment.center,
                    child: Ico(Ico.user, size: 22, color: p.ink),
                  ),
          ),
        ],
      ),
    );
    if (over) {
      body = ClipRect(
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6), child: body),
      );
    }
    return body;
  }
}

class _Nav extends StatefulWidget {
  const _Nav({required this.tab});
  final AppTab tab;
  @override
  State<_Nav> createState() => _NavState();
}

class _NavState extends State<_Nav> {
  final _q = TextEditingController();
  final _focus = FocusNode();

  @override
  void didUpdateWidget(_Nav old) {
    super.didUpdateWidget(old);
    if (widget.tab != AppTab.map && _q.text.isNotEmpty) _q.clear();
  }

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), p = Palette.of(context);
    final pad = MediaQuery.paddingOf(context);
    final mapMode = widget.tab == AppTab.map;
    if (app.query.isEmpty && _q.text.isNotEmpty) _q.clear();

    Widget square(AppTab t, String svg, String label) {
      final on = widget.tab == t;
      return Tap(
        onTap: () => app.setTab(t),
        label: label,
        selected: on,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 58,
          height: 58,
          decoration: BoxDecoration(color: p.navBg, borderRadius: BorderRadius.circular(on ? 29 : 19)),
          alignment: Alignment.center,
          child: Ico(svg, size: 28, color: p.navInk),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(gutter + pad.left, 0, gutter + pad.right, 18 + pad.bottom),
      child: Center(
        child: SizedBox(
          width: 360,
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  square(AppTab.home, Ico.home, 'Home'),
                  const SizedBox(width: 8),
                  // the middle button becomes a search field on the map tab
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: mapMode ? w - 132 : 58,
                    height: 58,
                    decoration: BoxDecoration(color: p.navBg, borderRadius: BorderRadius.circular(mapMode ? 29 : 19)),
                    clipBehavior: Clip.antiAlias,
                    child: Row(
                      children: [
                        Tap(
                          onTap: () {
                            app.setTab(AppTab.map);
                            Future.delayed(const Duration(milliseconds: 250), () => _focus.requestFocus());
                          },
                          label: 'Map and search',
                          selected: mapMode,
                          child: SizedBox(
                            width: 58,
                            height: 58,
                            child: Center(child: Ico(Ico.search, size: 26, color: p.navInk)),
                          ),
                        ),
                        if (mapMode)
                          Expanded(
                            child: TextField(
                              controller: _q,
                              focusNode: _focus,
                              onChanged: app.setQuery,
                              textInputAction: TextInputAction.search,
                              cursorColor: p.navInk,
                              style: ts(15, color: p.navInk),
                              decoration: InputDecoration(
                                hintText: 'Search cafes',
                                hintStyle: ts(15, color: p.navInk.withValues(alpha: .55)),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.only(right: 16),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  square(AppTab.wallet, Ico.wallet, 'Wallet'),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Keeps the OS geofences in step with the account and the cafes nearby.
class NearbySync {
  NearbySync(this.app, this.sync, this.stop);
  final AppState app;
  final Future<void> Function(List<Cafe> cafes, Map<String, String> offers) sync;
  final Future<void> Function() stop;
  String _key = '';

  void attach() => app.addListener(_check);

  void _check() {
    final on = app.signedIn && (app.me?.geoAlerts ?? false) && app.nearby.isNotEmpty;
    final key = on ? app.nearby.take(20).map((c) => c.id).join(',') : 'off';
    if (key == _key) return;
    _key = key;
    if (on) {
      sync(app.nearby, {for (final o in app.offers) o.cafeId: o.title});
    } else {
      stop();
    }
  }
}
