import 'dart:async';
import 'package:almaworks/config.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:weather/weather.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Internal model holding current + next-slot weather for one location
// ─────────────────────────────────────────────────────────────────────────────
class _SiteWeather {
  final String location;
  final Weather? current;
  final Weather? next;   // first 3-hour forecast slot
  final String? error;

  const _SiteWeather({
    required this.location,
    this.current,
    this.next,
    this.error,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// WeatherWidget
//   • projectLocation  – pass for Project Summary (single site)
//   • projectLocations – pass for Dashboard (all project sites)
// ─────────────────────────────────────────────────────────────────────────────
class WeatherWidget extends StatefulWidget {
  /// Single project location (Project Summary Screen).
  final String? projectLocation;

  /// All project locations (Dashboard Screen).
  final List<String>? projectLocations;

  const WeatherWidget({
    super.key,
    this.projectLocation,
    this.projectLocations,
  });

  @override
  State<WeatherWidget> createState() => _WeatherWidgetState();
}

class _WeatherWidgetState extends State<WeatherWidget> {
  late final WeatherFactory _wf;
  late final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _refreshTimer;

  bool _isOffline = false;
  bool _isUnstable = false;
  bool _isLoading = true;
  bool _isExpanded = false;
  List<_SiteWeather> _data = [];
  DateTime? _lastFetched;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _wf = WeatherFactory(Config.weatherApiKey, language: Language.ENGLISH);
    _connectivity = Connectivity();
    _listenToConnectivity();
    _fetchAll();
    _startAutoRefresh();
  }

  @override
  void didUpdateWidget(WeatherWidget old) {
    super.didUpdateWidget(old);
    // Re-fetch if the list of locations changed (e.g. new project added on dashboard)
    if (old.projectLocation != widget.projectLocation ||
        old.projectLocations?.join() != widget.projectLocations?.join()) {
      _fetchAll();
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ── Connectivity ────────────────────────────────────────────────────────────
  void _listenToConnectivity() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final offline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      if (!mounted) return;
      if (offline != _isOffline) {
        setState(() => _isOffline = offline);
        if (!offline) _fetchAll();
      }
    });
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (mounted && !_isOffline) _fetchAll();
    });
  }

  // ── Data fetching ────────────────────────────────────────────────────────────
  List<String> get _locations {
    if (widget.projectLocation != null && widget.projectLocation!.trim().isNotEmpty) {
      return [widget.projectLocation!.trim()];
    }
    return (widget.projectLocations ?? [])
        .where((l) => l.trim().isNotEmpty)
        .map((l) => l.trim())
        .toSet()                    // deduplicate
        .toList();
  }

  Future<void> _fetchAll() async {
    if (!mounted) return;

    // ── Check connectivity ────────────────────────────────────────────────────
    final conn = await _connectivity.checkConnectivity();
    final offline = conn.isEmpty || conn.every((r) => r == ConnectivityResult.none);
    if (offline) {
      if (mounted) setState(() { _isOffline = true; _isLoading = false; });
      return;
    }

    if (mounted) {
      setState(() {
        _isOffline  = false;
        _isUnstable = false;
        _isLoading  = true;
      });
    }

    final locations = _locations;
    if (locations.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    bool anyUnstable = false;
    final results = <_SiteWeather>[];

    for (final loc in locations) {
      try {
        final current = await _wf
            .currentWeatherByCityName(loc)
            .timeout(const Duration(seconds: 12));

        final forecast = await _wf
            .fiveDayForecastByCityName(loc)
            .timeout(const Duration(seconds: 12));

        // forecast[0] is the nearest upcoming 3-hour slot
        final next = forecast.isNotEmpty ? forecast[0] : null;

        results.add(_SiteWeather(location: loc, current: current, next: next));
      } on TimeoutException {
        anyUnstable = true;
        results.add(_SiteWeather(
          location: loc,
          error: 'timeout',
        ));
      } catch (e) {
        // Try to detect a network-related error vs. a city-not-found error
        final msg = e.toString().toLowerCase();
        final isNetwork = msg.contains('socket') ||
            msg.contains('connection') ||
            msg.contains('network') ||
            msg.contains('handshake');
        if (isNetwork) anyUnstable = true;
        results.add(_SiteWeather(
          location: loc,
          error: isNetwork ? 'timeout' : 'notfound',
        ));
      }
    }

    if (mounted) {
      setState(() {
        _data       = results;
        _isLoading  = false;
        _isUnstable = anyUnstable;
        _lastFetched = DateTime.now();
      });
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  IconData _icon(String? main) {
    switch ((main ?? '').toLowerCase()) {
      case 'clear':
        return Icons.wb_sunny;
      case 'clouds':
        return Icons.cloud;
      case 'rain':
        return Icons.water_drop;
      case 'drizzle':
        return Icons.grain;
      case 'thunderstorm':
        return Icons.thunderstorm;
      case 'snow':
        return Icons.ac_unit;
      case 'mist':
      case 'smoke':
      case 'haze':
      case 'dust':
      case 'fog':
      case 'sand':
      case 'ash':
      case 'squall':
      case 'tornado':
        return Icons.blur_on;
      default:
        return Icons.wb_cloudy;
    }
  }

  Color _color(String? main) {
    switch ((main ?? '').toLowerCase()) {
      case 'clear':
        return Colors.orange;
      case 'clouds':
        return Colors.blueGrey;
      case 'rain':
      case 'drizzle':
        return Colors.blue;
      case 'thunderstorm':
        return Colors.deepPurple;
      case 'snow':
        return Colors.lightBlue;
      default:
        return Colors.teal;
    }
  }

  String _tempStr(Temperature? t) =>
      t?.celsius != null ? '${t!.celsius!.round()}°C' : '--';

  String _humidity(Weather? w) =>
      w?.humidity != null ? '${w!.humidity}%' : '--';

  String _fetchedAgo() {
    if (_lastFetched == null) return '';
    final diff = DateTime.now().difference(_lastFetched!);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes == 1) return '1 min ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
    return '${diff.inHours}h ago';
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final isMobile = sw < 600;

    return Card(
      elevation: 2,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isMobile),
            const SizedBox(height: 10),
            Expanded(child: _buildBody(isMobile)),
            if (_lastFetched != null && !_isLoading && !_isOffline)
              _buildFooterBar(isMobile),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Row(
      children: [
        Icon(Icons.wb_sunny, color: Colors.orange, size: isMobile ? 20 : 24),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weather Report',
                style: TextStyle(
                  fontSize: isMobile ? 16 : 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (widget.projectLocation != null)
                Text(
                  widget.projectLocation!,
                  style: TextStyle(
                    fontSize: isMobile ? 11 : 12,
                    color: Colors.grey[600],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        // Refresh button
        IconButton(
          icon: _isLoading
              ? SizedBox(
                  width: isMobile ? 16 : 18,
                  height: isMobile ? 16 : 18,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.refresh, size: isMobile ? 18 : 20),
          onPressed: _isLoading ? null : _fetchAll,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          tooltip: 'Refresh weather',
        ),
      ],
    );
  }

  Widget _buildBody(bool isMobile) {
    // ── Offline ────────────────────────────────────────────────────────────
    if (_isOffline) {
      return _buildStatusMessage(
        icon: Icons.wifi_off,
        color: Colors.grey[700]!,
        title: 'No Internet Connection',
        subtitle:
            'Weather data is unavailable while offline.\nWe\'ll refresh automatically once you reconnect.',
        isMobile: isMobile,
      );
    }

    // ── Loading ────────────────────────────────────────────────────────────
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              'Fetching weather data…',
              style: TextStyle(color: Colors.grey[600], fontSize: isMobile ? 12 : 13),
            ),
          ],
        ),
      );
    }

    // ── No locations configured ─────────────────────────────────────────────
    if (_locations.isEmpty) {
      return _buildStatusMessage(
        icon: Icons.location_off,
        color: Colors.grey,
        title: 'No Locations Set',
        subtitle: 'Add a location to your project to see weather data here.',
        isMobile: isMobile,
      );
    }

    // ── Unstable + nothing loaded ───────────────────────────────────────────
    if (_isUnstable && _data.every((d) => d.error != null)) {
      return _buildStatusMessage(
        icon: Icons.signal_wifi_statusbar_connected_no_internet_4,
        color: Colors.orange,
        title: 'Unstable Connection',
        subtitle:
            'Weather data could not load due to a weak or slow network.\nPlease check your connection and tap refresh.',
        isMobile: isMobile,
        action: TextButton.icon(
          onPressed: _fetchAll,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('Retry'),
        ),
      );
    }

    // ── Data available ──────────────────────────────────────────────────────
    return _buildDataContent(isMobile);
  }

  Widget _buildDataContent(bool isMobile) {
    final isMulti = _data.length > 1;
    final visible = (isMulti && !_isExpanded && _data.length > 3)
        ? _data.sublist(0, 3)
        : _data;

    return Column(
      children: [
        // Optional unstable banner when some (not all) failed
        if (_isUnstable && _data.any((d) => d.error == null))
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Some locations could not be reached due to a slow connection.',
                    style: TextStyle(
                      color: Colors.orange[800],
                      fontSize: isMobile ? 10 : 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

        Expanded(
          child: ListView.separated(
            itemCount: visible.length,
            separatorBuilder: (_, _) => SizedBox(height: isMobile ? 8 : 10),
            itemBuilder: (_, i) => isMulti
                ? _buildMultiCard(visible[i], isMobile)
                : _buildSingleCard(visible[i], isMobile),
          ),
        ),

        if (isMulti && _data.length > 3)
          TextButton(
            onPressed: () => setState(() => _isExpanded = !_isExpanded),
            child: Text(
              _isExpanded
                  ? 'Show Less'
                  : 'View All Sites (${_data.length})',
            ),
          ),
      ],
    );
  }

  // ── Single-location detailed card (Project Summary) ────────────────────────
  Widget _buildSingleCard(_SiteWeather sw, bool isMobile) {
    if (sw.error != null) return _buildErrorTile(sw, isMobile);

    final cur = sw.current!;
    final nxt = sw.next;
    final main = cur.weatherMain;
    final ic   = _icon(main);
    final cl   = _color(main);

    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cl.withValues(alpha: 0.08), cl.withValues(alpha: 0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cl.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current weather row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: isMobile ? 48 : 56,
                height: isMobile ? 48 : 56,
                decoration: BoxDecoration(
                  color: cl.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(ic, color: cl, size: isMobile ? 26 : 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Now  •  ${_tempStr(cur.temperature)}',
                      style: TextStyle(
                        fontSize: isMobile ? 18 : 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _capitalise(cur.weatherDescription ?? main ?? ''),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: isMobile ? 12 : 13,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _chip(Icons.water_drop, _humidity(cur), Colors.blue),
                  const SizedBox(height: 4),
                  if (cur.windSpeed != null)
                    _chip(Icons.air, '${cur.windSpeed!.round()} m/s', Colors.teal),
                ],
              ),
            ],
          ),

          // Forecast divider
          if (nxt != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
            Row(
              children: [
                Icon(Icons.schedule, size: 13, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  'Next ~3 h',
                  style: TextStyle(
                    fontSize: isMobile ? 11 : 12,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Icon(_icon(nxt.weatherMain),
                    color: _color(nxt.weatherMain), size: isMobile ? 14 : 16),
                const SizedBox(width: 6),
                Text(
                  _capitalise(nxt.weatherDescription ?? nxt.weatherMain ?? ''),
                  style: TextStyle(fontSize: isMobile ? 12 : 13),
                ),
                const SizedBox(width: 8),
                Text(
                  _tempStr(nxt.temperature),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: isMobile ? 13 : 14,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Multi-location compact card (Dashboard) ────────────────────────────────
  Widget _buildMultiCard(_SiteWeather sw, bool isMobile) {
    if (sw.error != null) return _buildErrorTile(sw, isMobile);

    final cur  = sw.current!;
    final nxt  = sw.next;
    final main = cur.weatherMain;
    final ic   = _icon(main);
    final cl   = _color(main);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 12,
        vertical: isMobile ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: isMobile ? 36 : 40,
            height: isMobile ? 36 : 40,
            decoration: BoxDecoration(
              color: cl.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(ic, color: cl, size: isMobile ? 18 : 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sw.location,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: isMobile ? 12 : 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _capitalise(cur.weatherDescription ?? main ?? ''),
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: isMobile ? 10 : 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Current temp + humidity
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _tempStr(cur.temperature),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: isMobile ? 14 : 16,
                ),
              ),
              Text(
                _humidity(cur),
                style: TextStyle(
                  color: Colors.blue[400],
                  fontSize: isMobile ? 10 : 11,
                ),
              ),
            ],
          ),

          // Next slot
          if (nxt != null) ...[
            Container(
              width: 1,
              height: 32,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: Colors.grey.withValues(alpha: 0.2),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '~3h',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: isMobile ? 9 : 10,
                  ),
                ),
                Icon(_icon(nxt.weatherMain),
                    color: _color(nxt.weatherMain), size: isMobile ? 14 : 16),
                Text(
                  _tempStr(nxt.temperature),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: isMobile ? 10 : 11,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorTile(_SiteWeather sw, bool isMobile) {
    final isTimeout = sw.error == 'timeout';
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 10 : 12, vertical: isMobile ? 8 : 10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(
            isTimeout ? Icons.signal_wifi_bad : Icons.location_off,
            color: Colors.grey[500],
            size: isMobile ? 18 : 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sw.location,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: isMobile ? 12 : 13,
                    color: Colors.grey[700],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isTimeout
                      ? 'Connection too slow to load'
                      : 'Location not found',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: isMobile ? 10 : 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusMessage({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool isMobile,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: isMobile ? 42 : 52, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: isMobile ? 14 : 16,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: isMobile ? 11 : 12,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 10), action],
          ],
        ),
      ),
    );
  }

  Widget _buildFooterBar(bool isMobile) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 10, vertical: isMobile ? 5 : 6),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.access_time, color: Colors.blue[400], size: isMobile ? 12 : 13),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Updated ${_fetchedAgo()}  •  auto-refresh every 30 min',
              style: TextStyle(
                color: Colors.blue[700],
                fontSize: isMobile ? 9 : 10,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}