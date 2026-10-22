import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'sheets.dart';
import 'widgets.dart';

Future<void> openEditProfile(BuildContext context) => showSheet(context, (_) => const _EditSheet());

class _DayRow {
  _DayRow(String label, this.day) : label = TextEditingController(text: label);
  final TextEditingController label;
  DateTime? day;
}

class _EditSheet extends StatefulWidget {
  const _EditSheet();
  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final Profile me = AppScope.read(context).me!;
  late final _name = TextEditingController(text: me.name);
  late final _email = TextEditingController(text: me.email ?? '');
  late final _fav = TextEditingController(text: me.usualOrder ?? '');
  late DateTime? _birthday = me.birthday;
  late Diet? _diet = me.diet;
  late final List<_DayRow> _days = [for (final d in me.specialDays) _DayRow(d.label, d.day)];
  ImageProvider? _photo;
  bool _photoChanged = false, _busy = false;
  Uint8List? _newPhoto;
  String? _nameErr, _emailErr;

  @override
  void initState() {
    super.initState();
    _photo = me.photo;
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _fav, ..._days.map((d) => d.label)]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      // a square-ish 512px JPEG is plenty for a 72px avatar
      final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      setState(() {
        _newPhoto = bytes;
        _photo = MemoryImage(bytes);
        _photoChanged = true;
      });
    } catch (_) {
      if (mounted) AppScope.read(context).toast('Could not read that image');
    }
  }

  Future<DateTime?> _pickDate(DateTime? initial, {bool pastOnly = false}) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? DateTime(now.year - (pastOnly ? 25 : 0), now.month, now.day),
      firstDate: DateTime(1920),
      lastDate: pastOnly ? now : DateTime(now.year + 5),
    );
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final name = _name.text.trim(), email = _email.text.trim();
    setState(() {
      _nameErr = name.isEmpty ? 'Enter your name to continue.' : null;
      _emailErr = email.isEmpty || RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ? null : 'Enter a valid email address.';
    });
    if (_nameErr != null || _emailErr != null) return;
    setState(() => _busy = true);
    try {
      await app.saveProfile(
        ProfileEdit(
          name: name,
          birthday: _birthday,
          email: email.isEmpty ? null : email,
          diet: _diet,
          usualOrder: _fav.text.trim().isEmpty ? null : _fav.text.trim(),
          specialDays: [
            for (final d in _days)
              if (d.day != null) SpecialDay(d.label.text.trim().isEmpty ? 'Special day' : d.label.text.trim(), d.day!),
          ],
          newPhoto: _newPhoto,
          removePhoto: _photoChanged && _photo == null,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context);
      app.toast('Saved');
    } catch (_) {
      app.toast('Could not save. Check your connection.');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    String dateText(DateTime? d) => d == null ? 'Not set' : '${d.day} ${months[d.month - 1]} ${d.year}';
    Widget dateBox(DateTime? d, VoidCallback onTap, String label) => Tap(
      onTap: onTap,
      label: '$label, ${dateText(d)}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: p.card2,
          border: Border.all(color: p.line, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(dateText(d), style: ts(16, color: d == null ? p.ink2 : p.ink)),
      ),
    );
    final initial = (_name.text.trim().isEmpty ? me.name : _name.text.trim()).characters.first.toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHead(title: 'Edit profile', sub: 'Your mobile number is verified and can’t be changed here.'),
        const SizedBox(height: 18),
        Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: p.heroInk,
                borderRadius: BorderRadius.circular(18),
                image: _photo == null ? null : DecorationImage(image: _photo!, fit: BoxFit.cover),
              ),
              alignment: Alignment.center,
              child: _photo == null ? Text(initial, style: heading(30, color: p.heroBg)) : null,
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Pill('Change photo', onTap: _pickPhoto, bg: p.card, fg: p.ink, radius: 12, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9)),
                if (_photo != null) ...[
                  const SizedBox(height: 8),
                  Pill(
                    'Remove',
                    onTap: () => setState(() {
                      _photo = null;
                      _newPhoto = null;
                      _photoChanged = true;
                    }),
                    bg: p.card,
                    fg: p.ink,
                    radius: 12,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  ),
                ],
              ],
            ),
          ],
        ),
        const FormLabel('Name'),
        Field(controller: _name, autofill: const [AutofillHints.givenName], capitalize: true, onChanged: (_) => setState(() {}), label: 'Name'),
        if (_nameErr != null) FieldError(_nameErr!),
        const FormLabel('Birthday'),
        dateBox(_birthday, () async {
          final d = await _pickDate(_birthday, pastOnly: true);
          if (d != null) setState(() => _birthday = d);
        }, 'Birthday'),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Cafes can send you a treat on the day. Only day and month are shown.', style: ts(12.5, color: p.ink2)),
        ),
        const FormLabel('Email (optional)'),
        Field(controller: _email, autofill: const [AutofillHints.email], keyboard: TextInputType.emailAddress, hint: 'you@example.com', label: 'Email'),
        if (_emailErr != null) FieldError(_emailErr!),
        const FormLabel('Special days'),
        for (final (i, d) in _days.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Field(controller: d.label, hint: 'e.g. Anniversary', maxLength: 24, label: 'Name of special day'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: dateBox(d.day, () async {
                    final v = await _pickDate(d.day);
                    if (v != null) setState(() => d.day = v);
                  }, 'Date'),
                ),
                const SizedBox(width: 8),
                CloseBox(onTap: () => setState(() => _days.removeAt(i).label.dispose()), label: 'Remove date'),
              ],
            ),
          ),
        if (_days.length < 5)
          Align(
            alignment: Alignment.centerLeft,
            child: Pill(
              '+ Add a special day',
              onTap: () => setState(() => _days.add(_DayRow('', null))),
              bg: p.card,
              fg: p.ink,
              radius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        const FormLabel('Food preference'),
        DropdownButtonFormField<Diet?>(
          initialValue: _diet,
          items: [
            const DropdownMenuItem(value: null, child: Text('Not set')),
            for (final d in Diet.values) DropdownMenuItem(value: d, child: Text(d.label)),
          ],
          onChanged: (v) => setState(() => _diet = v),
          style: ts(16, color: p.ink),
          dropdownColor: p.sheet,
          borderRadius: BorderRadius.circular(14),
          decoration: fieldDecoration(context),
        ),
        const FormLabel('Usual order (optional)'),
        Field(controller: _fav, hint: 'e.g. Oat flat white', maxLength: 40, label: 'Usual order'),
        const SizedBox(height: 16),
        Pill('Save', onTap: _save, busy: _busy, bg: p.ink, fg: p.bg, radius: 16, size: 15, padding: const EdgeInsets.all(15), expand: true),
      ],
    );
  }
}
