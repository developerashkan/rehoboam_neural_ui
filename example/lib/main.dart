import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rehoboam_neural_ui/rehoboam_neural_ui.dart';

import 'assistant.dart';
import 'demos.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Optional: compile the liquid shaders before the first frame.
  unawaited(NeuralShaders.precache());
  runApp(const GalleryApp());
}

/// The sections of the gallery.
enum GalleryTab {
  /// AI chat with tools and generated UI.
  assistant,

  /// The Rehoboam HUD driven by voice and AI.
  hud,

  /// Every widget.
  widgets,
}

/// The Rehoboam Neural UI gallery.
class GalleryApp extends StatefulWidget {
  /// Creates the gallery.
  const GalleryApp({
    super.key,
    this.initialMode = ThemeMode.dark,
    this.initialRtl = false,
    this.initialTab = GalleryTab.assistant,
    this.initialDesign = NeuralDesign.liquid,
    this.today,
    this.simulate = true,
  });

  /// Light or dark at start.
  final ThemeMode initialMode;

  /// Start right-to-left.
  final bool initialRtl;

  /// First section.
  final GalleryTab initialTab;

  /// Liquid or neon.
  final NeuralDesign initialDesign;

  /// Fixed "today" (screenshots); defaults to now.
  final DateTime? today;

  /// Run the simulated live data (mic level, typing transcript...).
  final bool simulate;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

/// Builds the gallery theme for [design].
ThemeData galleryTheme(Brightness b,
    [NeuralDesign design = NeuralDesign.liquid]) {
  final dark = b == Brightness.dark;
  final liquid = design == NeuralDesign.liquid;
  final scheme = liquid
      ? ColorScheme.fromSeed(
          seedColor: const Color(0xFF6A5BFF),
          brightness: b,
          dynamicSchemeVariant: DynamicSchemeVariant.neutral,
        ).copyWith(
          primary: dark ? const Color(0xFFB9B4FF) : const Color(0xFF4B43D9),
          tertiary: dark ? const Color(0xFFFF9BD2) : const Color(0xFFC2307E),
          surface: dark ? const Color(0xFF0A0A0D) : const Color(0xFFF5F5F7),
        )
      : ColorScheme.fromSeed(
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
    extensions: [
      NeuralThemeData(design: design, glowIntensity: liquid ? null : 1.1),
    ],
  );
}

class _GalleryAppState extends State<GalleryApp> {
  late ThemeMode _mode = widget.initialMode;
  late bool _rtl = widget.initialRtl;
  late NeuralDesign _design = widget.initialDesign;
  late GalleryTab _tab = widget.initialTab;
  final AssistantHub _hub = AssistantHub();

  @override
  void dispose() {
    _hub.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Rehoboam Neural UI',
      theme: galleryTheme(Brightness.light, _design),
      darkTheme: galleryTheme(Brightness.dark, _design),
      themeMode: _mode,
      builder: (context, child) => Directionality(
        textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: GalleryShell(
        hub: _hub,
        tab: _tab,
        dark: _mode == ThemeMode.dark,
        rtl: _rtl,
        design: _design,
        today: widget.today,
        simulate: widget.simulate,
        onTab: (t) => setState(() => _tab = t),
        onToggleTheme: () => setState(() =>
            _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark),
        onToggleRtl: () => setState(() => _rtl = !_rtl),
        onToggleDesign: () => setState(() => _design =
            _design == NeuralDesign.liquid
                ? NeuralDesign.neon
                : NeuralDesign.liquid),
      ),
    );
  }
}

/// Adaptive navigation: a bar on phones, a rail on wide screens.
class GalleryShell extends StatelessWidget {
  /// Creates the shell.
  const GalleryShell({
    super.key,
    required this.hub,
    required this.tab,
    required this.dark,
    required this.rtl,
    required this.design,
    required this.onTab,
    required this.onToggleTheme,
    required this.onToggleRtl,
    required this.onToggleDesign,
    this.today,
    this.simulate = true,
  });

  /// Shared AI state.
  final AssistantHub hub;

  /// Current section.
  final GalleryTab tab;

  /// Dark mode on.
  final bool dark;

  /// RTL on.
  final bool rtl;

  /// Current design.
  final NeuralDesign design;

  /// Section change.
  final ValueChanged<GalleryTab> onTab;

  /// Theme switch.
  final VoidCallback onToggleTheme;

  /// Direction switch.
  final VoidCallback onToggleRtl;

  /// Design switch.
  final VoidCallback onToggleDesign;

  /// Fixed date for the heatmap.
  final DateTime? today;

  /// Live simulation on.
  final bool simulate;

  static const _destinations = [
    (Icons.blur_on_rounded, 'Assistant'),
    (Icons.public_rounded, 'HUD'),
    (Icons.widgets_outlined, 'Widgets'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final actions = [
      IconButton(
        tooltip:
            design == NeuralDesign.liquid ? 'Neon design' : 'Liquid design',
        onPressed: onToggleDesign,
        icon: Icon(design == NeuralDesign.liquid
            ? Icons.auto_awesome_outlined
            : Icons.water_drop_outlined),
      ),
      IconButton(
        tooltip: rtl ? 'Left to right' : 'Right to left',
        onPressed: onToggleRtl,
        icon: Icon(rtl
            ? Icons.format_textdirection_l_to_r
            : Icons.format_textdirection_r_to_l),
      ),
      IconButton(
        tooltip: dark ? 'Light mode' : 'Dark mode',
        onPressed: onToggleTheme,
        icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      ),
    ];

    final page = switch (tab) {
      GalleryTab.assistant => AssistantPage(hub: hub, actions: actions),
      GalleryTab.hud => HudPage(hub: hub, actions: actions),
      GalleryTab.widgets => WidgetsPage(
          dark: dark,
          today: today,
          simulate: simulate,
          actions: actions,
        ),
    };

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: scheme.surface,
              selectedIndex: tab.index,
              onDestinationSelected: (i) => onTab(GalleryTab.values[i]),
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: NeuralLiquidOrb(
                    size: 44,
                    state: NeuralOrbState.thinking,
                    tile: true,
                    semanticsLabel: 'Logo'),
              ),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                      icon: Icon(d.$1), label: Text(d.$2)),
              ],
            ),
            VerticalDivider(
                width: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
            Expanded(child: page),
          ],
        ),
      );
    }
    return Scaffold(
      body: page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab.index,
        onDestinationSelected: (i) => onTab(GalleryTab.values[i]),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.$1), label: d.$2),
        ],
      ),
    );
  }
}

/// A slim page header.
class PageHeader extends StatelessWidget {
  /// Creates a header.
  const PageHeader(
      {super.key, required this.title, this.subtitle, this.actions = const []});

  /// Title.
  final String title;

  /// Subtitle.
  final String? subtitle;

  /// Trailing actions.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// The AI chat.
class AssistantPage extends StatelessWidget {
  /// Creates the page.
  const AssistantPage({super.key, required this.hub, this.actions = const []});

  /// Shared AI state.
  final AssistantHub hub;

  /// Header actions.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: hub.agent,
        builder: (context, _) => Column(
          children: [
            PageHeader(
              title: 'Assistant',
              subtitle:
                  '${hub.settings.provider.label} · ${hub.agent.model.provider}',
              actions: [
                IconButton(
                  tooltip: 'Model settings',
                  onPressed: () => showDemoSettings(context, hub),
                  icon: const Icon(Icons.tune_rounded),
                ),
                IconButton(
                  tooltip: 'New chat',
                  onPressed: hub.agent.clear,
                  icon: const Icon(Icons.add_comment_outlined),
                ),
                ...actions,
              ],
            ),
            Expanded(
              child: NeuralChatView(
                agent: hub.agent,
                title: 'Rehoboam',
                suggestions: const [
                  'Weather in Lisbon',
                  'Show me Tokyo on the globe',
                  'Server dashboard',
                  'What can you do?',
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Rehoboam HUD, driven by the same agent: speak or type, and the
/// model flies the globe with its tools.
class HudPage extends StatelessWidget {
  /// Creates the page.
  const HudPage({super.key, required this.hub, this.actions = const []});

  /// Shared AI state.
  final AssistantHub hub;

  /// Header actions.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final agent = hub.agent;
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: agent,
      builder: (context, _) => NeuralEdgeGlow(
        active: agent.isBusy,
        level: agent.level.value,
        borderRadius: 0,
        width: 36,
        child: SafeArea(
          child: Column(
            children: [
              PageHeader(
                title: 'Rehoboam HUD',
                subtitle: 'Voice and AI drive the ring and the globe',
                actions: actions,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => Center(
                    child: RehoboamHud(
                      controller: hub.hud,
                      size: (c.biggest.shortestSide * 0.95).clamp(220.0, 620.0),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  height: 76,
                  child: ValueListenableBuilder<String>(
                    valueListenable: agent.streamingText,
                    builder: (context, live, _) {
                      final last = agent.messages.lastWhere(
                        (m) =>
                            m.role == NeuralRole.assistant && m.text.isNotEmpty,
                        orElse: () => NeuralMessage(
                            role: NeuralRole.assistant, parts: const []),
                      );
                      final text = live.isNotEmpty
                          ? live
                          : agent.phase == NeuralAgentPhase.listening
                              ? agent.liveTranscript.value
                              : last.text.replaceAll('**', '');
                      return ValueListenableBuilder<int?>(
                        valueListenable: agent.spokenWord,
                        builder: (context, word, _) => WordByWordTranscript(
                          text: text,
                          isFinal: agent.phase == NeuralAgentPhase.idle,
                          highlightIndex: word,
                          maxLines: 2,
                          textStyle: t.titleMedium?.copyWith(height: 1.3),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final p in const [
                      'Show me Tokyo',
                      'Where is Mount Everest?',
                      'Back to the ring'
                    ])
                      ActionChip(
                        label: Text(p),
                        onPressed: () => p.startsWith('Back')
                            ? hub.hud.showRing(label: 'Ask me anything')
                            : agent.send(p),
                      ),
                    ValueListenableBuilder<double>(
                      valueListenable: agent.level,
                      builder: (context, level, _) => NeuralLiquidOrb(
                        size: 56,
                        tile: true,
                        state: agent.orbState,
                        level: level,
                        semanticsLabel:
                            agent.phase == NeuralAgentPhase.listening
                                ? 'Stop listening'
                                : 'Talk',
                        onTap: () => agent.phase == NeuralAgentPhase.listening
                            ? agent.stop()
                            : agent.listen(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every widget on one adaptive dashboard.
class WidgetsPage extends StatelessWidget {
  /// Creates the page.
  const WidgetsPage({
    super.key,
    required this.dark,
    this.today,
    this.simulate = true,
    this.actions = const [],
  });

  /// Dark mode on.
  final bool dark;

  /// Fixed date for the heatmap.
  final DateTime? today;

  /// Live simulation on.
  final bool simulate;

  /// Header actions.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final liquid = NeuralPalette.of(context).isLiquid;
    final backdrop = liquid
        ? (dark
            ? const [Color(0xFF07070A), Color(0xFF101017), Color(0xFF0B0B10)]
            : const [Color(0xFFF7F7F9), Color(0xFFEDEDF2), Color(0xFFF5F2FA)])
        : (dark
            ? const [Color(0xFF04060C), Color(0xFF0A1022), Color(0xFF120B24)]
            : const [Color(0xFFF6F9FF), Color(0xFFEAF1FB), Color(0xFFF3EEFF)]);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: backdrop,
        ),
      ),
      child: NeuralNetworkBackground(
        density: liquid ? 0.3 : 0.55,
        linkDistance: 130,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final columns = w >= 1180 ? 3 : (w >= 720 ? 2 : 1);
              final pad = w >= 720 ? 24.0 : 16.0;
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: PageHeader(
                      title: 'Rehoboam Neural UI',
                      subtitle: 'Pure, liquid widgets for Flutter',
                      actions: actions,
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(pad, 8, pad, pad),
                    sliver: SliverToBoxAdapter(
                      child: DemoGrid(
                          columns: columns, today: today, simulate: simulate),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
