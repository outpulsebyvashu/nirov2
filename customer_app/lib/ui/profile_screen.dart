import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/demo_repository.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'edit_profile_sheet.dart';
import 'home_screen.dart';
import 'icons.dart';
import 'sheets.dart';
import 'widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.onSimulateWalk, required this.onAlertsChanged});

  /// Demo only: the mock's "Try it: walk past a cafe".
  final VoidCallback onSimulateWalk;

  /// Nearby alerts were switched on or off; [on] is the new value.
  final Future<void> Function(bool on) onAlertsChanged;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context), p = Palette.of(context);
    final m = app.me;
    final pad = MediaQuery.paddingOf(context);
    if (m == null) return const SizedBox.shrink();
    final list = app.cards, offersOff = !m.notifyOffers;
    final stamps = list.fold<int>(0, (a, c) => a + c.stamps), ready = list.where((c) => c.rewardReady).length;

    // birthday first, then special days, soonest first
    final days = [if (m.birthday != null) SpecialDay('Birthday', m.birthday!), ...m.specialDays].map((d) => (d, _inDays(d.day))).toList()
      ..sort((a, b) => a.$2.compareTo(b.$2));
    final about = [
      if (m.email != null) ('Email', m.email!),
      if (m.diet != null) ('Food preference', m.diet!.label),
      if (m.usualOrder != null) ('Usual order', m.usualOrder!),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter + pad.left, screenTop + pad.top, gutter + pad.right, screenBottom + pad.bottom),
      children: [
        // .me
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: p.heroBg, borderRadius: BorderRadius.circular(28)),
          child: Row(
            children: [
              Avatar(size: 56, radius: 18, bg: p.heroInk, fg: p.heroBg),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name, style: heading(24, color: p.heroInk)),
                    const SizedBox(height: 3),
                    Text('+91 ••••• •••${m.phone.length == 10 ? m.phone.substring(8) : '••'} · verified', style: ts(13, color: p.heroDim)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Pill(
                'Edit',
                onTap: () => openEditProfile(context),
                bg: p.heroInk,
                fg: p.heroBg,
                radius: 12,
                size: 13,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final (i, (n, l)) in [(list.length, 'Cards'), (stamps, 'Stamps'), (ready, 'Rewards ready')].indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$n', style: heading(26, height: 1).copyWith(letterSpacing: 0)),
                      const SizedBox(height: 4),
                      Text(l, style: ts(12, color: p.ink2)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),

        const _GroupHead('Special days'),
        _Group(
          children: [
            for (final (d, n) in days)
              _Row(
                title: d.label,
                sub: '${d.day.day} ${months[d.day.month - 1]}',
                right: Text(_inText(n), style: ts(14, color: p.ink2)),
              ),
            _NavRow(title: days.isEmpty ? 'Add your birthday and special dates' : 'Add or edit dates', onTap: () => openEditProfile(context)),
            _SwitchRow(
              title: 'Treats on special days',
              sub: 'Cafes you joined may send you a treat',
              on: m.notifyTreats,
              onChanged: (v) => app.setPref('treats', v),
            ),
          ],
        ),

        if (about.isNotEmpty) ...[
          const _GroupHead('About you'),
          _Group(
            children: [
              for (final (k, v) in about)
                _Row(
                  title: k,
                  right: Flexible(
                    child: Text(
                      v,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: ts(14, color: p.ink2),
                    ),
                  ),
                ),
            ],
          ),
        ],

        const _GroupHead('Appearance'),
        _Group(
          pad: true,
          children: [
            Semantics(
              label: 'Theme',
              child: Row(
                children: [
                  for (final (key, label) in [('system', 'System'), ('light', 'Light'), ('dark', 'Dark')]) ...[
                    if (key != 'system') const SizedBox(width: 4),
                    Expanded(
                      child: Tap(
                        onTap: () => app.setTheme(key),
                        label: '$label theme',
                        selected: app.themeKey == key,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                          decoration: BoxDecoration(color: app.themeKey == key ? p.ink : null, borderRadius: BorderRadius.circular(16)),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: ts(14, weight: FontWeight.w700, color: app.themeKey == key ? p.bg : p.ink),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        const _GroupHead('Notifications'),
        _Group(
          children: [
            _SwitchRow(
              title: 'Stamps and rewards',
              sub: 'When you earn a stamp or a reward is ready',
              on: m.notifyStamps,
              onChanged: (v) => app.setPref('stamps', v),
            ),
            _SwitchRow(title: 'Offers from cafes', sub: 'Deals from the cafes you joined', on: m.notifyOffers, onChanged: (v) => app.setPref('offers', v)),
          ],
        ),

        if (list.isNotEmpty) ...[
          const _GroupHead('Offers by cafe'),
          _Group(
            children: [
              for (final c in list)
                Opacity(
                  opacity: offersOff ? .45 : 1,
                  child: _Row(
                    title: c.cafe.name,
                    sub: c.cafe.area,
                    right: Toggle(on: c.offersOptIn, enabled: !offersOff, label: 'Offers from ${c.cafe.name}', onChanged: (v) => app.setCardOffers(c, v)),
                  ),
                ),
            ],
          ),
        ],

        const _GroupHead('Nearby alerts'),
        _Group(
          children: [
            _SwitchRow(
              title: 'Nearby cafe alerts',
              sub: 'A popup when you pass a partner cafe, up to 2 a day. Needs location access set to Always.',
              on: m.geoAlerts,
              onChanged: onAlertsChanged,
            ),
            _Row(
              title: 'Popups today',
              right: Text('${app.geoToday} of 2', style: ts(14, color: p.ink2)),
            ),
            if (Config.demo) ...[
              _NavRow(title: 'Try it: walk past a cafe', onTap: onSimulateWalk),
              _NavRow(
                title: 'Reset today’s count',
                onTap: () {
                  (app.repo as DemoRepository).resetGeoAlerts();
                  app.refreshGeoCount();
                  app.toast('Today’s count reset');
                },
              ),
            ],
          ],
        ),

        const _GroupHead('Location'),
        _Group(
          children: [
            _NavRow(title: 'Current location', value: app.city ?? '', onTap: () => openLocation(context)),
            _Row(
              title: 'Nearby cafes',
              right: Text('While using the app', style: ts(14, color: p.ink2)),
            ),
          ],
        ),

        const _GroupHead('Privacy'),
        _Group(
          children: [
            _NavRow(title: 'Download my data', onTap: () => _export(context)),
            _NavRow(
              title: 'Delete my data',
              onTap: () async {
                if (await confirm(
                  context,
                  title: 'Delete your data?',
                  body: 'This removes your account, cards and stamps. It can’t be undone.',
                  action: 'Delete my data',
                )) {
                  try {
                    await app.deleteAccount();
                    app.toast('Your data was deleted');
                  } catch (_) {
                    app.toast('Could not delete. Check your connection.');
                  }
                }
              },
            ),
          ],
        ),

        const _GroupHead('Help'),
        _Group(
          children: [
            _NavRow(title: 'Help centre', onTap: () => _open(context, Uri.parse(Config.helpUrl))),
            _NavRow(
              title: 'Contact support',
              onTap: () => _open(context, Uri(scheme: 'mailto', path: Config.supportEmail, query: 'subject=Cafe Loyalty help')),
            ),
            _NavRow(title: 'Terms and privacy policy', onTap: () => _open(context, Uri.parse(Config.termsUrl))),
          ],
        ),

        const SizedBox(height: 22),
        Pill(
          'Log out',
          onTap: () async {
            if (await confirm(context, title: 'Log out?', body: 'You will need your mobile number to sign back in.', action: 'Log out')) {
              await app.signOut();
              app.toast('Logged out');
            }
          },
          bg: p.card,
          fg: p.ink,
          radius: 16,
          size: 15,
          padding: const EdgeInsets.all(15),
          expand: true,
        ),
        const SizedBox(height: 24),
        Text(
          Config.demo ? 'Cafe Loyalty demo, example data only' : 'Cafe Loyalty',
          textAlign: TextAlign.center,
          style: ts(12, color: p.ink2),
        ),
      ],
    );
  }

  static int _inDays(DateTime d) {
    final n = DateTime.now(), today = DateTime(n.year, n.month, n.day);
    var x = DateTime(today.year, d.month, d.day);
    if (x.isBefore(today)) x = DateTime(today.year + 1, d.month, d.day);
    return x.difference(today).inDays;
  }

  static String _inText(int n) => n == 0
      ? 'Today'
      : n == 1
      ? 'Tomorrow'
      : 'in $n days';

  static Future<void> _open(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      AppScope.read(context).toast('Could not open that');
    }
  }

  /// Saves a JSON copy of everything we hold and opens the share sheet.
  static Future<void> _export(BuildContext context) async {
    final app = AppScope.read(context);
    try {
      final json = const JsonEncoder.withIndent('  ').convert(await app.repo.exportMyData());
      if (kIsWeb) {
        await Clipboard.setData(ClipboardData(text: json));
        app.toast('Your data was copied');
        return;
      }
      final f = File('${(await getTemporaryDirectory()).path}/cafe-loyalty-my-data.json');
      await f.writeAsString(json);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(f.path, mimeType: 'application/json')],
          subject: 'My Cafe Loyalty data',
        ),
      );
    } catch (_) {
      app.toast('Could not export. Check your connection.');
    }
  }
}

/// The customer's photo, or their initial (.ava, .mav).
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.size, required this.radius, required this.bg, required this.fg});
  final double size, radius;
  final Color bg, fg;

  @override
  Widget build(BuildContext context) {
    final m = AppScope.of(context).me;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        image: m?.photo == null ? null : DecorationImage(image: m!.photo!, fit: BoxFit.cover),
      ),
      alignment: Alignment.center,
      child: m?.photo != null ? null : Text((m?.name ?? '?').characters.first.toUpperCase(), style: heading(size * .45, color: fg, height: 1)),
    );
  }
}

class _GroupHead extends StatelessWidget {
  const _GroupHead(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: ts(12, weight: FontWeight.w700, color: Palette.of(context).ink2, spacing: .08),
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children, this.pad = false});
  final List<Widget> children;
  final bool pad;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: pad ? const EdgeInsets.all(6) : null,
      decoration: BoxDecoration(
        color: p.card2,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(22),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final (i, c) in children.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == children.length - 1 || pad ? null : Border(bottom: BorderSide(color: p.line)),
              ),
              child: c,
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.sub, required this.right});
  final String title;
  final String? sub;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: ts(15, weight: FontWeight.w700)),
                if (sub != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(sub!, style: ts(13, color: p.ink2)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          right,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.title, required this.sub, required this.on, required this.onChanged});
  final String title, sub;
  final bool on;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => _Row(
    title: title,
    sub: sub,
    right: Toggle(on: on, onChanged: onChanged, label: title),
  );
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.title, required this.onTap, this.value});
  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Tap(
      onTap: onTap,
      label: value == null ? title : '$title, $value',
      child: _Row(
        title: title,
        right: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value != null) Text(value!, style: ts(14, color: p.ink2)),
            const SizedBox(width: 6),
            Ico(Ico.chevRight, size: 16, color: p.ink2),
          ],
        ),
      ),
    );
  }
}
