import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_auth/smart_auth.dart';

import '../config.dart';
import '../data/repository.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'icons.dart';
import 'sheets.dart';
import 'widgets.dart';

/// Sign up or log in with name, mobile number and an SMS code. Afterwards,
/// carries on with whatever the customer was doing (joining a cafe).
Future<void> openAuth(BuildContext context) async {
  final app = AppScope.read(context);
  final ok = await showSheet<bool>(context, (_) => const _AuthSheet());
  final pend = app.pendingCafe;
  app.pendingCafe = null;
  if (ok != true || !context.mounted) return;
  if (pend == null) {
    app.toast('Welcome, ${app.me?.name ?? ''}');
  } else if (app.cardFor(pend) != null) {
    await openCard(context, pend);
  } else {
    await openJoin(context, pend);
  }
}

class _AuthSheet extends StatefulWidget {
  const _AuthSheet();
  @override
  State<_AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<_AuthSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _otp = false, _busy = false;
  String? _nameErr, _phoneErr, _codeErr;
  String _status = 'Waiting for your SMS…';
  int _resendIn = 30;
  Timer? _tick, _autoSubmit;

  @override
  void dispose() {
    _tick?.cancel();
    _autoSubmit?.cancel();
    if (_androidSms) SmartAuth.instance.removeUserConsentApiListener();
    _name.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _androidSms => !kIsWeb && defaultTargetPlatform == TargetPlatform.android && !Config.demo;
  String get _digits => _phone.text.replaceAll(RegExp(r'\D'), '');

  Future<void> _send({String? name, String? phone}) async {
    final app = AppScope.read(context);
    final nm = name ?? _name.text.trim(), ph = phone ?? _digits;
    setState(() {
      _nameErr = nm.isEmpty ? 'Enter your name to continue.' : null;
      _phoneErr = RegExp(r'^[6-9]\d{9}$').hasMatch(ph) ? null : 'Enter a valid 10-digit mobile number.';
    });
    if (_nameErr != null || _phoneErr != null) return;
    _name.text = nm;
    _phone.text = fmtPhone(ph);
    setState(() => _busy = true);
    try {
      await app.sendOtp(nm, ph);
      _startOtp();
    } on AppError catch (e) {
      setState(() => _phoneErr = e.message);
    } catch (_) {
      setState(() => _phoneErr = 'Could not send the code. Check your connection.');
    }
    if (mounted) setState(() => _busy = false);
  }

  void _startOtp() {
    _code.clear();
    _tick?.cancel();
    _autoSubmit?.cancel();
    setState(() {
      _otp = true;
      _codeErr = null;
      _resendIn = 30;
      _status = 'Waiting for your SMS…';
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
    if (_androidSms) {
      // Android shows a one-tap "allow" prompt for the incoming SMS
      SmartAuth.instance.getSmsWithUserConsentApi().then((r) {
        final code = r.data?.code;
        if (mounted && code != null && _code.text.isEmpty) _filled(code);
      });
    } else if (Config.demo) {
      // the mock fills a code by itself, like SMS autofill on a phone
      _autoSubmit = Timer(const Duration(milliseconds: 1500), () {
        if (mounted && _code.text.isEmpty) _filled('482916');
      });
    }
  }

  void _filled(String code) {
    _code.text = code;
    setState(() => _status = 'Code filled from your SMS');
    _autoSubmit = Timer(const Duration(milliseconds: 800), _verify);
  }

  Future<void> _verify() async {
    _autoSubmit?.cancel();
    final app = AppScope.read(context);
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text)) {
      setState(() => _codeErr = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _codeErr = null;
    });
    try {
      await app.verifyOtp(_digits, _code.text);
      if (mounted) Navigator.pop(context, true);
      return;
    } on AppError catch (e) {
      setState(() => _codeErr = e.message);
    } catch (_) {
      setState(() => _codeErr = 'Could not check the code. Check your connection.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AutofillGroup(child: _otp ? _otpStep(context) : _formStep(context));

  Widget _formStep(BuildContext context) {
    final p = Palette.of(context);
    final saved = AppScope.of(context).savedAccount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHead(title: 'Sign up or log in', sub: 'Enter your name and mobile number. We’ll text you a code to confirm it.'),
        if (saved != null) ...[
          const SizedBox(height: 16),
          Tap(
            onTap: () => _send(name: saved.name, phone: saved.phone),
            label: 'Continue as ${saved.name}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(18)),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(14)),
                    alignment: Alignment.center,
                    child: Text(saved.name[0].toUpperCase(), style: heading(18, color: p.bg)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Continue as ${saved.name}', style: ts(15, weight: FontWeight.w700)),
                        Text('+91 ${saved.phone.substring(0, 5)} •••${saved.phone.substring(8)}', style: ts(13, color: p.ink2)),
                      ],
                    ),
                  ),
                  Ico(Ico.chevRight, size: 16, color: p.ink),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'or use a different number',
              textAlign: TextAlign.center,
              style: ts(12.5, color: p.ink2),
            ),
          ),
        ],
        const SizedBox(height: 12),
        const FormLabel('Name'),
        Field(controller: _name, autofill: const [AutofillHints.name], capitalize: true, autofocus: saved == null, label: 'Name'),
        if (_nameErr != null) FieldError(_nameErr!),
        const FormLabel('Mobile number'),
        PhoneField(controller: _phone, onSubmit: (_) => _send()),
        if (_phoneErr != null) FieldError(_phoneErr!),
        const SizedBox(height: 16),
        Pill('Send OTP', onTap: _send, busy: _busy, bg: p.ink, fg: p.bg, radius: 16, size: 15, padding: const EdgeInsets.all(15), expand: true),
        const SizedBox(height: 10),
        Text(
          'By continuing you agree to the Terms and Privacy Policy.',
          textAlign: TextAlign.center,
          style: ts(12, color: p.ink2),
        ),
      ],
    );
  }

  Widget _otpStep(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHead(
          title: 'Enter the code',
          subWidget: Text.rich(
            TextSpan(
              style: ts(15, color: p.ink2),
              children: [
                TextSpan(text: 'We sent a 6-digit code to +91 ${_phone.text}. '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Tap(
                    onTap: () => setState(() {
                      _otp = false;
                      _tick?.cancel();
                      _autoSubmit?.cancel();
                    }),
                    label: 'Change number',
                    child: Text(
                      'Change',
                      style: ts(15, weight: FontWeight.w700, color: p.ink).copyWith(decoration: TextDecoration.underline),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const FormLabel('6-digit code', forField: true),
        Semantics(
          label: '6-digit code',
          textField: true,
          child: TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            style: ts(24, weight: FontWeight.w700, spacing: .4),
            decoration: fieldDecoration(context, hint: '••••••'),
            onChanged: (v) {
              _autoSubmit?.cancel();
              if (v.length == 6) _verify();
            },
            onSubmitted: (_) => _verify(),
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          liveRegion: true,
          child: Text(
            _status,
            textAlign: TextAlign.center,
            style: ts(13, weight: FontWeight.w700, color: p.ink2),
          ),
        ),
        if (_codeErr != null) FieldError(_codeErr!),
        const SizedBox(height: 16),
        Pill('Verify and continue', onTap: _verify, busy: _busy, bg: p.ink, fg: p.bg, radius: 16, size: 15, padding: const EdgeInsets.all(15), expand: true),
        const SizedBox(height: 6),
        Center(
          child: Tap(
            onTap: _resendIn > 0
                ? null
                : () {
                    AppScope.read(context).toast('Code sent again');
                    _send();
                  },
            label: _resendIn > 0 ? 'Resend code in $_resendIn seconds' : 'Resend code',
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                _resendIn > 0 ? 'Resend code in ${_resendIn}s' : 'Resend code',
                style: ts(15, weight: FontWeight.w700, color: _resendIn > 0 ? p.ink2 : p.ink),
              ),
            ),
          ),
        ),
        if (Config.demo)
          Text(
            'Demo: the code fills itself in a moment, like SMS autofill on a phone.',
            textAlign: TextAlign.center,
            style: ts(12, color: p.ink2),
          ),
      ],
    );
  }
}
