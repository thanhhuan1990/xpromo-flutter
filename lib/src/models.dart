import 'dart:convert';

/// Một app trong danh sách quảng bá.
class PromoApp {
  const PromoApp({
    required this.id,
    required this.name,
    this.tagline = '',
    this.emoji = '📱',
    this.icon,
    this.groups = const [],
    this.countries = const [],
    this.priority = 0,
    this.enabled = true,
    this.languages = const [],
  });

  /// Package name trên Google Play.
  final String id;
  final String name;
  final String tagline;

  /// Hiện khi chưa tải được icon.
  final String emoji;

  /// URL PNG vuông (khuyến nghị 192 px).
  final String? icon;

  /// Nhóm chủ đề: spiritual, household, health, finance, daily, fun…
  final List<String> groups;

  /// Mã quốc gia ISO (VN, US…). Rỗng = mọi nơi.
  final List<String> countries;
  final int priority;
  final bool enabled;

  /// Ngôn ngữ giao diện của app đích (vi, en, zh, ja). App chưa cài chỉ được gợi ý khi app nguồn đang dùng
  /// một trong các ngôn ngữ này. Rỗng = phù hợp mọi ngôn ngữ.
  final List<String> languages;

  bool supports(String? lang) => lang == null || languages.isEmpty || languages.contains(lang);

  factory PromoApp.fromJson(Map<String, dynamic> json) => PromoApp(
        id: json['id'] as String,
        name: json['name'] as String,
        tagline: (json['tagline'] as String?) ?? '',
        emoji: (json['emoji'] as String?) ?? '📱',
        icon: json['icon'] as String?,
        groups: _strings(json['groups']),
        countries: _strings(json['countries']),
        priority: (json['priority'] as num?)?.toInt() ?? 0,
        enabled: (json['enabled'] as bool?) ?? true,
        languages: _strings(json['languages']),
      );

  static List<String> _strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : const <String>[];
}

/// Số lần một app đã được hiện / được bấm trên máy này.
class PromoStats {
  const PromoStats({this.views = 0, this.clicks = 0});
  final int views;
  final int clicks;
}

/// Toàn bộ danh sách (apps.json).
class PromoFeed {
  const PromoFeed({this.schemaVersion = 1, this.version = '', this.developer = '', this.apps = const []});

  final int schemaVersion;
  final String version;
  final String developer;
  final List<PromoApp> apps;

  factory PromoFeed.fromJson(Map<String, dynamic> json) => PromoFeed(
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
        version: (json['version'] as String?) ?? '',
        developer: (json['developer'] as String?) ?? '',
        apps: ((json['apps'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) {
              try {
                return PromoApp.fromJson(Map<String, dynamic>.from(e));
              } catch (_) {
                return null;
              }
            })
            .whereType<PromoApp>()
            .toList(),
      );

  /// Trả null nếu chuỗi hỏng hoặc không có app nào.
  static PromoFeed? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final feed = PromoFeed.fromJson(Map<String, dynamic>.from(decoded));
      return feed.apps.isEmpty ? null : feed;
    } catch (_) {
      return null;
    }
  }
}
