import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/account_repository.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/astronomy/birth_data_store.dart';
import '../../core/astronomy/natal_chart.dart';
import '../../core/auth/auth_state.dart';
import '../../core/auth/session.dart';
import '../../shared/widgets/account_feature_page.dart';

class AccountProfileScreen extends ConsumerWidget {
  const AccountProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AccountFeaturePage<AccountProfile>(
    title: 'ข้อมูลโหราศาสตร์', feature: 'account_profile', value: ref.watch(accountProfileProvider),
    onRetry: () => ref.invalidate(accountProfileProvider),
    builder: (profile) => _ProfileForm(key: ValueKey(ref.watch(sessionUserIdProvider)), profile: profile),
  );
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({super.key, required this.profile});
  final AccountProfile profile;
  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _place, _line;
  DateTime? _date;
  TimeOfDay? _time;
  bool _subscribed = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _name = TextEditingController(text: p.name);
    _place = TextEditingController(text: p.birthPlace);
    _line = TextEditingController(text: p.lineId);
    _date = DateTime.tryParse(p.birthDate ?? '');
    final time = (p.birthTime ?? '').split(':');
    if (time.length >= 2) {
      final hour = int.tryParse(time[0]), minute = int.tryParse(time[1]);
      if (hour != null && minute != null && hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
        _time = TimeOfDay(hour: hour, minute: minute);
      }
    }
    _subscribed = p.subscribed;
  }
  @override
  void dispose() { _name.dispose(); _place.dispose(); _line.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Form(key: _form, child: ListView(
    padding: const EdgeInsets.all(20), children: [
      if (widget.profile.email != null) ListTile(title: const Text('อีเมล'), subtitle: Text(widget.profile.email!)),
      if (widget.profile.phone != null) ListTile(title: const Text('เบอร์เข้าสู่ระบบ'), subtitle: Text(widget.profile.phone!)),
      TextFormField(controller: _name, maxLength: 100, enabled: !_busy,
        decoration: const InputDecoration(labelText: 'ชื่อ'),
        validator: (v) => v == null || v.trim().isEmpty ? 'กรุณาระบุชื่อ' : null),
      ListTile(title: const Text('วันเกิด'), subtitle: Text(_date == null ? 'ยังไม่ระบุ' : DateFormat('d MMMM yyyy', 'th').format(_date!)),
        trailing: IconButton(icon: const Icon(Icons.clear), onPressed: _busy ? null : () => setState(() => _date = null)),
        onTap: _busy ? null : () async {
          final date = await showDatePicker(context: context, initialDate: _date ?? DateTime(1995),
            firstDate: DateTime(1900), lastDate: DateTime.now());
          if (mounted && date != null) setState(() => _date = date);
        }),
      ListTile(title: const Text('เวลาเกิด'), subtitle: Text(_time == null ? 'ยังไม่ระบุ' : _time!.format(context)),
        trailing: IconButton(icon: const Icon(Icons.clear), onPressed: _busy ? null : () => setState(() => _time = null)),
        onTap: _busy ? null : () async {
          final time = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 12, minute: 0));
          if (mounted && time != null) setState(() => _time = time);
        }),
      TextFormField(controller: _place, maxLength: 191, enabled: !_busy,
        decoration: const InputDecoration(labelText: 'สถานที่เกิด')),
      TextFormField(controller: _line, maxLength: 100, enabled: !_busy,
        decoration: const InputDecoration(labelText: 'LINE ID')),
      if (widget.profile.zodiac case final zodiac?) ListTile(title: const Text('ราศีไทย'), subtitle: Text('${zodiac['name_th']}')),
      if (widget.profile.chineseZodiac case final zodiac?) ListTile(title: const Text('ปีนักษัตร'), subtitle: Text('${zodiac['name_th']}')),
      SwitchListTile(title: const Text('รับคำทำนายรายวัน'), value: _subscribed,
        onChanged: _busy ? null : (v) => setState(() => _subscribed = v)),
      if (_error != null) Text(_error!),
      const SizedBox(height: 16),
      FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'กำลังบันทึก...' : 'บันทึกข้อมูล')),
    ]));

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final user = ref.read(sessionUserIdProvider);
    setState(() { _busy = true; _error = null; });
    try {
      final repo = await ref.read(accountRepositoryProvider.future);
      final profile = await repo.saveProfile({
        'name': _name.text.trim(), 'birth_date': _date == null ? null : DateFormat('yyyy-MM-dd').format(_date!),
        'birth_time': _time == null ? null : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}',
        'birth_place': _place.text.trim().isEmpty ? null : _place.text.trim(),
        'line_id': _line.text.trim().isEmpty ? null : _line.text.trim(), 'subscribed': _subscribed,
      });
      if (!mounted || user != ref.read(sessionUserIdProvider)) return;
      final place = kThaiBirthPlaces.where((p) => p.name == profile.birthPlace).firstOrNull;
      if (place != null && _date != null && _time != null) {
        await ref.read(birthDataProvider.notifier).save(BirthData(year: _date!.year, month: _date!.month,
          day: _date!.day, hour: _time!.hour, minute: _time!.minute,
          lat: place.lat, lng: place.lng, placeName: place.name, tzOffsetHours: 7));
      }
      if (!mounted) return;
      ref.invalidate(accountProfileProvider);
      await ref.read(authControllerProvider.notifier).refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกข้อมูลแล้ว')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'บันทึกไม่สำเร็จ กรุณาลองใหม่');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
