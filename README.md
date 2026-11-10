# xpromo-flutter

Quảng bá chéo các app của HuanHuynh cho app **Flutter** (Android). Cùng danh sách `apps.json` với thư viện Kotlin [xpromo-android](https://github.com/thanhhuan1990/xpromo-android).

- `MoreAppsSection`: mục "Ứng dụng khác của chúng tôi", tối đa 4 app chưa cài.
- `XPromoCard`: thẻ gợi ý, tự giới hạn tần suất (mặc định 3 ngày/lần), nút ✕ ẩn app đó 30 ngày.
- Danh sách tải từ `https://thanhhuan1990.github.io/xpromo/apps.json`, lưu 24 giờ; không có mạng thì dùng `assets/apps.json` trong package.
- Mở Google Play kèm UTM (`utm_medium=xpromo`).
- Phần native viết bằng **Java** (không kéo Kotlin Gradle Plugin), có sẵn `<queries>` tự gộp vào manifest app.
- Không phụ thuộc package nào ngoài Flutter. Trên iOS/web: `XPromo.init` trả `null`, widget không hiện gì.

## Dùng trong app

`pubspec.yaml`:
```yaml
dependencies:
  xpromo:
    git:
      url: https://github.com/thanhhuan1990/xpromo-flutter.git
      ref: 1.0.2
```

`main()` (sau `WidgetsFlutterBinding.ensureInitialized()`):
```dart
await XPromo.init(XPromoConfig(
  selfPackage: 'com.huanhuynh.numerology',
  hostGroups: ['spiritual'],
  analytics: (name, params) => FirebaseAnalytics.instance.logEvent(name: name, parameters: params),
));
XPromo.instance?.refreshIfStale();
```

UI:
```dart
const MoreAppsSection(placement: 'home')
const XPromoCard(placement: 'result_done')
```
Đổi màu qua `XPromoStyle(cardColor: ..., accentColor: ...)`.

## Phát triển cùng app (chưa cần tag)
Trong app, tạo `pubspec_overrides.yaml` (đừng commit):
```yaml
dependency_overrides:
  xpromo:
    path: ../xpromo-flutter
```

## Thêm app mới / phát hành
1. Sửa `apps.json` trên repo `thanhhuan1990.github.io` (các app tự cập nhật ≤ 24 giờ).
2. Repo này: chép `apps.json` vào `assets/`, thêm `<package>` vào `android/src/main/AndroidManifest.xml`, chạy `flutter test`.
3. `git tag 1.0.1 && git push origin main --tags`, rồi đổi `ref` trong app.
