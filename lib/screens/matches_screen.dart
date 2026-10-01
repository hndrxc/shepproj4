import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/roam_api.dart';
import '../style_labels.dart';
import '../theme.dart';

/// Results of public.find_travel_matches: other verified travelers with a
/// trip to the same city/country whose dates overlap this trip's dates.
/// The backend already orders same-travel-style matches first.
class MatchesScreen extends StatefulWidget {
  const MatchesScreen({
    super.key,
    required this.api,
    required this.tripId,
    required this.city,
    required this.country,
  });

  final RoamApi api;
  final String tripId;
  final String city;
  final String country;

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  final _items = <Map<String, dynamic>>[];
  final _connecting = <String>{};
  final _connected = <String>{};
  Object? _error;
  int? _nextOffset;
  var _loading = true;
  var _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.matches(widget.tripId);
      final items = (result['items'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _nextOffset = result['next_offset'] as int?;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final offset = _nextOffset;
    if (offset == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.api.matches(widget.tripId, offset: offset);
      final items = (result['items'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _nextOffset = result['next_offset'] as int?;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error is RoamApiException ? error.message : 'Could not load more matches.')),
      );
    }
  }

  Future<void> _connect(Map<String, dynamic> match) async {
    final ownerId = match['owner_id'] as String;
    setState(() => _connecting.add(ownerId));
    try {
      await widget.api.connect(ownerId);
      if (!mounted) return;
      setState(() {
        _connecting.remove(ownerId);
        _connected.add(ownerId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection request sent to ${match['owner_name']}.')),
      );
    } on RoamApiException catch (error) {
      if (!mounted) return;
      setState(() => _connecting.remove(ownerId));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: RoamColors.offwhite,
    appBar: AppBar(
      backgroundColor: RoamColors.navyTint,
      foregroundColor: Colors.white,
      title: Text(
        '${widget.city}, ${widget.country}',
        style: GoogleFonts.breeSerif(color: Colors.white, fontSize: 18),
      ),
    ),
    body: _buildBody(context),
  );

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: RoamColors.emerald));
    }
    if (_error != null) {
      return _ErrorState(error: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.travel_explore, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No companions found for these dates and destination yet. '
                'Check back soon, or try a wider date range.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: RoamColors.emerald,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length + 1,
        itemBuilder: (context, index) {
          if (index == _items.length) {
            if (_nextOffset == null) return const SizedBox(height: 24);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _loadingMore
                    ? const CircularProgressIndicator(color: RoamColors.emerald)
                    : OutlinedButton(onPressed: _loadMore, child: const Text('Load more')),
              ),
            );
          }
          final match = _items[index];
          final ownerId = match['owner_id'] as String;
          return _MatchCard(
            match: match,
            connecting: _connecting.contains(ownerId),
            connected: _connected.contains(ownerId),
            onConnect: () => _connect(match),
          );
        },
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.connecting,
    required this.connected,
    required this.onConnect,
  });

  final Map<String, dynamic> match;
  final bool connecting;
  final bool connected;
  final VoidCallback onConnect;

  String _formatDate(String isoDate) {
    final d = DateTime.parse(isoDate);
    return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final sameStyle = match['same_style'] == true;
    final verified = match['verified'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: sameStyle ? RoamColors.mint.withValues(alpha: 0.5) : const Color(0xffe8eef4),
          width: sameStyle ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  match['owner_name'] as String? ?? 'Traveler',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                ),
              ),
              if (verified) const Icon(Icons.verified, color: RoamColors.emerald, size: 18),
              if (sameStyle) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: RoamColors.mint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Same style',
                    style: TextStyle(color: RoamColors.emerald, fontWeight: FontWeight.w700, fontSize: 10.5),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(match['title'] as String? ?? '', style: const TextStyle(fontSize: 13.5, color: RoamColors.text)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 14, color: Color(0xff7a8fa6)),
              const SizedBox(width: 4),
              Text('${match['city']}, ${match['country']}', style: const TextStyle(fontSize: 12.5, color: Color(0xff7a8fa6))),
              const SizedBox(width: 14),
              const Icon(Icons.calendar_today_outlined, size: 13, color: Color(0xff7a8fa6)),
              const SizedBox(width: 4),
              Text(
                '${_formatDate(match['start'] as String)} – ${_formatDate(match['end'] as String)}',
                style: const TextStyle(fontSize: 12.5, color: Color(0xff7a8fa6)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            styleLabels[match['style']] ?? match['style'] as String? ?? '',
            style: const TextStyle(fontSize: 12.5, color: RoamColors.gold, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: connected ? RoamColors.emerald : RoamColors.navy,
                side: BorderSide(color: connected ? RoamColors.emerald : const Color(0xffcfd8e3)),
              ),
              onPressed: connecting || connected ? null : onConnect,
              child: connecting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(connected ? 'Request sent' : 'Connect'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final apiError = error;
    final isVerificationError = apiError is RoamApiException && apiError.statusCode == 403;
    final message = apiError is RoamApiException
        ? apiError.message
        : 'We could not load your matches. Please try again.';
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isVerificationError ? Icons.verified_outlined : Icons.error_outline,
              size: 48,
              color: isVerificationError ? RoamColors.gold : Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: RoamColors.text)),
            if (isVerificationError) ...[
              const SizedBox(height: 8),
              const Text(
                'Matching opens up once your profile has been ID-verified.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: RoamColors.emerald),
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
