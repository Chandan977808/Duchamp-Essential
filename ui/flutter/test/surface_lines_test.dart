import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:duchamp_essential_ui/main.dart';
import 'package:duchamp_essential_ui/surface_lines.dart';

ColorScheme schemeFor(Brightness brightness) =>
    ColorScheme.fromSeed(
      seedColor: const Color(0xFF087AC7),
      brightness: brightness,
    ).copyWith(
      surface: brightness == Brightness.dark
          ? Colors.black
          : const Color(0xFFFCFDFF),
      outline: brightness == Brightness.dark
          ? const Color(0xFF1C1C1C)
          : const Color(0xFFD2DCE7),
      onSurfaceVariant: brightness == Brightness.dark
          ? const Color(0xFFAEB8C5)
          : const Color(0xFF566477),
    );

void main() {
  for (final brightness in Brightness.values) {
    final colors = schemeFor(brightness);
    test(
      'boundaries remain visible without translucent strokes: $brightness',
      () {
        for (final stroke in [
          DuchampSurfaceLines.border(colors),
          DuchampSurfaceLines.inset(colors),
          DuchampSurfaceLines.divider(colors),
        ]) {
          expect(stroke.a, 1);
          final luminance = stroke.computeLuminance();
          final surfaceLuminance = colors.surface.computeLuminance();
          final contrast = luminance > surfaceLuminance
              ? (luminance + 0.05) / (surfaceLuminance + 0.05)
              : (surfaceLuminance + 0.05) / (luminance + 0.05);
          // Decorative boundaries, not a text/accessibility contrast claim.
          expect(contrast, greaterThan(1.2));
        }
      },
    );

    for (final cardStyle in [0, 1, 3]) {
      testWidgets(
        'shared card outline survives glass style $cardStyle: $brightness',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(colorScheme: colors),
              home: Scaffold(
                body: DuchampAppearanceScope(
                  config: DuchampAppearanceConfig(
                    themePreference: DuchampThemePreference.system,
                    backgroundStyle: DuchampBackgroundStyle.system,
                    backgroundBlur: 0,
                    customPath: '',
                    cardStyle: cardStyle,
                  ),
                  child: const SurfaceCard(child: Text('Glass card')),
                ),
              ),
            ),
          );
          final container = tester.widget<Container>(
            find
                .descendant(
                  of: find.byType(SurfaceCard),
                  matching: find.byType(Container),
                )
                .first,
          );
          final decoration = container.decoration! as BoxDecoration;
          expect(
            (decoration.border! as Border).top.color,
            DuchampSurfaceLines.border(colors),
          );
          expect(decoration.borderRadius, BorderRadius.circular(22));
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final hubs in [false, true]) {
      testWidgets(
        'dashboard mini-cards and separators share the stroke palette: hubs=$hubs $brightness',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(colorScheme: colors),
              home: Scaffold(
                body: hubs
                    ? HubsScreen(onOpen: (_) {})
                    : HomeScreen(
                        onOpen: (_) {},
                        onHubs: () {},
                        onSupport: () {},
                      ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final metric = find.byWidgetPredicate(
            (widget) =>
                widget.runtimeType.toString() ==
                (hubs ? '_HubMetric' : '_HomeHeroMetric'),
          );
          expect(metric, findsNWidgets(3));
          for (final element in metric.evaluate()) {
            final container = tester.widget<Container>(
              find
                  .descendant(
                    of: find.byWidget(element.widget),
                    matching: find.byType(Container),
                  )
                  .first,
            );
            final border =
                (container.decoration! as BoxDecoration).border! as Border;
            expect(border.top.color, DuchampSurfaceLines.inset(colors));
            expect(border.top.width, 0.85);
          }
          final dividers = tester.widgetList<Divider>(find.byType(Divider));
          expect(dividers, isNotEmpty);
          for (final divider in dividers) {
            expect(divider.color, DuchampSurfaceLines.divider(colors));
            expect(divider.thickness, 0.8);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
