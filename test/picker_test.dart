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

  test('includeInstalled giữ app đã cài (kể cả đang tắt), xếp sau', () {
    final f = PromoFeed(apps: const [
      PromoApp(id: 'a', name: 'a', groups: ['spiritual'], priority: 10),
      PromoApp(id: 'b', name: 'b', groups: ['spiritual'], priority: 90),
      PromoApp(id: 'off', name: 'off', groups: ['spiritual'], enabled: false),
    ]);
    final r = XPromoPicker.rank(f, selfPackage: 'self', hostGroups: const ['spiritual'], installed: const {'b', 'off'}, includeInstalled: true);
    expect(r.map((e) => e.id).toList(), ['a', 'b', 'off']);
    final r2 = XPromoPicker.rank(f, selfPackage: 'self', hostGroups: const ['spiritual'], installed: const {'b', 'off'});
    expect(r2.map((e) => e.id).toList(), ['a']);
  });
  test('nhóm liên quan xếp trước nhóm không liên quan', () {
    final f = PromoFeed(apps: const [
      PromoApp(id: 'game', name: 'game', groups: ['games', 'fun'], priority: 99),
      PromoApp(id: 'lich', name: 'lich', groups: ['spiritual', 'daily'], priority: 10),
      PromoApp(id: 'dict', name: 'dict', groups: ['education', 'daily'], priority: 50),
    ]);
    expect(XPromoPicker.rank(f, selfPackage: 'self', hostGroups: const ['spiritual']).map((e) => e.id).toList(), ['lich', 'dict', 'game']);
    expect(XPromoPicker.rank(f, selfPackage: 'self', hostGroups: const ['games', 'fun']).map((e) => e.id).toList(), ['game', 'dict', 'lich']);
  });

  test('lọc theo ngôn ngữ (chỉ app chưa cài)', () {
    final f = PromoFeed(apps: const [
      PromoApp(id: 'vankhan', name: 'vankhan', groups: ['spiritual'], languages: ['vi']),
      PromoApp(id: 'covay', name: 'covay', groups: ['games'], languages: ['vi', 'en']),
      PromoApp(id: 'wheel', name: 'wheel', groups: ['fun']),
    ]);
    expect(XPromoPicker.rank(f, selfPackage: 'self', hostGroups: const ['games'], lang: 'en').map((e) => e.id).toList(), ['covay', 'wheel']);
    expect(XPromoPicker.rank(f, selfPackage: 'self', hostGroups: const ['games'], lang: 'vi').length, 3);
    expect(XPromoPicker.rank(f, selfPackage: 'self', hostGroups: const ['games'], lang: 'en', installed: const {'vankhan'}, includeInstalled: true)
        .any((e) => e.id == 'vankhan'), isTrue);
  });

  test('app hiện nhiều lần không ai bấm bị xếp sau', () {
    final stats = {'water': const PromoStats(views: XPromoPicker.fatigueViews)};
    final r = XPromoPicker.rank(feed, selfPackage: 'self', hostGroups: ['household', 'health', 'daily'], country: 'VN', stats: stats);
    expect(r.map((e) => e.id), ['chitieu', 'lich', 'water']);
  });

  test('pickForCard bỏ app vừa hiện', () {
    final ranked = [app('a'), app('b'), app('c')];
    expect([0, 1, 2, 3].every((i) => XPromoPicker.pickForCard(ranked, i, lastId: 'b')!.id != 'b'), isTrue);
    expect(XPromoPicker.pickForCard([app('a')], 2, lastId: 'a')!.id, 'a');
  });

  test('splitForList: nhóm 1 chung nhóm, nhóm 2 còn lại', () {
    final ranked = [app('a', groups: ['games']), app('b', groups: ['games']), app('c', groups: ['education']), app('d', groups: ['games']), app('e', groups: ['spiritual'])];
    final (first, rest) = XPromoPicker.splitForList(ranked, ['games', 'fun'], 2);
    expect(first.map((e) => e.id).toList(), ['a', 'b']);
    expect(rest.map((e) => e.id).toList(), ['c', 'd', 'e']);
    final (f2, r2) = XPromoPicker.splitForList(ranked, ['health'], 3);
    expect(f2.map((e) => e.id).toList(), ['a', 'b', 'c']);
    expect(r2.map((e) => e.id).toList(), ['d', 'e']);
  });

  test('manifest có intent MEMBER', () {
    final manifest = File('android/src/main/AndroidManifest.xml').readAsStringSync();
    expect('com.huanhuynh.xpromo.MEMBER'.allMatches(manifest).length, 2);
  });
}
