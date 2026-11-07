import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xpromo/xpromo.dart';

PromoApp app(String id, {List<String> groups = const [], int priority = 0, bool enabled = true, List<String> countries = const []}) =>
    PromoApp(id: id, name: id, groups: groups, priority: priority, enabled: enabled, countries: countries);

void main() {
  final feed = PromoFeed(apps: [
    app('self', groups: ['household']),
    app('lich', groups: ['spiritual'], priority: 90),
    app('water', groups: ['health', 'daily'], priority: 50),
    app('chitieu', groups: ['household', 'finance'], priority: 60),
    app('off', groups: ['household'], enabled: false),
    app('us_only', groups: ['household'], countries: ['US']),
  ]);

  test('rank: lọc và sắp theo nhóm rồi priority', () {
    final r = XPromoPicker.rank(feed, selfPackage: 'self', hostGroups: ['household', 'health', 'daily'], country: 'vn');
    expect(r.map((e) => e.id), ['water', 'chitieu', 'lich']);
  });

  test('rank: bỏ app đã cài và app đã ẩn', () {
    final r = XPromoPicker.rank(feed,
        selfPackage: 'self', hostGroups: ['household'], country: 'VN', installed: {'chitieu'}, hidden: {'water'});
    expect(r.map((e) => e.id), ['lich']);
  });

  test('rank: lọc quốc gia', () {
    final us = XPromoPicker.rank(feed, selfPackage: 'self', hostGroups: ['household'], country: 'US');
    final vn = XPromoPicker.rank(feed, selfPackage: 'self', hostGroups: ['household'], country: 'VN');
    expect(us.any((e) => e.id == 'us_only'), isTrue);
    expect(vn.any((e) => e.id == 'us_only'), isFalse);
  });

  test('pickForCard xoay vòng 3 app đầu', () {
    final ranked = [app('a'), app('b'), app('c'), app('d')];
    expect([0, 1, 2, 3].map((i) => XPromoPicker.pickForCard(ranked, i)!.id), ['a', 'b', 'c', 'a']);
    expect(XPromoPicker.pickForCard(const [], 0), isNull);
  });

  test('marketUri có UTM', () {
    expect(XPromoPicker.marketUri('com.x', 'com.self', 'settings'),
        'market://details?id=com.x&referrer=utm_source%3Dcom.self%26utm_medium%3Dxpromo%26utm_campaign%3Dsettings');
  });

  test('assets/apps.json đọc được, không trùng id', () {
    final parsed = PromoFeed.tryParse(File('assets/apps.json').readAsStringSync())!;
    expect(parsed.apps, isNotEmpty);
    expect(parsed.apps.map((e) => e.id).toSet().length, parsed.apps.length);
  });

  test('manifest có <package> cho mọi app trong apps.json', () {
    final parsed = PromoFeed.tryParse(File('assets/apps.json').readAsStringSync())!;
    final manifest = File('android/src/main/AndroidManifest.xml').readAsStringSync();
    final declared = RegExp(r'<package android:name="([^"]+)"').allMatches(manifest).map((m) => m.group(1)).toSet();
    final missing = parsed.apps.map((e) => e.id).where((id) => !declared.contains(id)).toList();
    expect(missing, isEmpty, reason: 'Thiếu <package> trong AndroidManifest.xml: $missing');
  });
}
