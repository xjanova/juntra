import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/astronomy/birth_data_store.dart';
import '../../core/astronomy/natal_chart.dart';
import '../../shared/widgets/gold_button.dart';

/// Bottom sheet that lets the user enter their own birth date, time and
/// place so the natal chart is computed for *them* instead of the demo.
///
/// Place is chosen from [kThaiBirthPlaces] rather than asked as raw
/// latitude/longitude — friendlier, and every Thai province is UTC+7 so the
/// timezone is implicit. On save it persists via [birthDataProvider].
Future<void> showBirthDataEditor(BuildContext context, BirthData current) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: JuntraColors.bgPurpleDeep,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _BirthDataEditor(current: current),
  );
}

class _BirthDataEditor extends ConsumerStatefulWidget {
  const _BirthDataEditor({required this.current});
  final BirthData current;

  @override
  ConsumerState<_BirthDataEditor> createState() => _BirthDataEditorState();
}

class _BirthDataEditorState extends ConsumerState<_BirthDataEditor> {
  late DateTime _date;
  late TimeOfDay _time;
  late BirthPlace _place;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    _date = DateTime(c.year, c.month, c.day);
    _time = TimeOfDay(hour: c.hour, minute: c.minute);
    // Match the current place by name, else default to the first entry.
    _place = kThaiBirthPlaces.firstWhere(
      (p) => p.name == c.placeName,
      orElse: () => kThaiBirthPlaces.first,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      helpText: 'เลือกวันเกิด',
      builder: _datePickerTheme,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'เลือกเวลาเกิด',
      builder: (ctx, child) => _datePickerTheme(
        ctx,
        MediaQuery(
          // Force 24h input — Thai users read birth time in 24h.
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      ),
    );
    if (picked != null) setState(() => _time = picked);
  }

  /// Tints the Material date/time pickers to the app's gold-on-purple look.
  Widget _datePickerTheme(BuildContext context, Widget? child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: JuntraColors.gold,
          onPrimary: JuntraColors.bgPurpleDeep,
          surface: JuntraColors.bgPurpleDeep,
          onSurface: JuntraColors.textCream,
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: JuntraColors.bgPurpleDeep,
        ),
      ),
      child: child!,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final data = BirthData(
      year: _date.year, month: _date.month, day: _date.day,
      hour: _time.hour, minute: _time.minute,
      lat: _place.lat, lng: _place.lng,
      placeName: _place.name, tzOffsetHours: 7,
    );
    await ref.read(birthDataProvider.notifier).save(data);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('d MMMM yyyy', 'th').format(_date);
    final timeLabel =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')} น.';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: JuntraColors.gold.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(child: Text('ข้อมูลวันเกิด', style: baiJamjuree(size: 18))),
            const SizedBox(height: 4),
            const Center(
              child: Text('เวลาเกิดยิ่งแม่นยำ ผังดวงยิ่งตรง',
                  style: TextStyle(fontSize: 12, color: JuntraColors.textMuted)),
            ),
            const SizedBox(height: 18),
            _FieldTile(
              icon: Icons.event_outlined,
              label: 'วันเกิด',
              value: dateLabel,
              onTap: _pickDate,
            ),
            const SizedBox(height: 10),
            _FieldTile(
              icon: Icons.schedule_outlined,
              label: 'เวลาเกิด',
              value: timeLabel,
              onTap: _pickTime,
            ),
            const SizedBox(height: 10),
            _PlaceField(
              value: _place,
              onChanged: (p) => setState(() => _place = p),
            ),
            const SizedBox(height: 22),
            GoldButton(
              label: _saving ? 'กำลังบันทึก...' : 'บันทึกและคำนวณผังดวง',
              icon: const Icon(Icons.auto_awesome, size: 18),
              size: GoldButtonSize.lg,
              onPressed: _saving ? null : _save,
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('ยกเลิก',
                    style: TextStyle(color: JuntraColors.textMuted)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.icon, required this.label,
    required this.value, required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(JuntraRadius.card),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: JuntraColors.gold, size: 20),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                  fontSize: 13, color: JuntraColors.textMuted,
                )),
            const Spacer(),
            Text(value,
                style: baiJamjuree(size: 14, color: JuntraColors.textCream)),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right,
                color: JuntraColors.textFaint, size: 18),
          ],
        ),
      ),
    );
  }
}

class _PlaceField extends StatelessWidget {
  const _PlaceField({required this.value, required this.onChanged});
  final BirthPlace value;
  final ValueChanged<BirthPlace> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.place_outlined, color: JuntraColors.gold, size: 20),
          const SizedBox(width: 12),
          const Text('สถานที่เกิด',
              style: TextStyle(fontSize: 13, color: JuntraColors.textMuted)),
          const SizedBox(width: 12),
          // Expanded + isExpanded so a long city name (e.g. "สงขลา (หาดใหญ่)")
          // ellipsizes instead of overflowing the row on narrow screens.
          Expanded(
            child: DropdownButton<BirthPlace>(
              value: value,
              isExpanded: true,
              alignment: AlignmentDirectional.centerEnd,
              dropdownColor: JuntraColors.bgPurpleDeep,
              underline: const SizedBox.shrink(),
              icon: const Icon(Icons.arrow_drop_down, color: JuntraColors.gold),
              style: baiJamjuree(size: 14, color: JuntraColors.textCream),
              items: [
                for (final p in kThaiBirthPlaces)
                  DropdownMenuItem(value: p, child: Text(p.name)),
              ],
              onChanged: (p) => p == null ? null : onChanged(p),
            ),
          ),
        ],
      ),
    );
  }
}
