import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'auth_sheet.dart';
import 'brand.dart';
import 'icons.dart';
import 'widgets.dart';

// ------------------------------------------------------------- card sheet

/// The loyalty card: brand header, member QR, stamp grid and history.
Future<void> openCard(BuildContext context, String cafeId) => showSheet(context, (_) => _CardSheet(cafeId: cafeId));

class _CardSheet extends StatefulWidget {
  const _CardSheet({required this.cafeId});
  final String cafeId;
  @override
  State<_CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<_CardSheet> {
  Future<List<StampEvent>>? _hist;
  int? _seenStamps;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), p = Palette.of(context);
    final card = app.cardFor(widget.cafeId);
    if (card == null) return const SizedBox(height: 120);
    // reload history whenever staff add stamps while the sheet is open
    if (_seenStamps != card.stamps) {
      _seenStamps = card.stamps;
      _hist = app.repo.history(card.id);
    }
    final c = card.cafe, b = c.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrandBanner(
          cafe: c,
          sub: '${c.area} · ${card.rewardReady ? 'Reward ready' : '${card.toGo} stamp${card.toGo == 1 ? '' : 's'} to your next reward'}',
          onClose: () => Navigator.pop(context),
        ),
        const SizedBox(height: 18),
        Center(
          child: Container(
            width: math.min(220, MediaQuery.sizeOf(context).width * .64),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: QrImageView(
              data: card.memberCode,
              padding: EdgeInsets.zero,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0B0B0B)),
              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0B0B0B)),
              semanticsLabel: 'Member QR code',
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'MEMBER ${card.memberCode}',
          textAlign: TextAlign.center,
          style: ts(13, color: p.ink2, spacing: .06),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [for (var i = 0; i < c.stampGoal; i++) _StampCell(n: i + 1, on: i < card.stamps, brand: b)],
          ),
        ),
        FutureBuilder<List<StampEvent>>(
          future: _hist,
          builder: (context, snap) {
            final rows = snap.data ?? const <StampEvent>[];
            final items = card.stamps == 0 && rows.length <= 1
                ? [('No visits yet', 'Show this QR at the counter')]
                : [for (final e in rows.take(4)) ('${e.at.day.toString().padLeft(2, '0')} ${months[e.at.month - 1]}', e.note)];
            return Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.line)),
              ),
              child: Column(
                children: [
                  for (final (a, b) in items)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: p.line)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a, style: ts(14)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              b,
                              textAlign: TextAlign.right,
                              style: ts(14, color: p.ink2),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Cafe-coloured header used on the card sheet and the nearby popup (.bn).
class BrandBanner extends StatelessWidget {
  const BrandBanner({super.key, required this.cafe, required this.sub, required this.onClose, this.closeLabel = 'Close'});
  final Cafe cafe;
  final String sub, closeLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final b = cafe.brand;
    return BrandSurface(
      brand: b,
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Monogram(cafe),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(cafe.name, style: heading(24, color: b.ink)),
                ),
                const SizedBox(height: 4),
                Text(sub, style: ts(14, color: b.ink.withValues(alpha: .75))),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CloseBox(onTap: onClose, bg: b.ink.withValues(alpha: .18), fg: b.ink, label: closeLabel),
        ],
      ),
    );
  }
}

class _StampCell extends StatelessWidget {
  const _StampCell({required this.n, required this.on, required this.brand});
  final int n;
  final bool on;
  final Brand brand;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final label = Text(
      on ? '✓' : '$n',
      style: ts(12, weight: FontWeight.w700, color: on ? brand.acc : p.ink2),
    );
    if (on) {
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: brand.bg,
          border: Border.all(color: brand.acc, width: 2),
        ),
        alignment: Alignment.center,
        child: label,
      );
    }
    return CustomPaint(
      painter: _DashedCircle(p.ink2),
      child: Center(child: label),
    );
  }
}

class _DashedCircle extends CustomPainter {
  _DashedCircle(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final r = size.shortestSide / 2 - 1, c = size.center(Offset.zero);
    final n = (2 * math.pi * r / 9).floor(), step = 2 * math.pi / n;
    for (var i = 0; i < n; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), i * step, step * .55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}

// ------------------------------------------------------------------ join

/// "Join Loyalty": signs in first if needed, then asks for the name and
/// whether to get the cafe's offers.
Future<void> openJoin(BuildContext context, String cafeId) async {
  final app = AppScope.read(context);
  if (!app.signedIn) {
    app.pendingCafe = cafeId;
    return openAuth(context);
  }
  if (app.cardFor(cafeId) != null) return openCard(context, cafeId);
  final joined = await showSheet<bool>(context, (_) => _JoinSheet(cafeId: cafeId));
  if (joined == true && context.mounted) await _showJoined(context, cafeId);
}

class _JoinSheet extends StatefulWidget {
  const _JoinSheet({required this.cafeId});
  final String cafeId;
  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  late final _name = TextEditingController(text: AppScope.read(context).me?.name ?? '');
  bool _offers = false, _busy = false, _nameErr = false;

  Future<void> _submit() async {
    final app = AppScope.read(context);
    final name = _name.text.trim();
    setState(() => _nameErr = name.isEmpty);
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await app.join(widget.cafeId, name: name, offers: _offers);
      if (mounted) Navigator.pop(context, true);
    } on AppError catch (e) {
      app.toast(e.message);
    } catch (_) {
      app.toast('Could not join. Check your connection.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), p = Palette.of(context);
    final c = app.registry[widget.cafeId]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHead(title: 'Join ${c.name}', sub: 'Takes 10 seconds. Your number stays private.'),
        const SizedBox(height: 18),
        FormLabel('Name', forField: true),
        Field(controller: _name, autofill: const [AutofillHints.givenName], autofocus: true, capitalize: true, onSubmit: (_) => _submit(), label: 'Name'),
        if (_nameErr) const FieldError('Enter your name to continue.'),
        const FormLabel('Mobile number'),
        PhoneField(controller: TextEditingController(text: fmtPhone(app.me?.phone ?? '')), readOnly: true),
        const SizedBox(height: 4),
        Tap(
          onTap: () => setState(() => _offers = !_offers),
          label: 'Send me offers from ${c.name}',
          selected: _offers,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: _offers,
                  onChanged: (v) => setState(() => _offers = v ?? false),
                  activeColor: p.ink,
                  checkColor: p.bg,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Send me offers from ${c.name}', style: ts(14, weight: FontWeight.w500)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Pill('Join Loyalty', onTap: _submit, busy: _busy, bg: p.ink, fg: p.bg, radius: 16, size: 15, padding: const EdgeInsets.all(15), expand: true),
        const SizedBox(height: 10),
        Text(
          'You can turn offers off any time in Profile.',
          textAlign: TextAlign.center,
          style: ts(12, color: p.ink2),
        ),
      ],
    );
  }
}

Future<void> _showJoined(BuildContext context, String cafeId) {
  final c = AppScope.read(context).registry[cafeId]!;
  return showPopup(context, (ctx) {
    final p = Palette.of(ctx);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(shape: BoxShape.circle, color: p.ink),
          alignment: Alignment.center,
          child: Ico(Ico.check, size: 30, color: p.bg),
        ),
        const SizedBox(height: 14),
        Text('You’re in!', style: heading(26)),
        const SizedBox(height: 8),
        Text(
          'To start earning stamps, show your card at the counter when you pay at ${c.name}.',
          textAlign: TextAlign.center,
          style: ts(15, color: p.ink2),
        ),
        const SizedBox(height: 18),
        Actions2(
          primaryFirst: false,
          primary: 'Show my card',
          onPrimary: () {
            Navigator.pop(ctx);
            openCard(context, cafeId);
          },
          secondary: 'Later',
          onSecondary: () => Navigator.pop(ctx),
        ),
      ],
    );
  });
}

// ------------------------------------------------------------- location

Future<void> openLocation(BuildContext context) => showSheet(context, (ctx) {
  final app = AppScope.of(ctx);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SheetHead(title: 'Your location', sub: 'Detected from your phone. Change it if it is wrong.'),
      const SizedBox(height: 12),
      ResultRow(
        title: 'Use my current location',
        note: 'Auto-detect',
        onTap: () {
          Navigator.pop(ctx);
          app.locate();
        },
      ),
      for (final (i, c) in app.cities.indexed)
        ResultRow(
          title: c.name,
          note: c.name == app.city ? 'Selected' : '',
          last: i == app.cities.length - 1,
          onTap: () {
            Navigator.pop(ctx);
            app.chooseCity(c);
          },
        ),
    ],
  );
});

// -------------------------------------------------------------- confirm

Future<bool> confirm(BuildContext context, {required String title, required String body, required String action}) async {
  final ok = await showSheet<bool>(
    context,
    (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHead(title: title, sub: body),
        const SizedBox(height: 20),
        Actions2(
          primaryFirst: false,
          primary: action,
          onPrimary: () => Navigator.pop(ctx, true),
          secondary: 'Cancel',
          onSecondary: () => Navigator.pop(ctx, false),
        ),
      ],
    ),
  );
  return ok ?? false;
}

// --------------------------------------------------------- nearby popup

Future<void> showNearbyPopup(BuildContext context, Cafe c, {required VoidCallback onDirections}) {
  final app = AppScope.read(context);
  final offer = app.offers.where((o) => o.cafeId == c.id).firstOrNull;
  return showPopup(context, (ctx) {
    final p = Palette.of(ctx);
    final joined = AppScope.of(ctx).cardFor(c.id) != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrandBanner(cafe: c, sub: 'You’re ${fmtDistance(app.distanceTo(c))} away', onClose: () => Navigator.pop(ctx), closeLabel: 'Dismiss'),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 4),
          child: Text(offer?.title ?? 'Show your card to earn a stamp.', style: ts(15)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 14),
          child: Text('Nearby alert ${app.geoToday} of 2 today', style: ts(13, color: p.ink2)),
        ),
        Actions2(
          primary: joined ? 'Show Card' : 'Join Loyalty',
          onPrimary: () {
            Navigator.pop(ctx);
            joined ? openCard(context, c.id) : openJoin(context, c.id);
          },
          secondary: 'Direction',
          onSecondary: () {
            Navigator.pop(ctx);
            onDirections();
          },
        ),
      ],
    );
  });
}

// ---------------------------------------------------------- form parts

class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {super.key, this.forField = false});
  final String text;
  final bool forField;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: forField ? 0 : 10, bottom: 10),
    child: Text(
      text,
      style: ts(13, weight: FontWeight.w700, color: Palette.of(context).ink2),
    ),
  );
}

class FieldError extends StatelessWidget {
  const FieldError(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Semantics(
      liveRegion: true,
      child: Text(text, style: ts(13, weight: FontWeight.w700)),
    ),
  );
}

InputDecoration fieldDecoration(BuildContext context, {String? hint, bool boxed = true}) {
  final p = Palette.of(context);
  OutlineInputBorder border(Color c, [double w = 1.5]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: ts(16, color: p.ink2),
    filled: boxed,
    fillColor: p.card2,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: boxed ? border(p.line) : InputBorder.none,
    enabledBorder: boxed ? border(p.line) : InputBorder.none,
    focusedBorder: boxed ? border(p.ink, 2) : InputBorder.none,
  );
}

class Field extends StatelessWidget {
  const Field({
    super.key,
    required this.controller,
    this.autofill = const [],
    this.hint,
    this.keyboard,
    this.autofocus = false,
    this.capitalize = false,
    this.maxLength,
    this.onSubmit,
    this.onChanged,
    this.label,
  });
  final TextEditingController controller;
  final List<String> autofill;
  final String? hint, label;
  final TextInputType? keyboard;
  final bool autofocus, capitalize;
  final int? maxLength;
  final ValueChanged<String>? onSubmit, onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    textField: true,
    child: TextField(
      controller: controller,
      autofillHints: autofill,
      autofocus: autofocus,
      keyboardType: keyboard,
      textCapitalization: capitalize ? TextCapitalization.words : TextCapitalization.none,
      inputFormatters: [if (maxLength != null) LengthLimitingTextInputFormatter(maxLength)],
      style: ts(16),
      decoration: fieldDecoration(context, hint: hint),
      onSubmitted: onSubmit,
      onChanged: onChanged,
    ),
  );
}

/// "98765 43210" from 9876543210.
String fmtPhone(String d) => d.length > 5 ? '${d.substring(0, 5)} ${d.substring(5)}' : d;

/// Keeps digits only, max 10, with a space after the fifth (as the mock does).
class PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue next) {
    var d = next.text.replaceAll(RegExp(r'\D'), '');
    if (d.length > 10) d = d.substring(d.length - 10); // pasted +91…
    final t = fmtPhone(d);
    return TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }
}

/// +91 prefix and a 10-digit number (.ph).
class PhoneField extends StatelessWidget {
  const PhoneField({super.key, required this.controller, this.readOnly = false, this.onSubmit, this.autofocus = false});
  final TextEditingController controller;
  final bool readOnly, autofocus;
  final ValueChanged<String>? onSubmit;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.card2,
        border: Border.all(color: p.line, width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text('+91', style: ts(16, weight: FontWeight.w700)),
          ),
          Expanded(
            child: Semantics(
              label: 'Mobile number',
              textField: true,
              child: TextField(
                controller: controller,
                readOnly: readOnly,
                autofocus: autofocus,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: [PhoneFormatter()],
                style: ts(16, color: readOnly ? p.ink2 : p.ink),
                decoration: fieldDecoration(context, hint: '98765 43210', boxed: false).copyWith(contentPadding: const EdgeInsets.fromLTRB(10, 14, 16, 14)),
                onSubmitted: onSubmit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
