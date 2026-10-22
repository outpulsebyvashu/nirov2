import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The mock's inline SVG icons, drawn in the current text colour.
class Ico extends StatelessWidget {
  const Ico(this.svg, {super.key, this.size = 24, this.color});
  final String svg;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      theme: SvgTheme(currentColor: c),
    );
  }

  static const home = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M3 11.2 12 3l9 8.2V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/></svg>';
  static const search =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="6.5"/><path d="M16 16l5 5"/></svg>';
  static const wallet =
      '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M4 7.5A2.5 2.5 0 0 1 6.5 5H17v3H6.5a.9.9 0 0 0 0 1.8H19a1 1 0 0 1 1 1V18a2 2 0 0 1-2 2H6.5A2.5 2.5 0 0 1 4 17.5zM15.5 14.2a1.2 1.2 0 1 0 2.4 0 1.2 1.2 0 0 0-2.4 0z"/></svg>';
  static const pin =
      '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2a7 7 0 0 0-7 7c0 5 7 13 7 13s7-8 7-13a7 7 0 0 0-7-7zm0 9.5A2.5 2.5 0 1 1 12 6.5a2.5 2.5 0 0 1 0 5z"/></svg>';
  static const chevDown =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M6 9l6 6 6-6"/></svg>';
  static const chevRight =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6l6 6-6 6"/></svg>';
  static const x =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M5 5l14 14M19 5L5 19"/></svg>';
  static const user =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8" r="4"/><path d="M4 21c0-4.4 3.6-7 8-7s8 2.6 8 7"/></svg>';
  static const recenter =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="3.5"/><path d="M12 2.5v4M12 17.5v4M2.5 12h4M17.5 12h4"/></svg>';
  static const walk =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="13" cy="4.5" r="1.8"/><path d="M9.5 21l2.2-6-2.2-2 1.5-4.5 4 1.5 2 3M11.7 15l3.3 1.5V21"/></svg>';
  static const check =
      '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>';
}
