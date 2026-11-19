part of 'main.dart';

class GlobalRefreshScreen extends StatefulWidget {
  const GlobalRefreshScreen({required this.onBack, super.key});
  final VoidCallback onBack;

  @override
  State<GlobalRefreshScreen> createState() => _GlobalRefreshScreenState();
}

class _GlobalRefreshScreenState extends State<GlobalRefreshScreen> {
  int _current = 0;
  Set<int> _supported = <int>{60, 90, 120};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dynamic reply = await PerAppBackend.instance.command('GET global.refresh');
      if (!mounted) return;
      setState(() {
        _current = (reply['current'] as num?)?.toInt() ?? 0;
        _supported = ((reply['supported'] as List?) ?? const <dynamic>[])
            .whereType<num>()
            .map((num value) => value.toInt())
            .toSet();
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _set(int hz) async {
    if (_busy || !_supported.contains(hz) && hz != 0) return;
    setState(() { _busy = true; _error = null; });
    try {
      final dynamic reply = await PerAppBackend.instance.command('SET global.refresh $hz');
      if (!mounted) return;
      setState(() {
        _current = (reply['current'] as num?)?.toInt() ?? hz;
        _supported = ((reply['supported'] as List?) ?? const <dynamic>[])
            .whereType<num>().map((num value) => value.toInt()).toSet();
      });
      DuchampBackend.instance.haptic(1);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final List<int> rates = <int>[0, 60, 90, 120]
        .where((int hz) => hz == 0 || _supported.contains(hz)).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: <Widget>[
        SurfaceCard(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Icon(Icons.screen_rotation_rounded, color: colors.primary, size: 28),
            const SizedBox(height: 12),
            const Text('Whole-system refresh rate', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            Text('Applies to the system display, including the launcher and system UI. Per-app profiles remain separate and may temporarily override this setting.', style: TextStyle(color: colors.onSurfaceVariant, height: 1.45)),
            const SizedBox(height: 18),
            if (_loading) const Center(child: CircularProgressIndicator()) else Wrap(
              spacing: 9, runSpacing: 9,
              children: rates.map((int hz) {
                final bool selected = _current == hz;
                final String label = hz == 0 ? 'Auto' : '$hz Hz';
                return ChoiceChip(
                  label: Text(label), selected: selected, onSelected: _busy ? null : (_) => _set(hz),
                  avatar: selected ? const Icon(Icons.check_rounded, size: 17) : null,
                );
              }).toList(),
            ),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: colors.error, height: 1.4))),
          ]),
        ),
        const SizedBox(height: 12),
        SurfaceCard(
          padding: const EdgeInsets.all(15),
          child: Text('Auto restores the display preferences captured before the first manual change. Available rates are detected from the connected internal display; unsupported modes are not offered.', style: TextStyle(color: colors.onSurfaceVariant, height: 1.45)),
        ),
      ],
    );
  }
}
