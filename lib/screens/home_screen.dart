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
    backgroundColor: RoamColors.offwhite,
    appBar: _RoamAppBar(onJoin: () => _comingSoon('Sign up')),
    // A plain Column (not a lazy ListView/CustomScrollView) so every section
    // is always built, not just whatever is within the current viewport.
    body: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Hero(onFindTrips: () => _comingSoon('Trip search')),
          const SizedBox(height: 56),
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
  const _Hero({required this.onFindTrips});

  final VoidCallback onFindTrips;

  static const _heroImage = AssetImage('assets/images/hero-nightlife.jpg');

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: Image(image: _heroImage, fit: BoxFit.cover),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.4, 1],
                    colors: [
                      RoamColors.navy.withValues(alpha: 0.45),
                      RoamColors.navy.withValues(alpha: 0.2),
                      RoamColors.navy.withValues(alpha: 0.72),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 84, 24, 230),
              child: Column(
                children: [
                  Text(
                    'Find Your Travel',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.breeSerif(
                      color: Colors.white,
                      fontSize: 34,
                      height: 1.15,
                      shadows: const [
                        Shadow(color: Colors.black38, blurRadius: 24, offset: Offset(0, 4)),
                      ],
                    ),
                  ),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [RoamColors.mint, RoamColors.gold, RoamColors.coral],
                    ).createShader(bounds),
                    child: Text(
                      'Companion.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.breeSerif(
                        color: Colors.white,
                        fontSize: 34,
                        height: 1.15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Roam Together matches solo travelers with verified, '
                    'like-minded companions — so you never have to explore alone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14.5, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  const _TrustBar(),
                ],
              ),
            ),
          ],
        ),
      ),
      Positioned(
        left: 20,
        right: 20,
        bottom: -70,
        child: _SearchCard(onFindTrips: onFindTrips),
      ),
    ],
  );
}

class _TrustBar extends StatelessWidget {
  const _TrustBar();

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 22,
    runSpacing: 10,
    children: const [
      _TrustItem(icon: Icons.verified_user, bold: 'ID-Verified', rest: 'travelers only'),
      _TrustItem(icon: Icons.star, bold: '4.8/5', rest: 'average trip rating'),
      _TrustItem(icon: Icons.public, bold: '120+', rest: 'countries', prefix: 'Travelers in '),
    ],
  );
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({
    required this.icon,
    required this.bold,
    required this.rest,
    this.prefix = '',
  });

  final IconData icon;
  final String bold;
  final String rest;
  final String prefix;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: RoamColors.gold),
      const SizedBox(width: 7),
      Text.rich(
        TextSpan(
          style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w500),
          children: [
            if (prefix.isNotEmpty) TextSpan(text: prefix),
            TextSpan(text: bold, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            TextSpan(text: ' $rest'),
          ],
        ),
      ),
    ],
  );
}

class _SearchCard extends StatefulWidget {
  const _SearchCard({required this.onFindTrips});

  final VoidCallback onFindTrips;

  @override
  State<_SearchCard> createState() => _SearchCardState();
}

class _SearchCardState extends State<_SearchCard> {
  final _whereController = TextEditingController();
  DateTimeRange? _dates;
  String? _style;

  static const _styleOptions = {
    'solo': 'Solo, independent',
    'chill': 'Chill & beachy',
    'adventure': 'Adventure & outdoors',
    'luxury': 'Luxury & bougie',
    'budget': 'Budget & backpacking',
    'food': 'Food & culture focused',
  };

  @override
  void dispose() {
    _whereController.dispose();
    super.dispose();
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _dates = picked);
  }

  String get _dateLabel {
    if (_dates == null) return 'mm/dd/yyyy – mm/dd/yyyy';
    String fmt(DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
    return '${fmt(_dates!.start)} – ${fmt(_dates!.end)}';
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 32, offset: const Offset(0, 16)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchField(
          icon: Icons.location_on_outlined,
          label: 'WHERE TO?',
          child: TextField(
            controller: _whereController,
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'Country / City',
              hintStyle: TextStyle(color: Color(0xffb0bec9)),
            ),
          ),
        ),
        const Divider(height: 22),
        _SearchField(
          icon: Icons.calendar_today_outlined,
          label: 'DATES',
          child: InkWell(
            onTap: _pickDates,
            child: Text(
              _dateLabel,
              style: TextStyle(
                fontSize: 13.5,
                color: _dates == null ? const Color(0xffb0bec9) : RoamColors.text,
              ),
            ),
          ),
        ),
        const Divider(height: 22),
        _SearchField(
          icon: Icons.tune,
          label: 'TRAVEL STYLE',
          child: DropdownButton<String>(
            value: _style,
            isExpanded: true,
            isDense: true,
            underline: const SizedBox.shrink(),
            hint: const Text('Select style', style: TextStyle(color: Color(0xffb0bec9), fontSize: 13.5)),
            items: [
              for (final entry in _styleOptions.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value, style: const TextStyle(fontSize: 13.5))),
            ],
            onChanged: (value) => setState(() => _style = value),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [RoamColors.mint, RoamColors.coral]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: widget.onFindTrips,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Find Trips',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.icon, required this.label, required this.child});

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Icon(icon, size: 13, color: RoamColors.mint),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: Color(0xff7a8fa6),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      child,
    ],
  );
}

class _RoamAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _RoamAppBar({required this.onJoin});

  final VoidCallback onJoin;

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) => AppBar(
    backgroundColor: RoamColors.navyTint,
    elevation: 0,
    automaticallyImplyLeading: false,
    titleSpacing: 20,
    title: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [RoamColors.mint, RoamColors.gold],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.explore, color: RoamColors.navy, size: 20),
    ),
    actions: [
      Padding(
        padding: const EdgeInsets.only(right: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [RoamColors.mint, RoamColors.coral]),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: onJoin,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text(
                  'Join Now',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ),
        ),
      ),
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
