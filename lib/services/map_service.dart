import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart' as fmtc;

class PhilippinesMapService {
  static const String _philippinesStore = 'philippines_base';
  static const String _userCacheStore = 'user_cache';
  static const String _emergencyStore = 'emergency_cache';

  // Philippines bounds and major cities
  static const LatLng philippinesCenter = LatLng(12.8797, 121.7740);
  static const LatLng butuan = LatLng(8.9472, 125.5406);
  static const LatLng agusanDelNorte = LatLng(8.9344, 125.5264);

  static final LatLngBounds philippinesBounds = LatLngBounds(
    const LatLng(4.2158064, 114.0952145), // Southwest
    const LatLng(21.3210946, 127.6050855), // Northeast
  );

  static const List<CriticalLocation> criticalLocations = [
    CriticalLocation('Butuan City', LatLng(8.9472, 125.5406)),
    CriticalLocation('Baguio', LatLng(16.4023, 120.5960)),
    CriticalLocation('Cabanatuan', LatLng(15.4855, 120.9647)),
    CriticalLocation('Navotas', LatLng(14.6564, 120.9496)),
    CriticalLocation('Bayawan', LatLng(9.3599, 122.8014)),
    CriticalLocation('Agusan del Norte', LatLng(8.9344, 125.5264)),
  ];

  static PhilippinesMapService? _instance;
  static PhilippinesMapService get instance {
    _instance ??= PhilippinesMapService._();
    return _instance!;
  }

  PhilippinesMapService._();

  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _isOnline = false;
  bool _isInitialized = false;

  // Tile providers
  late TileLayer _onlineTileLayer;
  late TileLayer _offlineTileLayer;

  bool get isOnline => _isOnline;
  bool get isInitialized => _isInitialized;

  /// Initialize the map service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('🚀 Starting PhilippinesMapService initialization...');

      await FMTCObjectBoxBackend().initialise();
      debugPrint('✅ FMTC ObjectBox backend initialized');

      await _setupTileStores();
      debugPrint('✅ Tile stores setup completed');

      // Check connectivity first
      final connectivityResults = await Connectivity().checkConnectivity();
      _isOnline = connectivityResults.any(
        (result) =>
            result == ConnectivityResult.mobile ||
            result == ConnectivityResult.wifi ||
            result == ConnectivityResult.ethernet,
      );
      debugPrint(
        '🌐 Initial connectivity: ${_isOnline ? "online" : "offline"}',
      );

      await _loadBundledTiles();
      debugPrint('✅ Bundled tiles loading completed');

      _setupTileLayers();
      debugPrint('✅ Tile layers setup completed');

      // Add comprehensive debugging
      await debugCacheStatus();
      final offlineReady = await testOfflineCapability();
      debugPrint(
        '🔍 Offline capability: ${offlineReady ? "✅ READY" : "❌ NOT READY"}',
      );

      _startConnectivityMonitoring();
      debugPrint('✅ Connectivity monitoring started');

      _isInitialized = true;
      debugPrint('🎉 PhilippinesMapService initialized successfully');
    } catch (e) {
      debugPrint('💥 Failed to initialize PhilippinesMapService: $e');
      _isInitialized = false;

      try {
        _setupFallbackMode();
        debugPrint('🔄 Fallback mode activated');
      } catch (fallbackError) {
        debugPrint('💥 Fallback mode also failed: $fallbackError');
        rethrow;
      }
    }
  }

  void _setupFallbackMode() {
    // Setup basic online-only tile layer as fallback
    _onlineTileLayer = TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.resqlink.app',
      maxZoom: 19,
    );

    _offlineTileLayer = _onlineTileLayer;

    _startConnectivityMonitoring();
    _isInitialized = true;
  }

  /// Setup tile stores for different use cases
  Future<void> _setupTileStores() async {
    final stores = [_philippinesStore, _userCacheStore, _emergencyStore];

    for (final storeName in stores) {
      try {
        final store = FMTCStore(storeName);
        if (!await store.manage.ready) {
          await store.manage.create();
          debugPrint('Created tile store: $storeName');
        }
      } catch (e) {
        debugPrint('Error setting up store $storeName: $e');
      }
    }
  }

  Future<void> _loadBundledTiles() async {
    try {
      final store = FMTCStore(_philippinesStore);
      final stats = await store.stats.all;

      if (stats.length == 0) {
        debugPrint('📦 No base tiles found');

        if (_isOnline) {
          // Start download in background - don't await!
          _downloadPhilippinesBaseTiles().catchError((e) {
            debugPrint('Background download failed: $e');
          });
          debugPrint('🔄 Started background tile download');
        } else {
          debugPrint('📱 Offline - will use online tiles when available');
        }
      } else {
        debugPrint('✅ Base tiles ready (${stats.length} tiles)');
      }
    } catch (e) {
      debugPrint('⚠️ Tile loading error: $e - continuing with online mode');
      // Don't rethrow - let the app continue
    }
  }

  /// Setup tile layers for different scenarios
  void _setupTileLayers() {
    const urlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    // Online tile layer with user cache
    _onlineTileLayer = TileLayer(
      urlTemplate: urlTemplate,
      userAgentPackageName: 'com.resqlink.app',
      maxZoom: 19,
      tileProvider: fmtc.FMTCTileProvider(
        stores: {_userCacheStore: fmtc.BrowseStoreStrategy.read},
        loadingStrategy: fmtc.BrowseLoadingStrategy.cacheFirst,
      ),
    );

    // Offline base layer - FIXED: Check BOTH user cache AND Philippines base tiles
    // This ensures downloaded tiles AND bundled tiles work offline
    // CRITICAL: Use cacheOnly strategy to prevent network requests in offline mode
    _offlineTileLayer = TileLayer(
      urlTemplate: urlTemplate,
      userAgentPackageName: 'com.resqlink.app',
      maxZoom: 19,
      tileProvider: fmtc.FMTCTileProvider(
        stores: {
          _userCacheStore: fmtc
              .BrowseStoreStrategy
              .read, // User-downloaded tiles (highest priority)
          _philippinesStore:
              fmtc.BrowseStoreStrategy.read, // Bundled base tiles (fallback)
        },
        loadingStrategy: fmtc
            .BrowseLoadingStrategy
            .cacheOnly, // Never try network in offline mode
      ),
    );
  }

  Future<void> debugCacheStatus() async {
    try {
      debugPrint('=== CACHE DEBUG INFO ===');

      final stores = [_philippinesStore, _userCacheStore, _emergencyStore];

      for (final storeName in stores) {
        final store = FMTCStore(storeName);
        if (await store.manage.ready) {
          final stats = await store.stats.all;
          final size = await store.stats.size;
          debugPrint('Store: $storeName');
          debugPrint('  Tiles: ${stats.length}');
          debugPrint('  Size: ${(size / (1024 * 1024)).toStringAsFixed(2)} MB');

          // Display cache statistics
          if (stats.length > 0) {
            debugPrint('  Cache Stats:');
            debugPrint('    Hits: ${stats.hits}');
            debugPrint('    Misses: ${stats.misses}');
            debugPrint('    Length: ${stats.length}');
            debugPrint('    Size: ${stats.size.toStringAsFixed(2)} bytes');
          }
        } else {
          debugPrint('Store $storeName not ready');
        }
      }

      debugPrint('========================');
    } catch (e) {
      debugPrint('Debug cache error: $e');
    }
  }

  Future<void> _downloadPhilippinesBaseTiles() async {
    if (!_isOnline) {
      debugPrint('Cannot download base tiles - offline');
      return;
    }

    try {
      final store = FMTCStore(_philippinesStore);
      final stats = await store.stats.all;

      // Only download if store is empty
      if (stats.length == 0) {
        debugPrint('Downloading Philippines base tiles...');

        // Define Philippines bounds
        final bounds = LatLngBounds(
          const LatLng(4.2158064, 114.0952145), // Southwest
          const LatLng(21.3210946, 127.6050855), // Northeast
        );

        final region = fmtc.RectangleRegion(bounds);
        final downloadable = region.toDownloadable(
          minZoom: 0,
          maxZoom: 8, // Lower zoom for base coverage
          options: TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.resqlink.app',
          ),
        );

        final download = store.download.startForeground(
          region: downloadable,
          parallelThreads: 2,
          maxBufferLength: 50,
          skipExistingTiles: true,
          skipSeaTiles: true,
        );

        // Create a completer to properly handle async completion
        final completer = Completer<void>();
        StreamSubscription? subscription;

        // Listen to progress with proper error handling
        subscription = download.downloadProgress.listen(
          (progress) {
            debugPrint(
              'Philippines base download: ${progress.percentageProgress.toStringAsFixed(1)}%',
            );
          },
          onDone: () {
            debugPrint('Philippines base tiles downloaded successfully');
            subscription?.cancel();
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
          onError: (error) {
            debugPrint('Error downloading Philippines base tiles: $error');
            subscription?.cancel();
            if (!completer.isCompleted) {
              completer.completeError(error);
            }
          },
        );

        // Add timeout to prevent hanging
        Timer(Duration(minutes: 10), () {
          if (!completer.isCompleted) {
            subscription?.cancel();
            completer.completeError(
              TimeoutException('Download timeout', Duration(minutes: 10)),
            );
          }
        });

        // Wait for download to complete
        await completer.future;
      } else {
        debugPrint(
          'Philippines base tiles already available (${stats.length} tiles)',
        );
      }
    } catch (e) {
      debugPrint('Error downloading Philippines base tiles: $e');
      // Don't rethrow - allow app to continue with online-only mode
    }
  }

  Future<bool> testOfflineCapability() async {
    try {
      debugPrint('🧪 Testing offline capability...');

      // Check if Philippines store has tiles
      final store = FMTCStore(_philippinesStore);
      if (!await store.manage.ready) {
        debugPrint('❌ Philippines store not ready');
        return false;
      }

      final stats = await store.stats.all;
      final size = await store.stats.size;

      debugPrint('📊 Store stats:');
      debugPrint('  - Tiles: ${stats.length}');
      debugPrint('  - Size: ${(size / (1024 * 1024)).toStringAsFixed(2)} MB');

      if (stats.length == 0) {
        debugPrint('❌ No tiles in Philippines store');

        if (_isOnline) {
          debugPrint('🔄 Attempting to download base tiles...');
          await _downloadPhilippinesBaseTiles();

          // Check again after download attempt
          final newStats = await store.stats.all;
          if (newStats.length == 0) {
            debugPrint('❌ Download attempt failed');
            return false;
          } else {
            debugPrint('✅ Base tiles downloaded successfully');
            return true;
          }
        } else {
          return false;
        }
      }

      // Test tile layer creation without storing unused variable
      try {
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          tileProvider: fmtc.FMTCTileProvider(
            stores: {_philippinesStore: fmtc.BrowseStoreStrategy.read},
            loadingStrategy: fmtc.BrowseLoadingStrategy.cacheOnly,
          ),
        );
        debugPrint('✅ Test tile layer created successfully');
      } catch (e) {
        debugPrint('❌ Failed to create test tile layer: $e');
        return false;
      }

      debugPrint('✅ Offline test passed - ${stats.length} tiles available');
      return true;
    } catch (e) {
      debugPrint('❌ Offline test failed: $e');
      return false;
    }
  }

  TileLayer getTileLayer({int? zoom, required bool useOffline}) {
    if (!_isInitialized) {
      debugPrint('⚠️ Map service not initialized, using fallback');
      return _createFallbackTileLayer();
    }

    try {
      // CRITICAL FIX: Respect the useOffline parameter instead of just checking _isOnline
      // This allows forcing offline mode even when internet is available
      if (!useOffline && _isOnline) {
        debugPrint('🌐 Using online tile layer (zoom: ${zoom ?? "unknown"})');
        return _onlineTileLayer;
      } else {
        // IMPROVED offline logic - always use base tiles with cacheFirst strategy
        // This ensures peer locations load from cached Philippines tiles
        debugPrint(
          '📴 Offline mode: using cached tiles with fallback (zoom: ${zoom ?? "unknown"})',
        );
        return _offlineTileLayer; // Now uses cacheFirst, will work for all of Philippines
      }
    } catch (e) {
      debugPrint('❌ Error in getTileLayer: $e');
      return _createFallbackTileLayer();
    }
  }

  /// Create fallback tile layer when service isn't initialized
  TileLayer _createFallbackTileLayer() {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.resqlink.app',
      maxZoom: 19,
    );
  }

  /// Monitor connectivity changes
  void _startConnectivityMonitoring() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      final wasOnline = _isOnline;
      _isOnline = results.any(
        (result) =>
            result == ConnectivityResult.mobile ||
            result == ConnectivityResult.wifi ||
            result == ConnectivityResult.ethernet,
      );

      if (wasOnline != _isOnline) {
        debugPrint('Connectivity changed: ${_isOnline ? "online" : "offline"}');
      }
    });

    // Check initial connectivity
    Connectivity().checkConnectivity().then((results) {
      _isOnline = results.any(
        (result) =>
            result == ConnectivityResult.mobile ||
            result == ConnectivityResult.wifi ||
            result == ConnectivityResult.ethernet,
      );
    });
  }

  /// Pre-cache area for offline use
  Future<DownloadProgress> cacheArea({
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    String? regionName,
    bool isEmergencyCache = false,
  }) async {
    if (!_isInitialized) {
      throw StateError('MapService not initialized');
    }

    if (!_isOnline) {
      throw StateError('Cannot download maps while offline');
    }

    final storeName = isEmergencyCache ? _emergencyStore : _userCacheStore;
    final store = FMTCStore(storeName);

    final region = fmtc.RectangleRegion(bounds);
    final downloadable = region.toDownloadable(
      minZoom: minZoom,
      maxZoom: maxZoom,
      options: TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.resqlink.app',
      ),
    );

    debugPrint('🚀 Starting download for ${regionName ?? "region"}');
    debugPrint('📍 Bounds: ${bounds.toString()}');
    debugPrint('🔍 Zoom: $minZoom-$maxZoom');

    final downloadResult = store.download.startForeground(
      region: downloadable,
      parallelThreads: 2, // Reduced for stability
      maxBufferLength: 50, // Reduced for stability
      skipExistingTiles: true,
      skipSeaTiles: true,
    );

    // Create a custom stream controller to track progress
    late StreamController<double> progressController;
    progressController = StreamController<double>();

    downloadResult.downloadProgress.listen(
      (progress) {
        final percentage = progress.percentageProgress;
        debugPrint('📊 Download progress: ${percentage.toStringAsFixed(1)}%');
        if (!progressController.isClosed) {
          progressController.add(percentage);
        }
      },
      onDone: () {
        debugPrint('✅ Download completed successfully');
        if (!progressController.isClosed) {
          progressController.add(100.0);
          progressController.close();
        }
      },
      onError: (error) {
        debugPrint('❌ Download error: $error');
        if (!progressController.isClosed) {
          progressController.addError(error);
          progressController.close();
        }
      },
    );

    return DownloadProgress(progressController.stream);
  }

  /// Pre-cache Philippines overview (low zoom levels)
  Future<void> precachePhilippinesOverview() async {
    if (!_isInitialized || !_isOnline) return;

    try {
      // Philippines bounds (approximate)
      final philippinesBounds = LatLngBounds(
        LatLng(4.5, 116.0), // Southwest
        LatLng(21.0, 127.0), // Northeast
      );

      await cacheArea(
        bounds: philippinesBounds,
        minZoom: 5,
        maxZoom: 8,
        regionName: 'Philippines Overview',
        isEmergencyCache: false,
      );

      debugPrint('Philippines overview cached successfully');
    } catch (e) {
      debugPrint('Error caching Philippines overview: $e');
    }
  }

  /// Get cache statistics
  Future<Map<String, CacheStats>> getCacheStats() async {
    if (!_isInitialized) return {};

    final stats = <String, CacheStats>{};
    final storeNames = [_philippinesStore, _userCacheStore, _emergencyStore];

    for (final storeName in storeNames) {
      try {
        final store = FMTCStore(storeName);
        final storeStats = await store.stats.all;
        final size = await store.stats.size;

        stats[storeName] = CacheStats(
          tileCount: storeStats.length,
          sizeBytes: size.toInt(),
          storeName: storeName,
        );
      } catch (e) {
        debugPrint('Error getting stats for $storeName: $e');
      }
    }

    return stats;
  }

  /// Clear specific cache store
  Future<void> clearCache(String? storeName) async {
    if (!_isInitialized) return;

    if (storeName == null) {
      // Clear all user caches (not the base Philippines cache)
      await FMTCStore(_userCacheStore).manage.reset();
      await FMTCStore(_emergencyStore).manage.reset();
    } else if (storeName != _philippinesStore) {
      await FMTCStore(storeName).manage.reset();
    }

    debugPrint('Cleared cache: ${storeName ?? "all user caches"}');
  }

  /// Get recommended cache regions for Philippines
  List<CacheRegion> getRecommendedRegions() {
    return [
      CacheRegion(
        name: 'Butuan City',
        bounds: LatLngBounds(
          const LatLng(8.8972, 125.4906), // SW
          const LatLng(8.9972, 125.5906), // NE
        ),
        priority: CachePriority.high,
        description: 'Butuan City and immediate surroundings',
      ),
      CacheRegion(
        name: 'Agusan del Norte',
        bounds: LatLngBounds(
          const LatLng(8.5000, 125.0000), // SW
          const LatLng(9.5000, 126.0000), // NE
        ),
        priority: CachePriority.medium,
        description: 'Full Agusan del Norte province',
      ),
      CacheRegion(
        name: 'Metro Manila',
        bounds: LatLngBounds(
          const LatLng(14.3000, 120.8000), // SW
          const LatLng(14.8000, 121.2000), // NE
        ),
        priority: CachePriority.medium,
        description: 'National Capital Region',
      ),
      CacheRegion(
        name: 'Cebu City',
        bounds: LatLngBounds(
          const LatLng(10.2000, 123.8000), // SW
          const LatLng(10.4000, 124.0000), // NE
        ),
        priority: CachePriority.medium,
        description: 'Cebu City metropolitan area',
      ),
      CacheRegion(
        name: 'Davao City',
        bounds: LatLngBounds(
          const LatLng(7.0000, 125.4000), // SW
          const LatLng(7.3000, 125.7000), // NE
        ),
        priority: CachePriority.medium,
        description: 'Davao City and surroundings',
      ),
    ];
  }

  /// Check if area is cached
  Future<bool> isAreaCached(LatLngBounds bounds, int zoom) async {
    if (!_isInitialized) return false;

    try {
      final store = FMTCStore(_userCacheStore);

      // Check if we have tiles in the specified bounds and zoom level
      // This is a simplified check - for accurate coverage, you'd need
      // to check specific tile coordinates
      final stats = await store.stats.all;

      if (stats.length == 0) return false;

      // Basic heuristic: if we have a reasonable number of tiles
      // and the store was created recently, assume good coverage
      // You might want to implement more sophisticated checking
      // by actually querying for specific tile coordinates

      return stats.length > 50; // Arbitrary threshold
    } catch (e) {
      debugPrint('Error checking cache coverage: $e');
      return false;
    }
  }

  /// Get detailed cache coverage for a specific area
  Future<CacheCoverage> getCachecoverage(LatLngBounds bounds, int zoom) async {
    if (!_isInitialized) {
      return CacheCoverage(
        coveragePercentage: 0,
        totalTiles: 0,
        cachedTiles: 0,
      );
    }

    try {
      // Calculate total tiles needed for the area
      final n = bounds.north * math.pi / 180;
      final s = bounds.south * math.pi / 180;
      final deltaLng = bounds.east - bounds.west;

      final tilesX = ((deltaLng / 360.0) * math.pow(2, zoom)).ceil();
      final tilesY =
          ((math.log(math.tan(math.pi / 4 + n / 2)) -
                      math.log(math.tan(math.pi / 4 + s / 2))) /
                  (2 * math.pi) *
                  math.pow(2, zoom))
              .abs()
              .ceil();

      final totalTiles = tilesX * tilesY;

      // For now, return approximate coverage based on store stats
      // In a full implementation, you'd check actual tile coordinates
      final store = FMTCStore(_userCacheStore);
      final stats = await store.stats.all;
      final cachedTiles = math.min(stats.length, totalTiles);

      final coveragePercentage = totalTiles > 0
          ? (cachedTiles / totalTiles * 100).round()
          : 0;

      return CacheCoverage(
        coveragePercentage: coveragePercentage,
        totalTiles: totalTiles,
        cachedTiles: cachedTiles,
      );
    } catch (e) {
      debugPrint('Error calculating cache coverage: $e');
      return CacheCoverage(
        coveragePercentage: 0,
        totalTiles: 0,
        cachedTiles: 0,
      );
    }
  }

  Future<int> getTotalCacheSize() async {
    if (!_isInitialized) return 0;

    final stats = await getCacheStats();
    return stats.values.fold<int>(0, (total, stat) => total + stat.sizeBytes);
  }

  /// Check if Philippines base map is available
  Future<bool> isPhilippinesBaseAvailable() async {
    if (!_isInitialized) return false;

    try {
      final store = FMTCStore(_philippinesStore);
      final stats = await store.stats.all;
      return stats.length > 0;
    } catch (e) {
      return false;
    }
  }

  /// Emergency cache for current location
  Future<void> emergencyCache(LatLng center, double radiusKm) async {
    final bounds = _calculateBounds(center, radiusKm);

    await cacheArea(
      bounds: bounds,
      minZoom: 10,
      maxZoom: 16,
      regionName: 'Emergency Cache',
      isEmergencyCache: true,
    );
  }

  LatLngBounds _calculateBounds(LatLng center, double radiusKm) {
    // Convert radius to degrees (approximate)
    final latOffset = radiusKm / 111.0; // 1 degree ≈ 111 km
    final lngOffset =
        radiusKm / (111.0 * math.cos(center.latitude * math.pi / 180));

    return LatLngBounds(
      LatLng(center.latitude - latOffset, center.longitude - lngOffset), // SW
      LatLng(center.latitude + latOffset, center.longitude + lngOffset), // NE
    );
  }

  /// Dispose resources
  void dispose() {
    _connectivitySubscription.cancel();
    _isInitialized = false;
  }
}

// Supporting models
class CriticalLocation {
  final String name;
  final LatLng coordinates;

  const CriticalLocation(this.name, this.coordinates);
}

class CacheStats {
  final int tileCount;
  final int sizeBytes;
  final String storeName;

  CacheStats({
    required this.tileCount,
    required this.sizeBytes,
    required this.storeName,
  });

  String get sizeFormatted {
    if (sizeBytes < 1024) return '${sizeBytes}B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
    }
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}

class CacheRegion {
  final String name;
  final LatLngBounds bounds;
  final CachePriority priority;
  final String description;

  CacheRegion({
    required this.name,
    required this.bounds,
    required this.priority,
    required this.description,
  });
}

class CacheCoverage {
  final int coveragePercentage;
  final int totalTiles;
  final int cachedTiles;

  CacheCoverage({
    required this.coveragePercentage,
    required this.totalTiles,
    required this.cachedTiles,
  });

  bool get isFullyCached => coveragePercentage >= 95;
  bool get isPartiallyCached => coveragePercentage > 0;

  @override
  String toString() {
    return 'CacheCoverage($coveragePercentage%, $cachedTiles/$totalTiles tiles)';
  }
}

enum CachePriority { low, medium, high, critical }

// Download progress tracking
class DownloadProgress {
  final Stream<double> stream;

  DownloadProgress(this.stream);

  // Add helper method to get percentage
  Stream<double> get percentageStream => stream;
}
