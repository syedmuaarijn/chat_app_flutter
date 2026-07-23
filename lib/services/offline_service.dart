import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class OfflineService {
  static final OfflineService _instance = OfflineService._internal();
  factory OfflineService() => _instance;
  OfflineService._internal();

  bool _isOnline = true;
  final Connectivity _connectivity = Connectivity();

  // Cache the last check result so we don't re-query the platform channel on
  // every call. The cache expires after 2 seconds, which is fine for UX
  // purposes and prevents the multi-minute Android platform-channel block.
  DateTime? _lastCheckTime;
  static const _cacheDuration = Duration(seconds: 2);

  bool get isOnline => _isOnline;

  Future<void> initialize() async {
    await _checkConnectivity();
    _connectivity.onConnectivityChanged.listen((_) {
      _invalidateCache();
      _checkConnectivity();
    });
  }

  void _invalidateCache() {
    _lastCheckTime = null;
  }

  Future<void> _checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _isOnline = !result.contains(ConnectivityResult.none) ||
          result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.mobile) ||
          result.contains(ConnectivityResult.ethernet);
      // More robust: just check there's at least one non-none result
      _isOnline = result.any((r) => r != ConnectivityResult.none);
      _lastCheckTime = DateTime.now();
      debugPrint('Network status: ${_isOnline ? "Online" : "Offline"}');
    } catch (e) {
      debugPrint('Error checking connectivity: $e');
      _isOnline = true; // Assume online if check fails
      _lastCheckTime = DateTime.now();
    }
  }

  /// Returns the cached online status without hitting the platform channel.
  /// Use this when you need an instant, non-blocking answer (e.g. in build
  /// methods or before showing cached data). May be slightly stale (≤2s).
  bool get isOnlineCached => _isOnline;

  /// Checks connectivity, using the cached result if it was obtained within
  /// [_cacheDuration]. This prevents the multi-minute Android platform-channel
  /// block that occurs when calling checkConnectivity() on every invocation.
  Future<bool> hasConnection() async {
    final now = DateTime.now();
    if (_lastCheckTime != null &&
        now.difference(_lastCheckTime!) < _cacheDuration) {
      return _isOnline;
    }
    await _checkConnectivity();
    return _isOnline;
  }
}
