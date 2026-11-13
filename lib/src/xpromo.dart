import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

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
    this.languages = const ['vi'],
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

  /// Ngôn ngữ app hỗ trợ (vi, en…); phần tử đầu là mặc định. Chỉ gợi ý app đích có ngôn ngữ đang dùng.
  final List<String> languages;
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
  static const String _kCardLast = 'card_last';
  static const String _kViews = 'views_';
  static const String _kViewAt = 'viewat_';
  static const String _kClicks = 'clicks_';

  static XPromo? _instance;

  /// Null nếu chưa init hoặc không phải Android.
  static XPromo? get instance => _instance;

  final XPromoConfig config;
  final Map<String, Object?> _prefs;

  /// Danh sách hiện tại (đổi khi tải được bản mới).
  final ValueNotifier<PromoFeed> feed;

  /// Tăng mỗi khi app quay lại màn hình: widget đọc lại app nào đã cài (cài xong từ Google Play → hiện "Mở").
  /// Trước 1.0.5 danh sách app đã cài chỉ đọc một lần nên vẫn hiện "Cài".
  final ValueNotifier<int> installTick = ValueNotifier<int>(0);

  Set<String>? _installedCache;

  /// Bản danh sách đóng gói sẵn trong package (để so với bản tải về – lấy bản mới hơn theo `version`).
  static PromoFeed? _bundled;

  static PromoFeed? _newest(PromoFeed? a, PromoFeed? b) {
    if (a == null) return b;
    if (b == null) return a;
    return b.version.compareTo(a.version) > 0 ? b : a;
  }

  /// Gọi một lần sau `WidgetsFlutterBinding.ensureInitialized()`. Không ném lỗi; trả null ngoài Android.
  static Future<XPromo?> init(XPromoConfig config) async {
    if (_instance != null) return _instance;
    if (kIsWeb || !Platform.isAndroid) {
      if (kDebugMode) debugPrint('XPromo: chỉ hỗ trợ Android');
      return null;
    }
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('prefs') ?? <String, Object?>{};
      final prefs = Map<String, Object?>.from(raw);
      final cached = PromoFeed.tryParse(prefs[_kFeed] as String?);
      PromoFeed? bundled;
      try {
        bundled = PromoFeed.tryParse(await rootBundle.loadString(_bundledAsset));
      } catch (_) {}
      _bundled = bundled;
      final initial = _newest(cached, bundled);
      _instance = XPromo._(config, prefs, initial ?? const PromoFeed());
      final x = _instance!;
      WidgetsBinding.instance.addObserver(_ResumeObserver(x.refreshInstalled));
      if (kDebugMode) debugPrint('XPromo: init ok, ${_instance!.feed.value.apps.length} app trong feed');
      return _instance;
    } catch (e) {
      debugPrint('XPromo init failed: $e');
      return null;
    }
  }

  /// Đọc lại trạng thái cài của các app (tự gọi khi app quay lại màn hình).
  void refreshInstalled() {
    _installedCache = null;
    installTick.value++;
  }

  /// Ngôn ngữ giao diện hiện tại (trong `config.languages`).
  String currentLang() {
    final current = PlatformDispatcher.instance.locale.languageCode;
    return config.languages.contains(current) ? current : (config.languages.isEmpty ? 'vi' : config.languages.first);
  }

  Map<String, PromoStats> _stats() {
    final ids = <String>{};
    for (final k in _prefs.keys) {
      if (k.startsWith(_kViews)) ids.add(k.substring(_kViews.length));
      if (k.startsWith(_kClicks)) ids.add(k.substring(_kClicks.length));
    }
    return {for (final id in ids) id: PromoStats(views: _int('$_kViews$id'), clicks: _int('$_kClicks$id'))};
  }

  /// Đếm lượt hiện, mỗi app tối đa 1 lần / 12 giờ.
  void _countView(String id) {
    if (_now - _int('$_kViewAt$id') < 12 * _hourMs) return;
    _put('$_kViewAt$id', _now);
    _put('$_kViews$id', _int('$_kViews$id') + 1);
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
    feed.value = _newest(parsed, _bundled) ?? parsed;
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

  /// App đã cài trên máy (trong danh sách feed).
  Future<Set<String>> installedIds() => _installed();

  /// Các app [ids] (theo thứ tự) còn đủ điều kiện; mặc định giữ cả app đã cài (nút "Mở"), app chưa cài lên trước.
  Future<List<PromoApp>> targets(List<String> ids, {bool includeInstalled = true}) async {
    final ok = {for (final a in await candidates(includeInstalled: includeInstalled)) a.id: a};
    final installed = await _installed();
    final list = [for (final id in ids) if (ok[id] != null) ok[id]!];
    list.sort((a, b) => (installed.contains(a.id) ? 1 : 0).compareTo(installed.contains(b.id) ? 1 : 0));
    return list;
  }

  /// App cho mục "Ứng dụng khác". Mặc định bỏ app đã cài; `includeInstalled` giữ lại (xếp sau) để hiện nút "Mở".
  Future<List<PromoApp>> candidates({bool includeInstalled = false, String? lang}) async {
    if (!enabled) {
      if (kDebugMode) debugPrint('XPromo: tắt (config.enabled = false)');
      return const [];
    }
    final installed = await _installed();
    final hidden = _hidden();
    final list = XPromoPicker.rank(
      feed.value,
      selfPackage: config.selfPackage,
      hostGroups: config.hostGroups,
      country: PlatformDispatcher.instance.locale.countryCode,
      installed: installed,
      hidden: hidden,
      includeInstalled: includeInstalled,
      lang: lang ?? currentLang(),
      stats: _stats(),
    );
    if (kDebugMode) {
      final enabledApps = feed.value.apps.where((a) => a.enabled).map((a) => a.id).toList();
      debugPrint('XPromo: feed ${feed.value.version} – bật ${enabledApps.length} app $enabledApps; '
          'đã cài $installed; đã ẩn $hidden; còn gợi ý ${list.length}: ${list.map((a) => a.id).toList()}');
    }
    return list;
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
    return XPromoPicker.pickForCard(list, _int(_kCardCount), lastId: _prefs[_kCardLast] as String?);
  }

  /// Ghi nhận thẻ đã hiện (bắt đầu tính khoảng cách tần suất).
  void onCardShown(PromoApp app, String placement) {
    if (_prefs[_kCardApp] == app.id && _now - _int(_kCardAt) < config.cardMinIntervalDays * _dayMs) return;
    _put(_kCardAt, _now);
    _put(_kCardApp, app.id);
    _put(_kCardLast, app.id);
    _put(_kCardCount, _int(_kCardCount) + 1);
    _countView(app.id);
    _log('xpromo_view', app, placement);
  }

  /// Ghi nhận user bấm "Xem thêm" trong mục "Ứng dụng khác".
  void logListExpand(int count, String placement) =>
      _analytics('xpromo_list_expand', {'placement': placement, 'count': count, 'source': config.selfPackage});

  void onListShown(List<PromoApp> apps, String placement) {
    if (apps.isEmpty) return;
    final installed = _installedCache ?? const <String>{};
    for (final a in apps) {
      if (!installed.contains(a.id)) _countView(a.id);
    }
    _analytics('xpromo_list_view', {'placement': placement, 'count': apps.length, 'source': config.selfPackage});
  }

  /// User bấm ✕ → ẩn app đó `hideDays` ngày.
  void dismiss(PromoApp app, String placement) {
    _put('$_kHide${app.id}', _now + config.hideDays * _dayMs);
    _put(_kCardApp, null);
    _log('xpromo_dismiss', app, placement);
  }

  /// App đã cài → mở app; chưa cài → mở trang Google Play (kèm UTM).
  Future<void> open(PromoApp app, String placement) async {
    _put('$_kClicks${app.id}', _int('$_kClicks${app.id}') + 1);
    if ((await _installed()).contains(app.id)) {
      try {
        final ok = await _channel.invokeMethod<bool>('launch', {'id': app.id}) ?? false;
        if (ok) {
          _log('xpromo_open_app', app, placement);
          return;
        }
      } catch (_) {}
    }
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

/// Gọi [onResume] mỗi khi app quay lại màn hình.
class _ResumeObserver extends WidgetsBindingObserver {
  _ResumeObserver(this.onResume);

  final void Function() onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }
}
