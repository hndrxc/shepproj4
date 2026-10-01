import 'package:flutter/material.dart';

import 'services/roam_api.dart';
import 'services/supabase_roam_api.dart';

void main() => runApp(const MainApp());

class MainApp extends StatelessWidget {
  const MainApp({super.key, this.api});

  final RoamApi? api;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Roam Together',
    theme: ThemeData(colorSchemeSeed: const Color(0xff2e8b57)),
    home: TravelStylesPage(api: api),
  );
}

/// Small server-backed entry screen for the frontend team to build upon.
class TravelStylesPage extends StatefulWidget {
  const TravelStylesPage({super.key, this.api});

  final RoamApi? api;

  @override
  State<TravelStylesPage> createState() => _TravelStylesPageState();
}

class _TravelStylesPageState extends State<TravelStylesPage> {
  late final RoamApi _api;
  late Future<List<String>> _styles;

  static const labels = {
    'solo': 'Solo & independent',
    'chill': 'Beach & relaxation',
    'adventure': 'Adventure & outdoors',
    'luxury': 'Luxury travel',
    'budget': 'Budget & backpacking',
    'food': 'Food & culture',
  };

  @override
  void initState() {
    super.initState();
    _api =
        widget.api ??
        (const bool.fromEnvironment('USE_LOCAL_BACKEND')
            ? RoamApi()
            : SupabaseRoamApi());
    _styles = _loadStyles();
  }

  Future<List<String>> _loadStyles() async {
    final result = await _api.styles();
    final items = result['items'];
    if (items is! List || items.any((item) => item is! String)) {
      throw const RoamApiException(
        'Travel styles are temporarily unavailable.',
      );
    }
    return items.cast<String>();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Roam Together')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: FutureBuilder<List<String>>(
            future: _styles,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const CircularProgressIndicator(
                  semanticsLabel: 'Loading travel styles',
                );
              }
              if (snapshot.hasError) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'We could not load travel styles. Please try again.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() {
                        _styles = _loadStyles();
                      }),
                      child: const Text('Try again'),
                    ),
                  ],
                );
              }
              final styles = snapshot.data!;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Explore travel styles',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  if (styles.isEmpty)
                    const Text('New travel styles are coming soon.')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final style in styles)
                          Chip(label: Text(labels[style] ?? style)),
                      ],
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
