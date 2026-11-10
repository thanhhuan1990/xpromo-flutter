import 'models.dart';

/// Chọn & sắp xếp app để quảng bá (thuần Dart → test được).
class XPromoPicker {
  XPromoPicker._();

  /// Loại: chính app đang chạy, app user đã ẩn; app chưa cài thì loại thêm app tắt / không dành cho quốc gia này.
  /// App đã cài: bỏ nếu `includeInstalled = false` (mặc định); ngược lại giữ (kể cả app đang tắt) và xếp sau
  /// app chưa cài – để hiện nút "Mở".
  /// Sắp: chưa cài trước → càng chung nhóm chủ đề càng lên trước → priority → tên.
  static List<PromoApp> rank(
    PromoFeed feed, {
    required String selfPackage,
    required List<String> hostGroups,
    String? country,
    Set<String> installed = const {},
    Set<String> hidden = const {},
    bool includeInstalled = false,
  }) {
    final c = country?.toUpperCase();
    bool countryOk(PromoApp a) => a.countries.isEmpty || (c != null && a.countries.map((e) => e.toUpperCase()).contains(c));
    final list = feed.apps.where((a) {
      if (a.id == selfPackage || hidden.contains(a.id)) return false;
      if (installed.contains(a.id)) return includeInstalled;
      return a.enabled && countryOk(a);
    }).toList();
    int shared(PromoApp a) => a.groups.where(hostGroups.contains).length;
    list.sort((a, b) {
      final i = (installed.contains(a.id) ? 1 : 0).compareTo(installed.contains(b.id) ? 1 : 0);
      if (i != 0) return i;
      final g = shared(b).compareTo(shared(a));
      if (g != 0) return g;
      final p = b.priority.compareTo(a.priority);
      if (p != 0) return p;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  /// Thẻ gợi ý: xoay vòng trong nhóm đầu (tối đa 3 app) theo số lần đã hiện.
  static PromoApp? pickForCard(List<PromoApp> ranked, int shownCount) {
    if (ranked.isEmpty) return null;
    final top = ranked.take(3).toList();
    return top[shownCount % top.length];
  }

  /// Referrer cho Google Play (Play Console thống kê lượt cài theo nguồn UTM).
  static String playReferrer(String selfPackage, String placement) =>
      'utm_source%3D$selfPackage%26utm_medium%3Dxpromo%26utm_campaign%3D$placement';

  static String marketUri(String target, String selfPackage, String placement) =>
      'market://details?id=$target&referrer=${playReferrer(selfPackage, placement)}';

  static String webUri(String target, String selfPackage, String placement) =>
      'https://play.google.com/store/apps/details?id=$target&referrer=${playReferrer(selfPackage, placement)}';
}
