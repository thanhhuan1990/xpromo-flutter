import 'models.dart';

/// Chọn & sắp xếp app để quảng bá (thuần Dart → test được). Cùng quy tắc với xpromo-android.
class XPromoPicker {
  XPromoPicker._();

  /// Đã hiện từng ấy lần mà chưa lần nào được bấm → coi như người dùng không quan tâm, xếp sau.
  static const int fatigueViews = 5;

  /// Nhóm gần nhau: chung nhóm với app nguồn +2 điểm mỗi nhóm, nhóm "liên quan" +1.
  static const Map<String, Set<String>> related = {
    'spiritual': {'daily', 'household'},
    'household': {'finance', 'health', 'daily', 'spiritual'},
    'finance': {'household', 'daily'},
    'health': {'household', 'daily'},
    'daily': {'spiritual', 'household', 'finance', 'health', 'education'},
    'education': {'daily', 'games'},
    'games': {'fun', 'education'},
    'fun': {'games'},
  };

  static int groupScore(PromoApp app, List<String> hostGroups) {
    var score = 0;
    for (final g in app.groups) {
      if (hostGroups.contains(g)) {
        score += 2;
      } else if (hostGroups.any((h) => related[h]?.contains(g) ?? false)) {
        score += 1;
      }
    }
    return score;
  }

  static bool _fatigued(PromoStats? s) => s != null && s.clicks == 0 && s.views >= fatigueViews;

  /// Loại: chính app đang chạy, app user đã ẩn; app chưa cài thì loại thêm app tắt / không dành cho quốc gia này /
  /// không có ngôn ngữ [lang]. App đã cài: bỏ nếu `includeInstalled = false` (mặc định); ngược lại giữ
  /// (kể cả app đang tắt) và xếp sau app chưa cài – để hiện nút "Mở".
  /// Sắp: chưa cài trước → app chưa "nhàm" → điểm nhóm → priority → tên.
  static List<PromoApp> rank(
    PromoFeed feed, {
    required String selfPackage,
    required List<String> hostGroups,
    String? country,
    Set<String> installed = const {},
    Set<String> hidden = const {},
    bool includeInstalled = false,
    String? lang,
    Map<String, PromoStats> stats = const {},
  }) {
    final c = country?.toUpperCase();
    bool countryOk(PromoApp a) => a.countries.isEmpty || (c != null && a.countries.map((e) => e.toUpperCase()).contains(c));
    final list = feed.apps.where((a) {
      if (a.id == selfPackage || hidden.contains(a.id)) return false;
      if (installed.contains(a.id)) return includeInstalled;
      return a.enabled && a.supports(lang) && countryOk(a);
    }).toList();
    list.sort((a, b) {
      final i = (installed.contains(a.id) ? 1 : 0).compareTo(installed.contains(b.id) ? 1 : 0);
      if (i != 0) return i;
      final f = (_fatigued(stats[a.id]) ? 1 : 0).compareTo(_fatigued(stats[b.id]) ? 1 : 0);
      if (f != 0) return f;
      final g = groupScore(b, hostGroups).compareTo(groupScore(a, hostGroups));
      if (g != 0) return g;
      final p = b.priority.compareTo(a.priority);
      if (p != 0) return p;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  /// Thẻ gợi ý: xoay vòng trong nhóm đầu (tối đa 3 app) theo số lần đã hiện, bỏ app vừa hiện ([lastId]) nếu còn app khác.
  static PromoApp? pickForCard(List<PromoApp> ranked, int shownCount, {String? lastId}) {
    if (ranked.isEmpty) return null;
    final top = ranked.take(3).toList();
    final others = top.where((a) => a.id != lastId).toList();
    final pool = others.isEmpty ? top : others;
    return pool[shownCount % pool.length];
  }

  /// Referrer cho Google Play (Play Console thống kê lượt cài theo nguồn UTM).
  static String playReferrer(String selfPackage, String placement) =>
      'utm_source%3D$selfPackage%26utm_medium%3Dxpromo%26utm_campaign%3D$placement';

  static String marketUri(String target, String selfPackage, String placement) =>
      'market://details?id=$target&referrer=${playReferrer(selfPackage, placement)}';

  static String webUri(String target, String selfPackage, String placement) =>
      'https://play.google.com/store/apps/details?id=$target&referrer=${playReferrer(selfPackage, placement)}';
}
