part of 'main.dart';

class BatteryHealthScreen extends StatefulWidget {
  const BatteryHealthScreen({required this.onBack, super.key});
  final VoidCallback onBack;

  @override
  State<BatteryHealthScreen> createState() => _BatteryHealthScreenState();
}

class _BatteryHealthScreenState extends State<BatteryHealthScreen> {
  late Future<dynamic> _details;

  @override
  void initState() {
    super.initState();
    _details = PerAppBackend.instance.command('GET battery.health');
  }

  String _capacityHealth(dynamic details) {
    final double? full = double.tryParse('${details['chargeFull']}');
    final double? design = double.tryParse('${details['chargeFullDesign']}');
    if (full == null || design == null || full <= 0 || design <= 0) return 'Unavailable';
    return '${(full / design * 100).toStringAsFixed(1)}%';
  }

  String _status(int value) => switch (value) {
    1 => 'Charging',
    2 => 'Discharging',
    3 => 'Not charging',
    4 => 'Full',
    0 => 'Unknown',
    _ => 'Unavailable',
  };

  String _voltage(DuchampBackendSnapshot s) => s.batteryVoltageV == null
      ? 'Unavailable' : '${s.batteryVoltageV!.toStringAsFixed(3)} V';
  String _current(DuchampBackendSnapshot s) => s.batteryCurrentA == null
      ? 'Unavailable' : '${(s.batteryCurrentA! * 1000).toStringAsFixed(0)} mA';
  String _temperature(DuchampBackendSnapshot s) => s.batteryTempC == null
      ? 'Unavailable' : '${s.batteryTempC!.toStringAsFixed(1)} °C';

  Widget _row(String label, String value, ColorScheme colors) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(children: <Widget>[
      Expanded(child: Text(label, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13))),
      const SizedBox(width: 12),
      Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return FutureBuilder<dynamic>(
      future: _details,
      builder: (BuildContext context, AsyncSnapshot<dynamic> detailState) =>
      StreamBuilder<DuchampBackendSnapshot>(
      stream: DuchampBackend.instance.snapshots,
      initialData: DuchampBackend.instance.latest,
      builder: (BuildContext context, AsyncSnapshot<DuchampBackendSnapshot> state) {
        final DuchampBackendSnapshot s = state.data ?? DuchampBackend.instance.latest;
        final dynamic details = detailState.data is Map ? detailState.data : <String, dynamic>{};
        final String level = s.batteryCapacity >= 0 ? '${s.batteryCapacity}%' : 'Unavailable';
        final String healthPercent = detailState.hasError ? 'Unavailable' : _capacityHealth(details);
        final String cycles = '${details['cycleCount'] ?? 'NA'}';
        final String full = '${details['chargeFull'] ?? 'NA'}';
        final String design = '${details['chargeFullDesign'] ?? 'NA'}';
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: <Widget>[
            SurfaceCard(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  Icon(Icons.health_and_safety_rounded, color: colors.primary, size: 27),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Battery condition', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 18),
                Text(healthPercent, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: Color(0xFF41C98A))),
                const SizedBox(height: 5),
                Text('Battery health · BMS capacity ratio', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                const SizedBox(height: 14),
                Divider(color: colors.outlineVariant.withValues(alpha: 0.55)),
                _row('Charge level', level, colors),
                _row('Battery state', _status(s.batteryStatus), colors),
                _row('Temperature', _temperature(s), colors),
                _row('Voltage', _voltage(s), colors),
                _row('Current', _current(s), colors),
                const SizedBox(height: 4),
                Divider(color: colors.outlineVariant.withValues(alpha: 0.55)),
                _row('Capacity health estimate', healthPercent, colors),
                _row('Charge cycles', cycles == 'NA' ? 'Unavailable' : cycles, colors),
                _row('Full-charge capacity (raw)', full == 'NA' ? 'Unavailable' : full, colors),
                _row('Design capacity (raw)', design == 'NA' ? 'Unavailable' : design, colors),
                if (detailState.connectionState == ConnectionState.waiting)
                  const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
              ]),
            ),
            const SizedBox(height: 12),
            SurfaceCard(
              padding: const EdgeInsets.all(15),
              child: Text('Battery health is calculated as BMS charge_full ÷ charge_full_design × 100. This calculation does not depend on a device region. Cycle count and raw capacity values are shown only when the device exports them; missing kernel data stays unavailable rather than being guessed.', style: TextStyle(color: colors.onSurfaceVariant, height: 1.5)),
            ),
          ],
        );
      },
    ),
    );
  }
}
