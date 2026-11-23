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
    if (full == null || design == null || full <= 0 || design <= 0) {
      return 'Unavailable';
    }
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
      ? 'Unavailable'
      : '${s.batteryVoltageV!.toStringAsFixed(3)} V';
  String _current(DuchampBackendSnapshot s) => s.batteryCurrentA == null
      ? 'Unavailable'
      : '${(s.batteryCurrentA! * 1000).toStringAsFixed(0)} mA';
  String _temperature(DuchampBackendSnapshot s) => s.batteryTempC == null
      ? 'Unavailable'
      : '${s.batteryTempC!.toStringAsFixed(1)} °C';

  Widget _row(String label, String value, ColorScheme colors) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
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
            builder: (BuildContext context,
                AsyncSnapshot<DuchampBackendSnapshot> state) {
              final DuchampBackendSnapshot s =
                  state.data ?? DuchampBackend.instance.latest;
              final dynamic details = detailState.data is Map
                  ? detailState.data
                  : <String, dynamic>{};
              final String level = s.batteryCapacity >= 0
                  ? '${s.batteryCapacity}%'
                  : 'Unavailable';
              final String healthPercent = detailState.hasError
                  ? 'Unavailable'
                  : _capacityHealth(details);
              final String cycles = '${details['cycleCount'] ?? 'NA'}';
              final String full = '${details['chargeFull'] ?? 'NA'}';
              final String design = '${details['chargeFullDesign'] ?? 'NA'}';

              return DuchampScrollPage(
                children: <Widget>[
                  DetailHeader(
                    title: 'Battery Health',
                    onBack: widget.onBack,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Battery condition, live electrical readings, and capacity data',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  HeroCard(
                    icon: Icons.health_and_safety_rounded,
                    accent: const Color(0xFF41C98A),
                    title: 'Battery condition',
                    subtitle: 'Estimated full-charge capacity health',
                    leading: Container(
                      width: 54,
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF41C98A).withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: const Icon(
                        Icons.battery_5_bar_rounded,
                        color: Color(0xFF41C98A),
                        size: 29,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SurfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  const SectionLabel('"Still alive. Just not for as long."'),
                                  const SizedBox(height: 7),
                                  Text(
                                    healthPercent,
                                    style: const TextStyle(
                                      fontSize: 31,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.8,
                                      color: Color(0xFF41C98A),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (detailState.connectionState ==
                                ConnectionState.waiting)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Battery Health',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const SectionLabel('Live battery readings'),
                  const SizedBox(height: 8),
                  SurfaceCard(
                    child: Column(
                      children: <Widget>[
                        _row('Charge level', level, colors),
                        _row('Battery state', _status(s.batteryStatus), colors),
                        _row('Temperature', _temperature(s), colors),
                        _row('Voltage', _voltage(s), colors),
                        _row('Current', _current(s), colors),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const SectionLabel('Battery capacity details'),
                  const SizedBox(height: 8),
                  SurfaceCard(
                    child: Column(
                      children: <Widget>[
                        _row(
                          'Charge cycles',
                          cycles == 'NA' ? 'Unavailable' : cycles,
                          colors,
                        ),
                        _row(
                          'Full-charge capacity (raw)',
                          full == 'NA' ? 'Unavailable' : full,
                          colors,
                        ),
                        _row(
                          'Design capacity (raw)',
                          design == 'NA' ? 'Unavailable' : design,
                          colors,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SurfaceCard(
                    child: Text(
                      'Cycle count and raw capacity values are shown only when the device exports them. Missing kernel data stays unavailable rather than being guessed.',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        height: 1.5,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
    );
  }
}
