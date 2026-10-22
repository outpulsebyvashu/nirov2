import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme.dart';

/// The cafe's background pattern (.pt-dots, .pt-stripes, .pt-rings, .pt-grid).
class PatternPainter extends CustomPainter {
  PatternPainter(this.brand);
  final Brand brand;

  Color _ink(double a) => brand.ink.withValues(alpha: a);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    switch (brand.pat) {
      case CardPattern.dots:
        final p = Paint()..color = _ink(.16);
        for (var y = 8.0; y < size.height + 16; y += 16) {
          for (var x = 8.0; x < size.width + 16; x += 16) {
            canvas.drawCircle(Offset(x, y), 2.3, p);
          }
        }
      case CardPattern.stripes:
        // repeating-linear-gradient(135deg, ink 0 8px, transparent 8px 18px):
        // 8px bands every 18px, running from top right to bottom left
        final p = Paint()
          ..color = _ink(.10)
          ..strokeWidth = 8;
        final d = size.width + size.height;
        for (var o = 0.0; o < d; o += 18 * math.sqrt2) {
          canvas.drawLine(Offset(o, 0), Offset(o - size.height, size.height), p);
        }
      case CardPattern.rings:
        final p = Paint()
          ..color = _ink(.12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        final r = math.sqrt(size.width * size.width + size.height * size.height);
        for (var i = 1.0; i < r; i += 14) {
          canvas.drawCircle(Offset(size.width, 0), i, p);
        }
      case CardPattern.grid:
        final p = Paint()
          ..color = _ink(.11)
          ..strokeWidth = 1.5;
        for (var x = .75; x < size.width; x += 18) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        }
        for (var y = .75; y < size.height; y += 18) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        }
    }
  }

  @override
  bool shouldRepaint(PatternPainter old) => old.brand != brand;
}

/// A rounded panel in the cafe's colours with its pattern behind [child].
class BrandSurface extends StatelessWidget {
  const BrandSurface({super.key, required this.brand, required this.radius, required this.child, this.padding, this.border});
  final Brand brand;
  final double radius;
  final Widget child;
  final EdgeInsets? padding;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: brand.bg, borderRadius: BorderRadius.circular(radius), border: border),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: PatternPainter(brand),
        child: Padding(
          padding: padding ?? EdgeInsets.zero,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: brand.ink),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The cafe's logo, or its initials on the accent colour (.mono).
class Monogram extends StatelessWidget {
  const Monogram(this.cafe, {super.key, this.size = 36});
  final Cafe cafe;
  final double size;

  @override
  Widget build(BuildContext context) {
    final b = cafe.brand;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: b.acc, borderRadius: BorderRadius.circular(size / 3)),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: cafe.logoUrl != null
          ? Image.network(cafe.logoUrl!, fit: BoxFit.cover, width: size, height: size)
          : Text(initials(cafe.name), style: heading(size * 15 / 36, color: b.bg, height: 1)),
    );
  }
}

/// A row of stamp circles (.dots). [fill] colours the earned ones.
class StampDots extends StatelessWidget {
  const StampDots({super.key, required this.stamps, required this.goal, required this.color, this.fill, this.size = 20});
  final int stamps, goal;
  final Color color;
  final Color? fill;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$stamps of $goal stamps',
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < goal; i++)
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < stamps ? (fill ?? color) : null,
                border: Border.all(color: i < stamps ? (fill ?? color) : color.withValues(alpha: .4), width: 2),
              ),
            ),
        ],
      ),
    );
  }
}

/// Illustrated storefront in the cafe's colours, ported from the mock's
/// photo(). Shown until the cafe uploads its own photos.
class Storefront extends StatelessWidget {
  const Storefront(this.cafe, {super.key});
  final Cafe cafe;

  @override
  Widget build(BuildContext context) {
    if (cafe.photoUrls.isNotEmpty) {
      return Image.network(cafe.photoUrls.first, fit: BoxFit.cover, semanticLabel: 'Photo of ${cafe.name}');
    }
    return Semantics(
      label: 'Illustration of ${cafe.name}',
      child: CustomPaint(painter: _StorefrontPainter(cafe), child: const SizedBox.expand()),
    );
  }
}

class _StorefrontPainter extends CustomPainter {
  _StorefrontPainter(this.cafe);
  final Cafe cafe;

  // the mock's hh() hash, so each cafe's sun and tree sit on the same side every time
  static double hh(int x, int y, int s) {
    int imul(int a, int b) => (a * b).toSigned(32);
    var h = (imul(x, 374761393) + imul(y, 668265263) + imul(s, 2147483647)).toSigned(32);
    h = imul(h ^ (h.toUnsigned(32) >> 13), 1274126177);
    h ^= h.toUnsigned(32) >> 16;
    return h.toUnsigned(32) / 4294967296;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // viewBox 0 0 224 108, preserveAspectRatio xMidYMid slice
    final k = math.max(size.width / 224, size.height / 108);
    canvas.clipRect(Offset.zero & size);
    canvas.translate((size.width - 224 * k) / 2, (size.height - 108 * k) / 2);
    canvas.scale(k);

    final b = cafe.brand, id = cafe.id, rest = cafe.isRestaurant;
    final c0 = id.codeUnitAt(0), c1 = id.length > 1 ? id.codeUnitAt(1) : 0;
    final v = hh(id.length, c0, 5), v2 = hh(c1, id.length, 9);
    Paint fill(Color c, [double a = 1]) => Paint()..color = c.withValues(alpha: a);
    Paint line(Color c, double w, [double a = 1]) => Paint()
      ..color = c.withValues(alpha: a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    RRect rr(double x, double y, double w, double h, double r) => RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));

    canvas.drawRect(const Rect.fromLTWH(0, 0, 224, 108), fill(b.acc));
    canvas.drawRect(const Rect.fromLTWH(0, 0, 224, 108), fill(Colors.white, .38));
    canvas.drawCircle(Offset(v2 > .5 ? 30 : 196, 20), 11, fill(Colors.white, .7));
    canvas.drawRect(const Rect.fromLTWH(26, 26, 172, 70), fill(b.bg));
    canvas.drawRect(const Rect.fromLTWH(26, 20, 172, 12), fill(b.bg));
    canvas.drawRRect(rr(48, 9, 128, 19, 4), fill(b.ink));

    final sign = TextPainter(
      text: TextSpan(
        text: '${initials(cafe.name)}${rest ? ' · KITCHEN' : ' · CAFE'}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: b.bg,
          fontFamily: fBody,
          fontVariations: const [FontVariation('wght', 800)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    sign.paint(canvas, Offset(112 - sign.width / 2, 18.5 - sign.height / 2));

    // awning
    for (var i = 0; i < 6; i++) {
      canvas.drawRect(Rect.fromLTWH(34 + i * 26.7, 30, 26.8, 16), fill(i.isOdd ? b.ink : b.acc));
    }
    // window
    canvas.drawRRect(rr(42, 52, 76, 40, 3), fill(const Color(0xFFFFE3A3)));
    canvas.drawRRect(rr(42, 52, 76, 40, 3), line(b.ink, 2));
    canvas.drawLine(const Offset(80, 52), const Offset(80, 92), line(b.ink, 1.5, .7));
    canvas.drawLine(const Offset(42, 72), const Offset(118, 72), line(b.ink, 1.5, .7));
    if (rest) {
      canvas.drawLine(const Offset(54, 52), const Offset(54, 60), line(b.ink, 1.5));
      canvas.drawLine(const Offset(96, 52), const Offset(96, 60), line(b.ink, 1.5));
      canvas.drawOval(Rect.fromCenter(center: const Offset(54, 64), width: 14, height: 8), fill(b.acc));
      canvas.drawOval(Rect.fromCenter(center: const Offset(96, 64), width: 14, height: 8), fill(b.acc));
    } else {
      // a cup with steam
      canvas.drawRect(const Rect.fromLTWH(52, 81, 16, 11), fill(b.bg, .85));
      final handle = Path()
        ..moveTo(68, 84)
        ..lineTo(72, 84)
        ..arcToPoint(const Offset(72, 90), radius: const Radius.circular(3))
        ..lineTo(68, 90);
      canvas.drawPath(handle, line(b.bg, 1.6, .85));
      for (final sx in [56.0, 62.0]) {
        final steam = Path()
          ..moveTo(sx, 78)
          ..cubicTo(sx - 2, 75, sx + 2, 74, sx, 71);
        canvas.drawPath(steam, line(b.bg, 1.4, .6));
      }
    }
    // door
    canvas.drawRRect(rr(136, 52, 46, 44, 3), fill(b.ink, .92));
    canvas.drawCircle(const Offset(174, 76), 2.2, fill(b.bg));
    canvas.drawRRect(rr(144, 60, 30, 10, 2), fill(b.acc));
    // pavement
    canvas.drawRect(const Rect.fromLTWH(0, 92, 224, 16), fill(b.bg, .92));
    canvas.drawRect(const Rect.fromLTWH(0, 92, 224, 2), fill(b.ink, .25));
    // tree
    final px = v > .5 ? 18.0 : 190.0;
    canvas.drawRRect(rr(px - 5, 80, 10, 12, 2), fill(b.ink));
    canvas.drawCircle(Offset(px, 76), 8, fill(const Color(0xFF5DA56A)));
    canvas.drawCircle(Offset(px - 5, 81), 5, fill(const Color(0xFF4A8F58)));
    canvas.drawCircle(Offset(px + 5, 81), 5, fill(const Color(0xFF4A8F58)));
  }

  @override
  bool shouldRepaint(_StorefrontPainter old) => old.cafe.id != cafe.id;
}
