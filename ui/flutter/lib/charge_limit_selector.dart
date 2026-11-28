import 'package:flutter/material.dart';

/// Charging-limit selector: 80/85/90/95 only, same preview-then-commit
/// contract as the bypass threshold slider (no command stream while dragging).
class DuchampChargeLimitSelector extends StatefulWidget {
  const DuchampChargeLimitSelector({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.accent,
    this.onPreview,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final Color accent;
  final ValueChanged<int>? onPreview;

  @override
  State<DuchampChargeLimitSelector> createState() =>
      _ChargeLimitSelectorState();
}

class _ChargeLimitSelectorState extends State<DuchampChargeLimitSelector> {
  static const values = <int>[80, 85, 90, 95];
  int? _preview;

  @override
  Widget build(BuildContext context) {
    final index = (_preview ?? values.indexOf(widget.value)).clamp(0, 3);
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: widget.accent,
            inactiveTrackColor: widget.accent.withValues(alpha: 0.13),
            disabledActiveTrackColor: widget.accent,
            disabledInactiveTrackColor: widget.accent.withValues(alpha: 0.13),
            disabledThumbColor: widget.accent,
            activeTickMarkColor: colors.surface,
            inactiveTickMarkColor: widget.accent.withValues(alpha: 0.38),
            thumbColor: widget.accent,
            overlayColor: widget.accent.withValues(alpha: 0.10),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            value: index.toDouble(),
            max: 3,
            divisions: 3,
            semanticFormatterCallback: (value) =>
                '${values[value.round()]} percent',
            onChanged: widget.enabled
                ? (value) {
                    final next = value.round();
                    if (_preview != next) {
                      setState(() => _preview = next);
                      widget.onPreview?.call(values[next]);
                    }
                  }
                : null,
            onChangeEnd: widget.enabled
                ? (value) {
                    widget.onChanged(values[value.round()]);
                    setState(() => _preview = null);
                  }
                : null,
          ),
        ),
        Row(
          children: <Widget>[
            for (final value in values)
              Expanded(
                child: Text(
                  '$value%',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: values[index] == value
                        ? widget.accent
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
