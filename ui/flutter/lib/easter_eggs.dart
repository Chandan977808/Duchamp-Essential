part of 'main.dart';

// NEESCHAL's tiny break room. The daemon stays on duty; the jokes do not.
//     [ CPU ]  [ GPU ]
//         \\    /
//       ( snack )       No frequency tables were harmed making this sandwich.
class DuchampVersionSecret extends StatefulWidget {
  const DuchampVersionSecret({required this.version, super.key});
  final String version;
  @override
  State<DuchampVersionSecret> createState() => _DuchampVersionSecretState();
}

class _DuchampVersionSecretState extends State<DuchampVersionSecret> {
  int _taps = 0;
  Timer? _reset;
  bool _open = false;

  void _tap() {
    if (_open) return;
    DuchampHaptics.confirm();
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _taps = 0);
    });
    setState(() => _taps++);
    if (_taps != 4) return;
    setState(() => _taps = 0);
    _reset?.cancel();
    _open = true;
    unawaited(
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Close secret room',
        barrierColor: Colors.black.withValues(alpha: 0.5),
        transitionDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : DuchampInteractionSettings.motionDuration(340),
        pageBuilder: (_, _, _) => const DuchampSecretRoom(),
        transitionBuilder: (_, Animation<double> animation, _, Widget child) =>
            FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutBack,
                    reverseCurve: Curves.easeInCubic,
                  ),
                ),
                child: child,
              ),
            ),
      ).whenComplete(() => _open = false),
    );
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Duchamp Essential version ${widget.version}',
    hint: 'Tap four times to discover a secret',
    child: PressScale(
      enableHaptics: false,
      onTap: _tap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: AnimatedScale(
          scale: 1 + _taps * 0.025,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : DuchampInteractionSettings.motionDuration(160),
          curve: Curves.easeOutCubic,
          child: StatusPill(
            label: widget.version,
            accent: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    ),
  );
}

class DuchampSecretRoom extends StatefulWidget {
  const DuchampSecretRoom({super.key});
  @override
  State<DuchampSecretRoom> createState() => _DuchampSecretRoomState();
}

class _DuchampSecretRoomState extends State<DuchampSecretRoom>
    with TickerProviderStateMixin {
  static const List<String> _jokes = <String>[
    'Four taps. Zero secret overclock.',
    'I asked the GPU for a sandwich. It rendered the bread.',
    'My governor says I need a nap. Finally, sensible scheduling.',
    'Touch grass. OEM adaptive mode.',
    'Zero DEX. Full dad jokes.',
    'More cores, fewer chores. The laundry still won’t compile.',
    'SaanOS hid this here. The compiler pretended not to notice.',
    'The daemon works in the background. I tell jokes in the foreground.',
    'Your phone has eight cores. Somehow, you’re still doing all the work.',
    'Battery at 1%: suddenly every charger becomes your best friend.',
    'I cleared my cache. Still thinking about that embarrassing thing from 2017.',
    'My screen time report just asked if I live here.',
    'I opened one notification. Three hours later, I know how otters hold hands.',
    'Airplane mode is on. Still waiting for the phone to take off.',
    'My phone has a dark mode. My sleep schedule has only chaos mode.',
    'I told my phone to chill. It opened the weather app.',
    '128 tabs open. All of them are apparently essential.',
    'My charger and I have a connection. Sometimes it’s complicated.',
    'You found the Easter egg. The chicken is still compiling.',
    'SaanOS promised fewer bugs. Nobody said anything about these jokes.',
  ];
  late final AnimationController _burst;
  late final AnimationController _hold;
  bool _holding = false;
  bool _ready = false;
  bool _playing = false;
  int _joke = 0;
  bool _closing = false;
  bool _introduced = false;

  @override
  void initState() {
    super.initState();
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _hold =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 900),
        )..addStatusListener((AnimationStatus status) {
          if (status == AnimationStatus.completed && _holding && mounted) {
            DuchampHaptics.confirm();
            setState(() => _ready = true);
          }
        });
    DuchampNestedBackController.attach(this, _close);
  }

  bool get _animate =>
      !MediaQuery.disableAnimationsOf(context) &&
      DuchampInteractionSettings.motionDuration(1100) != Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_introduced) {
      _introduced = true;
      if (_animate) _burst.forward();
    } else if (!_animate) {
      _burst.stop();
      _burst.value = 1;
    }
  }

  bool _close() {
    if (_playing) {
      setState(() => _playing = false);
      return true;
    }
    if (_closing) return true;
    _closing = true;
    Navigator.of(context).pop();
    return true;
  }

  void _beginHold() {
    setState(() {
      _holding = true;
      _ready = false;
    });
    _hold.forward(from: 0);
  }

  void _endHold({bool cancelled = false}) {
    final bool launch = _ready && !cancelled;
    _hold.stop();
    _hold.value = 0;
    setState(() {
      _holding = false;
      _ready = false;
      _playing = launch;
    });
    if (launch) DuchampHaptics.confirm();
  }

  void _next() {
    DuchampHaptics.confirm();
    setState(() => _joke = (_joke + 1) % _jokes.length);
    if (_animate) {
      _burst.forward(from: 0);
    }
  }

  @override
  void dispose() {
    DuchampNestedBackController.detach(this);
    _burst.dispose();
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Widget joke = Text(
      _jokes[_joke],
      key: ValueKey<int>(_joke),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.45,
        color: colors.onSurface,
      ),
    );
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(22),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: (MediaQuery.sizeOf(context).height - 100).clamp(
            0,
            double.infinity,
          ),
        ),
        child: SurfaceCard(
          padding: const EdgeInsets.all(20),
          child: _playing
              ? AuroraDrift(onBack: () => setState(() => _playing = false))
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'The secret room',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close secret room',
                            onPressed: () {
                              DuchampHaptics.confirm();
                              _close();
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$duchampReleaseCodename · a little less serious.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 132,
                        child: Stack(
                          alignment: Alignment.center,
                          children: <Widget>[
                            Positioned.fill(
                              child: IgnorePointer(
                                child: RepaintBoundary(
                                  child: AnimatedBuilder(
                                    animation: _burst,
                                    builder: (_, _) => CustomPaint(
                                      painter: _DuchampSparkles(
                                        _burst.value,
                                        colors.primary,
                                        colors.secondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            AnimatedBuilder(
                              animation: Listenable.merge(<Listenable>[
                                _burst,
                                _hold,
                              ]),
                              child: Semantics(
                                button: true,
                                label: 'Duchamp Essential logo',
                                hint:
                                    'Tap for a joke. Hold, then release to play Aurora Drift.',
                                child: GestureDetector(
                                  key: const ValueKey<String>('secret-logo'),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _next,
                                  onLongPressStart: (_) => _beginHold(),
                                  onLongPressEnd: (_) => _endHold(),
                                  onLongPressCancel: () {
                                    if (_holding) _endHold(cancelled: true);
                                  },
                                  child: _DuchampAppEmblem(
                                    size: 72,
                                    color: colors.primary,
                                  ),
                                ),
                              ),
                              builder: (_, Widget? child) {
                                final double pulse = math.sin(
                                  _burst.value * math.pi,
                                );
                                return Transform.translate(
                                  offset: Offset(0, -pulse * 7),
                                  child: Transform.rotate(
                                    angle: !_animate
                                        ? 0
                                        : _holding
                                        ? _hold.value *
                                              _hold.value *
                                              math.pi *
                                              8
                                        : math.sin(_burst.value * math.pi * 6) *
                                              (1 - _burst.value) *
                                              0.10,
                                    child: Transform.scale(
                                      scale: 1 + pulse * 0.10,
                                      child: child,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _ready
                            ? 'Release to drift.'
                            : _holding
                            ? 'Winding up…'
                            : 'Tap for a laugh. Hold for an adventure.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const SizedBox(height: 12),
                      if (!_animate)
                        joke
                      else
                        AnimatedSize(
                          duration: DuchampInteractionSettings.motionDuration(
                            280,
                          ),
                          curve: Curves.easeOutCubic,
                          child: AnimatedSwitcher(
                            duration: _animate
                                ? DuchampInteractionSettings.motionDuration(260)
                                : Duration.zero,
                            transitionBuilder:
                                (Widget child, Animation<double> animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position:
                                            Tween<Offset>(
                                              begin: const Offset(0, 0.07),
                                              end: Offset.zero,
                                            ).animate(
                                              CurvedAnimation(
                                                parent: animation,
                                                curve: Curves.easeOutCubic,
                                              ),
                                            ),
                                        child: child,
                                      ),
                                    ),
                            child: joke,
                          ),
                        ),
                      const SizedBox(height: 22),
                      FilledButton.tonalIcon(
                        onPressed: _next,
                        icon: const Icon(Icons.auto_awesome_rounded),
                        label: const Text('One more joke'),
                      ),
                      TextButton(
                        onPressed: () {
                          DuchampHaptics.confirm();
                          setState(() => _playing = true);
                        },
                        child: const Text('Play Aurora Drift'),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Made with a straight face by SaanOS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Just for fun. No device settings changed.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _DuchampSparkles extends CustomPainter {
  const _DuchampSparkles(this.progress, this.primary, this.secondary);
  final double progress;
  final Color primary;
  final Color secondary;
  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final double radius =
        size.shortestSide *
        (0.23 + 0.33 * Curves.easeOutCubic.transform(progress));
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = primary.withValues(alpha: 0.2 * (1 - progress));
    canvas.drawCircle(size.center(Offset.zero), radius * 0.9, ring);
    for (int i = 0; i < 20; i++) {
      final double angle =
          i * math.pi * 2 / 20 + progress * (i.isEven ? 0.15 : -0.15);
      final Offset direction = Offset.fromDirection(angle, radius);
      final Offset point =
          size.center(Offset.zero) +
          direction +
          Offset(0, progress * progress * 18);
      final Paint paint = Paint()
        ..color = (i.isEven ? primary : secondary).withValues(
          alpha: 1 - progress,
        );
      canvas.save();
      canvas.translate(point.dx, point.dy);
      canvas.rotate(angle + progress * 2);
      if (i % 3 == 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-1.5, -3, 3, 6),
            const Radius.circular(1),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, 2.5 * (1 - progress * 0.5), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_DuchampSparkles old) =>
      old.progress != progress ||
      old.primary != primary ||
      old.secondary != secondary;
}
