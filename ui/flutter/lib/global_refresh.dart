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
      final dynamic reply =
          await PerAppBackend.instance.command('GET global.refresh');
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
    if (_busy || (!_supported.contains(hz) && hz != 0)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dynamic reply = await PerAppBackend.instance.command(
        'SET global.refresh $hz',
      );
      if (!mounted) return;
      setState(() {
        _current = (reply['current'] as num?)?.toInt() ?? hz;
        _supported = ((reply['supported'] as List?) ?? const <dynamic>[])
            .whereType<num>()
            .map((num value) => value.toInt())
            .toSet();
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
        .where((int hz) => hz == 0 || _supported.contains(hz))
        .toList();
    final String currentLabel = _current == 0 ? 'Auto' : '$_current Hz';

    return DuchampScrollPage(
      children: <Widget>[
        DetailHeader(
          title: 'Global Refresh Rate',
          onBack: widget.onBack,
        ),
        const SizedBox(height: 4),
        Text(
          'Choose the display refresh rate used across the system',
          style: TextStyle(
            fontSize: 13.5,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        HeroCard(
          icon: Icons.screen_rotation_rounded,
          accent: const Color(0xFF7B9CFF),
          title: 'Whole-system refresh rate',
          subtitle:
              'Applies to the launcher and system UI. Per-app profiles remain separate and may temporarily override this setting.',
        ),
        const SizedBox(height: 14),
        const SectionLabel('Refresh rate mode'),
        const SizedBox(height: 8),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Current mode',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    _loading ? 'Loading…' : currentLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: rates.map((int hz) {
                    final bool selected = _current == hz;
                    final String label = hz == 0 ? 'Auto' : '$hz Hz';
                    return ChoiceChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: _busy ? null : (_) => _set(hz),
                      avatar: selected
                          ? const Icon(Icons.check_rounded, size: 17)
                          : null,
                    );
                  }).toList(),
                ),
              if (_busy) ...<Widget>[
                const SizedBox(height: 14),
                const LinearProgressIndicator(),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: colors.error, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        const SectionLabel('About refresh rate'),
        const SizedBox(height: 8),
        SurfaceCard(
          child: Text(
            'Auto restores the display preferences captured before the first manual change. Available rates are detected from the connected internal display; unsupported modes are not offered.',
            style: TextStyle(
              color: colors.onSurfaceVariant,
              height: 1.5,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }
}
