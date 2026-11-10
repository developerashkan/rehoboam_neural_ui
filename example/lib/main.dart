import 'package:flutter/material.dart';
import 'package:rehoboam_neural_ui/rehoboam_neural_ui.dart';

import 'demos.dart';

void main() => runApp(const GalleryApp());

/// The Rehoboam Neural UI gallery: every widget on one adaptive dashboard.
class GalleryApp extends StatefulWidget {
  /// Creates the gallery.
  const GalleryApp({
    super.key,
    this.initialMode = ThemeMode.dark,
    this.initialRtl = false,
    this.today,
    this.simulate = true,
  });

  /// Light or dark at start.
  final ThemeMode initialMode;

  /// Start right-to-left.
  final bool initialRtl;

  /// Fixed "today" (screenshots); defaults to now.
  final DateTime? today;

  /// Run the simulated live data (mic level, typing transcript...).
  final bool simulate;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

/// Builds the gallery theme.
ThemeData galleryTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF00D5E0),
    brightness: b,
    dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
  ).copyWith(
    primary: dark ? const Color(0xFF3BE8F0) : const Color(0xFF00838F),
    tertiary: dark ? const Color(0xFFB28CFF) : const Color(0xFF6D3FD6),
    surface: dark ? const Color(0xFF0B1020) : const Color(0xFFF7F9FD),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    extensions: const [NeuralThemeData(glowIntensity: 1.1)],
  );
}

class _GalleryAppState extends State<GalleryApp> {
  late ThemeMode _mode = widget.initialMode;
  late bool _rtl = widget.initialRtl;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Rehoboam Neural UI',
      theme: galleryTheme(Brightness.light),
      darkTheme: galleryTheme(Brightness.dark),
      themeMode: _mode,
      builder: (context, child) => Directionality(
        textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: GalleryHome(
        dark: _mode == ThemeMode.dark,
        rtl: _rtl,
        today: widget.today,
        simulate: widget.simulate,
        onToggleTheme: () => setState(() =>
            _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark),
        onToggleRtl: () => setState(() => _rtl = !_rtl),
      ),
    );
  }
}

/// The dashboard page.
class GalleryHome extends StatelessWidget {
  /// Creates the page.
  const GalleryHome({
    super.key,
    required this.dark,
    required this.rtl,
    required this.onToggleTheme,
    required this.onToggleRtl,
    this.today,
    this.simulate = true,
  });

  /// Dark mode on.
  final bool dark;

  /// RTL on.
  final bool rtl;

  /// Theme switch.
  final VoidCallback onToggleTheme;

  /// Direction switch.
  final VoidCallback onToggleRtl;

  /// Fixed date for the heatmap.
  final DateTime? today;

  /// Live simulation on.
  final bool simulate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [
                    Color(0xFF04060C),
                    Color(0xFF0A1022),
                    Color(0xFF120B24)
                  ]
                : const [
                    Color(0xFFF6F9FF),
                    Color(0xFFEAF1FB),
                    Color(0xFFF3EEFF)
                  ],
          ),
        ),
        child: NeuralNetworkBackground(
          density: 0.55,
          linkDistance: 130,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                final columns = w >= 1180 ? 3 : (w >= 760 ? 2 : 1);
                final pad = w >= 760 ? 28.0 : 16.0;
                return CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(pad, pad * 0.75, pad, 12),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          children: [
                            const NeuralOrb(
                              size: 40,
                              state: NeuralOrbState.thinking,
                              semanticsLabel: 'Logo',
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Rehoboam Neural UI',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  Text(
                                    'Sci-fi widgets for Flutter',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton.filledTonal(
                              tooltip: rtl ? 'Left to right' : 'Right to left',
                              onPressed: onToggleRtl,
                              icon: Icon(rtl
                                  ? Icons.format_textdirection_l_to_r
                                  : Icons.format_textdirection_r_to_l),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: dark ? 'Light mode' : 'Dark mode',
                              onPressed: onToggleTheme,
                              icon: Icon(dark
                                  ? Icons.light_mode_rounded
                                  : Icons.dark_mode_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(pad, 4, pad, pad),
                      sliver: SliverToBoxAdapter(
                        child: DemoGrid(
                          columns: columns,
                          today: today,
                          simulate: simulate,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
