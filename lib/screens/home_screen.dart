import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/roam_api.dart';
import '../services/supabase_roam_api.dart';
import '../theme.dart';

/// Mobile home screen, adapted from web/home.html's marketing page into a
/// scrollable native layout. Keeps the live Supabase-backed travel-styles
/// fetch that main.dart previously rendered on its own.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.api});

  final RoamApi? api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final RoamApi _api;
  late Future<List<String>> _styles;

  static const styleLabels = {
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

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: RoamColors.navy,
      title: Text(
        'Roam Together',
        style: GoogleFonts.breeSerif(color: Colors.white, fontSize: 20),
      ),
    ),
    // A plain Column (not a lazy ListView/CustomScrollView) so every section
    // is always built, not just whatever is within the current viewport.
    body: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Hero(onGetStarted: () => _comingSoon('Sign up')),
          const _FeatureGrid(),
          _TravelStylesSection(
            future: _styles,
            labels: styleLabels,
            onRetry: () => setState(() {
              _styles = _loadStyles();
            }),
          ),
          const _HowItWorks(),
          const _SafetySection(),
          _MembershipCta(onJoin: () => _comingSoon('Roam+ membership')),
          const _Footer(),
        ],
      ),
    ),
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [RoamColors.navy, RoamColors.navyTint],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FIND YOUR TRAVEL COMPANION',
          style: TextStyle(
            color: RoamColors.mint,
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Roam further,\ntogether.',
          style: GoogleFonts.breeSerif(
            color: Colors.white,
            fontSize: 36,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Match with verified travelers who share your style, '
          'your dates, and your sense of adventure.',
          style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: RoamColors.mint,
                  foregroundColor: RoamColors.navy,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onGetStarted,
                child: const Text(
                  'Get Started',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _TrustStrip(),
      ],
    ),
  );
}

class _TrustStrip extends StatelessWidget {
  const _TrustStrip();

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 18,
    runSpacing: 10,
    children: const [
      _TrustBadge(icon: Icons.verified_user, label: 'Verified profiles'),
      _TrustBadge(icon: Icons.lock_outline, label: 'Private messaging'),
      _TrustBadge(icon: Icons.public, label: 'Global community'),
    ],
  );
}

class _TrustBadge extends StatelessWidget {
  const _TrustBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: RoamColors.mint),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
    ],
  );
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  static const features = [
    (
      Icons.favorite_border,
      'Style-based matching',
      'Tell us how you like to travel and we surface companions who match.',
      RoamColors.mint,
    ),
    (
      Icons.shield_outlined,
      'Safety first',
      'ID checks and in-app reporting keep the community accountable.',
      RoamColors.coral,
    ),
    (
      Icons.chat_bubble_outline,
      'Chat before you commit',
      'Message a match and get comfortable before planning anything.',
      RoamColors.gold,
    ),
    (
      Icons.explore_outlined,
      'Trips from everywhere',
      'Browse open trips the community has already posted.',
      RoamColors.emerald,
    ),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 32, 20, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Why Roam Together', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.92,
          children: [
            for (final (icon, title, desc, color) in features)
              _FeatureCard(icon: icon, title: title, desc: desc, color: color),
          ],
        ),
      ],
    ),
  );
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String desc;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
        ),
        const SizedBox(height: 6),
        Text(
          desc,
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, height: 1.35),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

class _TravelStylesSection extends StatelessWidget {
  const _TravelStylesSection({
    required this.future,
    required this.labels,
    required this.onRetry,
  });

  final Future<List<String>> future;
  final Map<String, String> labels;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 32, 20, 8),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: RoamColors.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LIVE FROM ROAM TOGETHER',
            style: TextStyle(
              color: RoamColors.mint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Explore travel styles',
            style: GoogleFonts.breeSerif(color: Colors.white, fontSize: 20),
          ),
          const SizedBox(height: 14),
          FutureBuilder<List<String>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: RoamColors.mint,
                      semanticsLabel: 'Loading travel styles',
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'We could not load travel styles. Please try again.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: RoamColors.mint,
                        foregroundColor: RoamColors.navy,
                      ),
                      onPressed: onRetry,
                      child: const Text('Try again'),
                    ),
                  ],
                );
              }
              final styles = snapshot.data!;
              if (styles.isEmpty) {
                return const Text(
                  'New travel styles are coming soon.',
                  style: TextStyle(color: Colors.white70),
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final style in styles)
                    Chip(
                      label: Text(labels[style] ?? style),
                      backgroundColor: RoamColors.navyTint,
                      labelStyle: const TextStyle(color: Colors.white),
                      side: BorderSide(color: RoamColors.mint.withValues(alpha: 0.4)),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const steps = [
    ('Create your profile', 'Share your travel style, dates, and what you\'re looking for.'),
    ('Find your match', 'Browse trips and companions who fit what you need.'),
    ('Travel together', 'Message, plan, and set off with someone you trust.'),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 32, 20, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How it works', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: RoamColors.emerald,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        steps[i].$1,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        steps[i].$2,
                        style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _SafetySection extends StatelessWidget {
  const _SafetySection();

  static const points = [
    (Icons.badge_outlined, 'ID verification on every profile'),
    (Icons.report_outlined, 'One-tap reporting and blocking'),
    (Icons.support_agent, 'Support is reachable in-app'),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: RoamColors.coral.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RoamColors.coral.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield, color: RoamColors.coral, size: 20),
              const SizedBox(width: 8),
              Text('Safety you can trust', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 14),
          for (final (icon, label) in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: RoamColors.coral),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label, style: const TextStyle(fontSize: 13.5, height: 1.3)),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _MembershipCta extends StatelessWidget {
  const _MembershipCta({required this.onJoin});

  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [RoamColors.gold, RoamColors.coral],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Roam+ membership',
            style: GoogleFonts.breeSerif(color: Colors.white, fontSize: 20),
          ),
          const SizedBox(height: 8),
          const Text(
            'Unlock unlimited matches, priority visibility, and advanced trip filters.',
            style: TextStyle(color: Colors.white, height: 1.4, fontSize: 13),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: onJoin,
            child: const Text('Learn more'),
          ),
        ],
      ),
    ),
  );
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 32, 20, 40),
    child: Column(
      children: [
        Text(
          'Roam Together',
          style: GoogleFonts.breeSerif(fontSize: 16, color: RoamColors.text),
        ),
        const SizedBox(height: 6),
        Text(
          'Travel further, together.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    ),
  );
}
