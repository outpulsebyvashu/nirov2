import 'package:flutter/material.dart';

/// Colour tokens from docs/customer-mock.html (:root and the dark overrides).
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.bg,
    required this.ink,
    required this.ink2,
    required this.card,
    required this.card2,
    required this.line,
    required this.navBg,
    required this.navInk,
    required this.good,
    required this.you,
    required this.heroBg,
    required this.heroInk,
    required this.heroDim,
    required this.sheet,
    required this.scrim,
  });

  final Color bg, ink, ink2, card, card2, line, navBg, navInk, good, you;
  final Color heroBg, heroInk, heroDim, sheet, scrim;

  static const light = Palette(
    bg: Color(0xFFF7F7F5),
    ink: Color(0xFF0B0B0B),
    ink2: Color(0xFF62625F),
    card: Color(0xFFDCDCD9),
    card2: Color(0xFFECECEA),
    line: Color(0x1A0B0B0B),
    navBg: Color(0xFF0B0B0B),
    navInk: Color(0xFFFAFAFA),
    good: Color(0xFF2F9E5A),
    you: Color(0xFF2F6FED),
    heroBg: Color(0xFF0B0B0B),
    heroInk: Color(0xFFFAFAFA),
    heroDim: Color(0x9EFAFAFA),
    sheet: Color(0xFFF7F7F5),
    scrim: Color(0x73000000),
  );

  static const dark = Palette(
    bg: Color(0xFF0C0C0C),
    ink: Color(0xFFF3F3F1),
    ink2: Color(0xFFA3A3A0),
    card: Color(0xFF222221),
    card2: Color(0xFF171717),
    line: Color(0x1FF3F3F1),
    navBg: Color(0xFFF3F3F1),
    navInk: Color(0xFF0B0B0B),
    good: Color(0xFF2F9E5A),
    you: Color(0xFF6E9BFF),
    heroBg: Color(0xFFF3F3F1),
    heroInk: Color(0xFF0B0B0B),
    heroDim: Color(0x9E0B0B0B),
    sheet: Color(0xFF161616),
    scrim: Color(0x99000000),
  );

  static Palette of(BuildContext context) => Theme.of(context).extension<Palette>()!;

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) => t < .5 ? this : (other ?? this);
}

const fDisplay = 'Bricolage Grotesque';
const fBody = 'DM Sans';

/// Text style helper. The bundled fonts are variable: set the weight and the
/// optical size (which browsers match to the font size automatically) as axes,
/// so text looks the same as in the mock.
TextStyle ts(double size, {FontWeight weight = FontWeight.w400, bool display = false, Color? color, double? height, double? spacing}) {
  return TextStyle(
    fontFamily: display ? fDisplay : fBody,
    fontSize: size,
    fontWeight: weight,
    fontVariations: [FontVariation('wght', weight.value.toDouble()), FontVariation('opsz', display ? size.clamp(12, 96) : size.clamp(9, 40))],
    color: color,
    height: height,
    letterSpacing: spacing == null ? null : spacing * size,
  );
}

/// The mock's display headings: bold Bricolage with tight tracking.
TextStyle heading(double size, {Color? color, double height = 1.1}) =>
    ts(size, weight: FontWeight.w700, display: true, color: color, height: height, spacing: -.02);

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Palette.dark : Palette.light;
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    fontFamily: fBody,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: p.ink, brightness: b, surface: p.bg, onSurface: p.ink, primary: p.ink, onPrimary: p.bg),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textSelectionTheme: TextSelectionThemeData(cursorColor: p.ink, selectionColor: p.ink.withValues(alpha: .2)),
    extensions: [p],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: fBody, bodyColor: p.ink, displayColor: p.ink),
  );
}
