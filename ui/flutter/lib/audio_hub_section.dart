part of 'main.dart';

/// Audio Hub landing section: routes Bluetooth audio.
class AudioHubSectionScreen extends StatefulWidget {
  const AudioHubSectionScreen({
    super.key,
    required this.onBack,
    required this.onOpen,
  });

  final VoidCallback onBack;
  final void Function(DuchampScreen screen) onOpen;

  @override
  State<AudioHubSectionScreen> createState() => _AudioHubSectionScreenState();
}

class _AudioHubSectionScreenState extends State<AudioHubSectionScreen> {
  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return DuchampScrollPage(
      children: <Widget>[
        DetailHeader(title: 'Audio Hub', onBack: widget.onBack),
        const SizedBox(height: 4),
        Text(
          'Bluetooth audio routing and saved device profiles.',
          style: TextStyle(fontSize: 13.5, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        HeroCard(
          icon: Icons.graphic_eq_rounded,
          accent: const Color(0xFF67C2FF),
          title: 'Audio Hub',
          subtitle: 'Bluetooth codecs, devices and saved audio profiles.',
        ),
        const SizedBox(height: 14),
        const SectionLabel('Audio engines'),
        const SizedBox(height: 8),
        SurfaceCard(
          child: Column(
            children: <Widget>[
              _AudioHubSectionRow(
                icon: Icons.headphones_rounded,
                accent: const Color(0xFF8B9CFF),
                title: 'Bluetooth audio',
                subtitle: 'Device connection, codecs and saved profiles',
                onTap: () => widget.onOpen(DuchampScreen.bluetoothAudio),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const SectionLabel('Quick status'),
        const SizedBox(height: 8),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.savings_rounded,
                    size: 18,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Bypass charging tile',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    'Control hub · Charging',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.sports_esports_rounded,
                    size: 18,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Per-app game tuning',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    'Control hub · Performance',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AudioHubSectionRow extends StatelessWidget {
  const _AudioHubSectionRow({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
