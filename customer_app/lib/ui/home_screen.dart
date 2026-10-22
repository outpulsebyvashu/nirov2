import 'package:flutter/material.dart';

import '../config.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'auth_sheet.dart';
import 'brand.dart';
import 'sheets.dart';
import 'widgets.dart';

const screenTop = 104.0, screenBottom = 140.0;

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), p = Palette.of(context);
    final pad = MediaQuery.paddingOf(context);
    final heroes = <Widget>[], children = <Widget>[];

    if (app.noPartnersHere) {
      heroes.add(
        Hero2(
          kicker: app.city ?? 'Your area',
          title: 'No partner cafes here yet',
          body: 'Partner cafes will appear here when they join.',
          button: 'Change location',
          onTap: () => openLocation(context),
        ),
      );
    } else {
      if (!app.signedIn) {
        heroes.add(
          Hero2(
            kicker: 'Loyalty cards',
            title: 'Earn a free coffee at partner cafes',
            body: 'Sign up with your mobile number. It takes under a minute.',
            button: 'Sign up or log in',
            onTap: () => openAuth(context),
          ),
        );
      }
      final h = app.closestReward;
      if (h != null) {
        final b = h.cafe.brand;
        heroes.add(
          BrandSurface(
            brand: b,
            radius: 28,
            padding: const EdgeInsets.all(20),
            child: _HeroBody(
              kicker: 'Closest reward',
              title: h.cafe.name,
              dots: StampDots(stamps: h.stamps, goal: h.cafe.stampGoal, color: b.ink),
              body: '${h.toGo} more stamp${h.toGo > 1 ? 's' : ''} to ${h.cafe.rewardLabel}.',
              button: 'Show card',
              onTap: () => openCard(context, h.cafe.id),
              ink: b.ink,
              bg: b.bg,
              dim: b.ink.withValues(alpha: .78),
            ),
          ),
        );
      }

      final near = app.nearby;
      children.add(
        SectionTitle(
          'Nearby',
          note: app.loadingNearby && near.isEmpty ? null : '${near.length} partner cafe${near.length == 1 ? '' : 's'}',
          top: heroes.isEmpty ? 4 : 26,
        ),
      );
      if (app.loadingNearby && near.isEmpty) {
        children.add(
          SizedBox(
            height: 108 + 70,
            child: Center(
              child: Text('Finding cafes near you…', style: ts(14, color: p.ink2)),
            ),
          ),
        );
      } else {
        children.add(
          SizedBox(
            height: 108 + 10 + 16 + 12 + 50,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.zero,
              physics: const SnapPhysics(extent: 236 + 12),
              itemCount: near.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _NearCard(cafe: near[i]),
            ),
          ),
        );
      }

      if (app.offers.isNotEmpty) {
        children.add(const SectionTitle('Offers for you'));
        for (final o in app.offers) {
          final c = app.registry[o.cafeId];
          if (c == null) continue;
          children.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _OfferRow(offer: o, cafe: c),
            ),
          );
        }
      }
      if (Config.demo) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text('Example cafes and offers, for this demo only.', style: ts(12, color: p.ink2)),
          ),
        );
      }
    }

    return RefreshIndicator(
      edgeOffset: screenTop + pad.top,
      color: p.ink,
      onRefresh: () async {
        await app.refreshNearby();
        if (app.signedIn) await app.refreshCards();
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(gutter + pad.left, screenTop + pad.top, gutter + pad.right, screenBottom + pad.bottom),
        children: [
          for (final (i, h) in heroes.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
              child: h,
            ),
          ...children,
        ],
      ),
    );
  }
}

/// The black hero card (.hero).
class Hero2 extends StatelessWidget {
  const Hero2({super.key, required this.kicker, required this.title, required this.body, required this.button, required this.onTap});
  final String kicker, title, body, button;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: p.heroBg, borderRadius: BorderRadius.circular(28)),
      child: _HeroBody(kicker: kicker, title: title, body: body, button: button, onTap: onTap, ink: p.heroInk, bg: p.heroBg, dim: p.heroDim),
    );
  }
}

class _HeroBody extends StatelessWidget {
  const _HeroBody({
    required this.kicker,
    required this.title,
    required this.body,
    required this.button,
    required this.onTap,
    required this.ink,
    required this.bg,
    required this.dim,
    this.dots,
  });
  final String kicker, title, body, button;
  final VoidCallback onTap;
  final Color ink, bg, dim;
  final Widget? dots;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kicker.toUpperCase(),
          style: ts(12, weight: FontWeight.w700, color: dim, spacing: .08),
        ),
        const SizedBox(height: 14),
        Text(title, style: heading(26, color: ink)),
        if (dots != null) ...[const SizedBox(height: 14), dots!],
        const SizedBox(height: 14),
        Text(body, style: ts(15, color: dim, height: 1.4)),
        const SizedBox(height: 14),
        Pill(button, onTap: onTap, bg: ink, fg: bg),
      ],
    );
  }
}

class _NearCard extends StatelessWidget {
  const _NearCard({required this.cafe});
  final Cafe cafe;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), p = Palette.of(context);
    final open = cafe.isOpen;
    return Tap(
      onTap: () => app.select(cafe.id),
      label: '${cafe.name}, ${cafe.area}, ${fmtDistance(app.distanceTo(cafe))}, ${open ? 'open' : 'closed'}',
      child: Container(
        width: 236,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 16),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 108,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: p.card2, child: Storefront(cafe)),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: OpenBadge(open: open, text: open ? 'Open' : 'Closed'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(cafe.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: heading(19, height: 1.15).copyWith(letterSpacing: -.19)),
                  const SizedBox(height: 4),
                  Text(
                    '${cafe.area} · ${fmtDistance(app.distanceTo(cafe))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(13, color: p.ink2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({required this.offer, required this.cafe});
  final Offer offer;
  final Cafe cafe;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), p = Palette.of(context);
    final on = app.saved.contains(offer.id);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.card2,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(offer.title, style: ts(16, weight: FontWeight.w700, height: 1.25)),
                const SizedBox(height: 4),
                Text('${cafe.name} · ${offer.expiryLabel}', style: ts(13, color: p.ink2)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Semantics(
            toggled: on,
            child: Pill(
              on ? 'Saved' : 'Save',
              onTap: () {
                if (!app.signedIn) {
                  openAuth(context);
                } else {
                  app.toggleSaved(offer);
                }
              },
              bg: on ? p.ink : p.card,
              fg: on ? p.bg : p.ink,
              radius: 12,
              size: 13,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}

/// Snaps a scroll position to multiples of [extent] (CSS scroll-snap).
class SnapPhysics extends ScrollPhysics {
  const SnapPhysics({required this.extent, super.parent});
  final double extent;

  @override
  SnapPhysics applyTo(ScrollPhysics? ancestor) => SnapPhysics(extent: extent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) || (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tol = toleranceFor(position);
    var page = position.pixels / extent;
    if (velocity < -tol.velocity) {
      page -= .5;
    } else if (velocity > tol.velocity) {
      page += .5;
    }
    final target = (page.roundToDouble() * extent).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < tol.distance) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity, tolerance: tol);
  }

  @override
  bool get allowImplicitScrolling => false;
}
