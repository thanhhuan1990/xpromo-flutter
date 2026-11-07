import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'picker.dart';

/// Cấu hình cho từng app chủ.
class XPromoConfig {
  const XPromoConfig({
    required this.selfPackage,
    required this.hostGroups,
    this.feedUrl = defaultFeedUrl,
    this.refreshHours = 24,
    this.cardMinIntervalDays = 3,
    this.hideDays = 30,
    this.enabled,
    this.analytics,
  });

  static const String defaultFeedUrl = 'https://thanhhuan1990.github.io/xpromo/apps.json';

  /// Package của app đang chạy (không tự quảng bá chính mình + làm utm_source).
  final String selfPackage;

  /// Nhóm chủ đề của app đang chạy – app cùng nhóm được ưu tiên.
  final List<String> hostGroups;
  final String feedUrl;
  final int refreshHours;

  /// Thẻ gợi ý: tối thiểu N ngày giữa 2 lần hiện.
  final int cardMinIntervalDays;

  /// User bấm ✕ → ẩn app đó N ngày.
  final int hideDays;

  /// Bật/tắt từ xa (Remote Config). Null = luôn bật.
  final bool Function()? enabled;

  /// Ghi analytics: xpromo_view / xpromo_list_view / xpromo_click / xpromo_dismiss.
  final void Function(String name, Map<String, Object> params)? analytics;
}

/// Quảng bá chéo: tải danh sách app (cache 24 giờ, dự phòng asset trong package), lọc app đã cài,
/// giới hạn tần suất thẻ gợi ý, mở Google Play kèm UTM. Chỉ hoạt động trên Android.
class XPromo {
  XPromo._(this.config, this._prefs, PromoFeed initial) : feed = ValueNotifier<PromoFeed>(initial);

  static const MethodChannel _channel = MethodChannel('com.huanhuynh.xpromo');
  static const String _bundledAsset = 'packages/xpromo/assets/apps.json';

  static const String _kFeed = 'feed_json';
  static const String _kFetchedAt = 'fetched_at';
  static const String _kCardAt = 'card_at';
  static const String _kCardApp = 'card_app';
  static const String _kCardCount = 'card_count';
  static const String _kHide = 'hide_';

  static XPromo? _instance;

  /// Null nếu chưa init hoặc không phải Android.
  static XPromo? get instance => _instance;

  final XPromoConfig config;
  final Map<String, Object?> _prefs;

  /// Danh sách hiện tại (đổi khi tải được bản mới).
  final ValueNotifier<PromoFeed> feed;

  Set<String>? _installedCache;

  /// Gọi một lần sau `WidgetsFlutterBinding.ensureInitialized()`. Không ném lỗi; trả null ngoài Android.
  static Future<XPromo?> init(XPromoConfig config) async {
    if (_instance != null) return _instance;
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('prefs') ?? <String, Object?>{};
      final prefs = Map<String, Object?>.from(raw);
      var initial = PromoFeed.tryParse(prefs[_kFeed] as String?);
      if (initial == null) {
        try {
          initial = PromoFeed.tryParse(await rootBundle.loadString(_bundledAsset));
        } catch (_) {}
      }
      _instance = XPromo._(config, prefs, initial ?? const PromoFeed());
      return _instance;
    } catch (e) {
      debugPrint('XPromo init failed: $e');
      return null;
    }
  }

  bool get enabled {
    try {
      return config.enabled?.call() ?? true;
    } catch (_) {
      return true;
    }
  }

  int _int(String key) {
    final v = _prefs[key];
    return v is num ? v.toInt() : 0;
  }

  void _put(String key, Object? value) {
    if (value == null) {
      _prefs.remove(key);
    } else {
      _prefs[key] = value;
    }
    _channel.invokeMethod<void>('prefsPut', {'key': key, 'value': value}).catchError((_) {});
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  static const int _hourMs = 3600000;
  static const int _dayMs = 24 * _hourMs;

  /// Tải lại danh sách nếu đã quá `refreshHours`. Gọi lúc mở app.
  Future<void> refreshIfStale({bool force = false}) async {
    if (!force && _now - _int(_kFetchedAt) < config.refreshHours * _hourMs) return;
    final raw = await _httpGet(config.feedUrl);
    final parsed = PromoFeed.tryParse(raw);
    if (parsed == null) return;
    _put(_kFeed, raw);
    _put(_kFetchedAt, _now);
    _installedCache = null;
    feed.value = parsed;
  }

  static Future<String?> _httpGet(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode > 299) return null;
      return await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<Set<String>> _installed() async {
    final cached = _installedCache;
    if (cached != null) return cached;
    try {
      final ids = feed.value.apps.map((e) => e.id).toList();
      final result = await _channel.invokeListMethod<String>('installed', {'ids': ids}) ?? const <String>[];
      return _installedCache = result.toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  Set<String> _hidden() {
    final now = _now;
    return _prefs.entries
        .where((e) => e.key.startsWith(_kHide) && e.value is num && (e.value as num) > now)
        .map((e) => e.key.substring(_kHide.length))
        .toSet();
  }

  /// App cho mục "Ứng dụng khác" (đã lọc app đã cài).
  Future<List<PromoApp>> candidates() async {
    if (!enabled) return const [];
    return XPromoPicker.rank(
      feed.value,
      selfPackage: config.selfPackage,
      hostGroups: config.hostGroups,
      country: PlatformDispatcher.instance.locale.countryCode,
      installed: await _installed(),
      hidden: _hidden(),
    );
  }

  /// App cho thẻ gợi ý, hoặc null nếu chưa tới lượt (giới hạn tần suất).
  Future<PromoApp?> nextCard() async {
    if (!enabled) return null;
    final list = await candidates();
    if (_now - _int(_kCardAt) < config.cardMinIntervalDays * _dayMs) {
      // Trong cùng "lượt" vẫn trả lại app đã hiện để thẻ không biến mất khi quay lại màn.
      final current = _prefs[_kCardApp];
      for (final app in list) {
        if (app.id == current) return app;
      }
      return null;
    }
    return XPromoPicker.pickForCard(list, _int(_kCardCount));
  }

  /// Ghi nhận thẻ đã hiện (bắt đầu tính khoảng cách tần suất).
  void onCardShown(PromoApp app, String placement) {
    if (_prefs[_kCardApp] == app.id && _now - _int(_kCardAt) < config.cardMinIntervalDays * _dayMs) return;
    _put(_kCardAt, _now);
    _put(_kCardApp, app.id);
    _put(_kCardCount, _int(_kCardCount) + 1);
    _log('xpromo_view', app, placement);
  }

  void onListShown(List<PromoApp> apps, String placement) {
    if (apps.isEmpty) return;
    _analytics('xpromo_list_view', {'placement': placement, 'count': apps.length, 'source': config.selfPackage});
  }

  /// User bấm ✕ → ẩn app đó `hideDays` ngày.
  void dismiss(PromoApp app, String placement) {
    _put('$_kHide${app.id}', _now + config.hideDays * _dayMs);
    _put(_kCardApp, null);
    _log('xpromo_dismiss', app, placement);
  }

  /// Mở trang Google Play của app (kèm UTM).
  Future<void> open(PromoApp app, String placement) async {
    _log('xpromo_click', app, placement);
    try {
      await _channel.invokeMethod<bool>('open', {
        'market': XPromoPicker.marketUri(app.id, config.selfPackage, placement),
        'web': XPromoPicker.webUri(app.id, config.selfPackage, placement),
      });
    } catch (_) {}
  }

  void _log(String event, PromoApp app, String placement) =>
      _analytics(event, {'target': app.id, 'placement': placement, 'source': config.selfPackage});

  void _analytics(String name, Map<String, Object> params) {
    try {
      config.analytics?.call(name, params);
    } catch (_) {}
  }
}
