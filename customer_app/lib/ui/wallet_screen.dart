import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'auth_sheet.dart';
import 'brand.dart';
import 'home_screen.dart';
import 'sheets.dart';
import 'widgets.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), p = Palette.of(context);
    final pad = MediaQuery.paddingOf(context);
    final list = app.cards;
    final insets = EdgeInsets.fromLTRB(gutter + pad.left, screenTop + pad.top, gutter + pad.right, 100 + pad.bottom);

    if (list.isEmpty) {
      return ListView(
        padding: insets,
        children: [
          const SectionTitle('Your cards', top: 4),
          app.signedIn
              ? Hero2(
                  kicker: 'No cards yet',
                  title: 'Join a partner cafe',
                  body: 'Find a cafe on the map and tap Join Loyalty to start earning stamps.',
                  button: 'Open map',
                  onTap: () => app.setTab(AppTab.map),
                )
              : Hero2(
                  kicker: 'Not signed in',
                  title: 'Sign up to get your cards',
                  body: 'Join a cafe’s loyalty card and your stamps will show up here.',
                  button: 'Sign up or log in',
                  onTap: () => openAuth(context),
                ),
        ],
      );
    }

    return Padding(
      padding: insets,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle('Your cards', note: '${list.length} cafe${list.length == 1 ? '' : 's'}', top: 4, bottom: 8),
          Expanded(child: _Carousel(cards: list)),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Scroll to browse · tap the front card to show your QR',
              textAlign: TextAlign.center,
              style: ts(12, color: p.ink2),
            ),
          ),
        ],
      ),
    );
  }
}

/// One card always sits fully in the middle; the rest peek out above and
/// below as stacks. Same geometry as the mock (step 120, peek 62, gap 10).
class _Carousel extends StatefulWidget {
  const _Carousel({required this.cards});
  final List<LoyaltyCard> cards;
  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  static const step = 120.0, peek = 62.0, gap = 10.0;
  late final ScrollController _sc;

  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    _sc = ScrollController(initialScrollOffset: math.min(app.walletIndex, widget.cards.length - 1) * step);
    _sc.addListener(() => app.walletIndex = (_sc.offset / step).round());
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.cards.length;
    return LayoutBuilder(
      builder: (context, box) {
        final a = box.maxHeight, h = math.min(204.0, a - 24);
        return ShaderMask(
          // fade the stacks at the top and bottom edges
          shaderCallback: (r) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
            stops: [0, 14 / r.height, 1 - 30 / r.height, 1],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            controller: _sc,
            physics: const SnapPhysics(extent: step),
            child: SizedBox(
              height: a + math.max(0, n - 1) * step,
              child: AnimatedBuilder(
                animation: _sc,
                builder: (context, _) {
                  final off = _sc.hasClients ? _sc.offset : _sc.initialScrollOffset;
                  final pos = off / step, ft = (a - h) / 2, front = pos.round();
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < n; i++)
                        Positioned(
                          left: 0,
                          right: 0,
                          height: h,
                          // the layer is sticky: card positions are relative to the viewport
                          top: off + _y(i - pos, ft, h),
                          child: _WalletCard(
                            card: widget.cards[i],
                            front: i == front,
                            onTap: () => i == front
                                ? openCard(context, widget.cards[i].cafe.id)
                                : _sc.animateTo(i * step, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  double _y(double d, double ft, double h) {
    if (d < 0) return ft + d * peek;
    if (d <= 1) return ft + d * (h + gap);
    return ft + (h + gap) + (d - 1) * peek;
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.card, required this.front, required this.onTap});
  final LoyaltyCard card;
  final bool front;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = card.cafe, b = c.brand;
    return Tap(
      onTap: onTap,
      label: '${c.name}, ${card.stamps} of ${c.stampGoal} stamps${card.rewardReady ? ', reward ready' : ''}',
      selected: front,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [BoxShadow(color: Color(0x24000000), offset: Offset(0, -6), blurRadius: 18)],
        ),
        child: BrandSurface(
          brand: b,
          radius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: heading(22, color: b.ink),
                        ),
                        const SizedBox(height: 3),
                        Text(c.area, style: ts(13, color: b.ink.withValues(alpha: .7))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (card.rewardReady)
                    Container(
                      margin: const EdgeInsets.only(right: 8, top: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(color: b.acc, borderRadius: BorderRadius.circular(99)),
                      child: Text(
                        'REWARD READY',
                        style: ts(11, weight: FontWeight.w700, color: b.bg, spacing: .05),
                      ),
                    ),
                  Monogram(c),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: StampDots(stamps: card.stamps, goal: c.stampGoal, color: b.ink, fill: b.acc, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${card.stamps}',
                          style: heading(30, color: b.ink, height: 1),
                        ),
                        TextSpan(
                          text: ' / ${c.stampGoal}',
                          style: ts(13, color: b.ink),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
