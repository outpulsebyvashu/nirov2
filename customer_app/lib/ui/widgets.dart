import 'package:flutter/material.dart';

import '../theme.dart';
import 'icons.dart';

const gutter = 16.0;

/// Plain tappable area with no ripple, like the mock's <button>.
class Tap extends StatelessWidget {
  const Tap({super.key, required this.onTap, required this.child, this.label, this.selected});
  final VoidCallback? onTap;
  final Widget child;
  final String? label;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      selected: selected,
      enabled: onTap != null,
      excludeSemantics: label != null,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: child),
    );
  }
}

/// Filled button (.btn, .acts .p, .acts .s, .submit, .chip).
class Pill extends StatelessWidget {
  const Pill(
    this.text, {
    super.key,
    required this.onTap,
    required this.bg,
    required this.fg,
    this.radius = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
    this.size = 14,
    this.expand = false,
    this.busy = false,
  });
  final String text;
  final VoidCallback? onTap;
  final Color bg, fg;
  final double radius, size;
  final EdgeInsets padding;
  final bool expand, busy;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: ts(size, weight: FontWeight.w700, color: fg),
    );
    return Tap(
      onTap: busy ? null : onTap,
      label: text,
      child: Container(
        padding: padding,
        width: expand ? double.infinity : null,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
        child: busy
            ? Center(
                widthFactor: 1,
                child: SizedBox(
                  width: size + 4,
                  height: size + 4,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                ),
              )
            : label,
      ),
    );
  }
}

/// Two side-by-side actions (.acts): primary on the left in ink.
class Actions2 extends StatelessWidget {
  const Actions2({
    super.key,
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    this.secondaryOn = false,
    this.primaryFirst = true,
  });
  final String primary, secondary;
  final VoidCallback onPrimary, onSecondary;
  final bool secondaryOn, primaryFirst;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    const pad = EdgeInsets.symmetric(horizontal: 10, vertical: 13);
    final a = Expanded(
      child: Pill(primary, onTap: onPrimary, bg: p.ink, fg: p.bg, radius: 15, padding: pad),
    );
    final b = Expanded(
      child: Semantics(
        toggled: secondaryOn,
        child: Pill(secondary, onTap: onSecondary, bg: secondaryOn ? p.ink : p.card, fg: secondaryOn ? p.bg : p.ink, radius: 15, padding: pad),
      ),
    );
    return Row(children: primaryFirst ? [a, const SizedBox(width: 10), b] : [b, const SizedBox(width: 10), a]);
  }
}

/// Square close button (.x).
class CloseBox extends StatelessWidget {
  const CloseBox({super.key, required this.onTap, this.bg, this.fg, this.label = 'Close'});
  final VoidCallback onTap;
  final Color? bg, fg;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Tap(
      onTap: onTap,
      label: label,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: bg ?? p.card, borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.center,
        child: Ico(Ico.x, size: 18, color: fg ?? p.ink),
      ),
    );
  }
}

/// Section heading (.sec) with an optional small note on the right.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.note, this.top = 26, this.bottom = 12});
  final String text;
  final String? note;
  final double top, bottom;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Semantics(header: true, child: Text(text, style: heading(20, height: 1.2).copyWith(letterSpacing: -.2))),
          ),
          if (note != null)
            Text(
              note!,
              style: ts(13, weight: FontWeight.w500, color: p.ink2),
            ),
        ],
      ),
    );
  }
}

/// Open/closed badge with a coloured dot (.badge).
class OpenBadge extends StatelessWidget {
  const OpenBadge({super.key, required this.open, required this.text});
  final bool open;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: p.bg, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: open ? p.good : p.ink2),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ts(12, weight: FontWeight.w700, color: p.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Toggle switch (.sw).
class Toggle extends StatelessWidget {
  const Toggle({super.key, required this.on, required this.onChanged, required this.label, this.enabled = true});
  final bool on, enabled;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      toggled: on,
      label: label,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? () => onChanged(!on) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48,
          height: 28,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: on ? p.ink : p.card, borderRadius: BorderRadius.circular(99)),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(shape: BoxShape.circle, color: on ? p.bg : p.ink2),
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- sheets

/// Bottom sheet in the mock's style (.sheet): rounded top, grab handle,
/// up to 88% of the screen, scrolls when taller.
Future<T?> showSheet<T>(BuildContext context, WidgetBuilder builder, {bool grab = true}) {
  final p = Palette.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: p.sheet,
    barrierColor: p.scrim,
    constraints: BoxConstraints(maxWidth: 520, maxHeight: MediaQuery.sizeOf(context).height * .88),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    clipBehavior: Clip.antiAlias,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 24 + MediaQuery.paddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (grab) const Grab(),
            Builder(builder: builder),
          ],
        ),
      ),
    ),
  );
}

/// Centred popup (.scrim.center .sheet), used for "You're in!" and the
/// nearby alert.
Future<T?> showPopup<T>(BuildContext context, WidgetBuilder builder) {
  final p = Palette.of(context);
  return showDialog<T>(
    context: context,
    barrierColor: p.scrim,
    builder: (ctx) => Dialog(
      backgroundColor: p.sheet,
      insetPadding: const EdgeInsets.symmetric(horizontal: gutter, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(gutter, 28, gutter, 20),
          child: Builder(builder: builder),
        ),
      ),
    ),
  );
}

class Grab extends StatelessWidget {
  const Grab({super.key});
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 44,
      height: 5,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: Palette.of(context).line, borderRadius: BorderRadius.circular(9)),
    ),
  );
}

/// Title, subtitle and close button at the top of a sheet (.sh-head).
class SheetHead extends StatelessWidget {
  const SheetHead({super.key, required this.title, this.sub, this.subWidget});
  final String title;
  final String? sub;
  final Widget? subWidget;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(title, style: heading(26))),
              if (sub != null || subWidget != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: subWidget ?? Text(sub!, style: ts(15, color: p.ink2, height: 1.4)),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        CloseBox(onTap: () => Navigator.of(context).pop()),
      ],
    );
  }
}

/// List of tappable rows with a bold title and a grey note (.res).
class ResultRow extends StatelessWidget {
  const ResultRow({super.key, required this.title, required this.note, required this.onTap, this.last = false});
  final String title, note;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Tap(
      onTap: onTap,
      label: '$title, $note',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: p.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: ts(16, weight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Text(note, style: ts(13, color: p.ink2)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- toast

/// Short message above the nav (.toast), gone after 2.4 seconds.
class Toaster {
  static OverlayEntry? _entry;

  static void show(BuildContext context, String msg) {
    _entry?.remove();
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry e;
    e = OverlayEntry(
      builder: (ctx) {
        final p = Palette.of(ctx);
        return Positioned(
          left: gutter,
          right: gutter,
          bottom: 100 + MediaQuery.paddingOf(ctx).bottom,
          child: IgnorePointer(
            // the overlay sits outside any Material, which would underline the text
            child: Material(
              type: MaterialType.transparency,
              child: Center(
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(14)),
                    child: Text(
                      msg,
                      textAlign: TextAlign.center,
                      style: ts(14, weight: FontWeight.w700, color: p.bg),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    _entry = e;
    overlay.insert(e);
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (_entry == e) {
        e.remove();
        _entry = null;
      }
    });
  }
}
