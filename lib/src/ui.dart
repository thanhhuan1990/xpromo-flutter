import 'package:flutter/material.dart';

import 'models.dart';
import 'xpromo.dart';

/// Màu cho widget XPromo. Mặc định lấy theo Theme của app.
class XPromoStyle {
  const XPromoStyle({
    this.cardColor,
    this.borderColor,
    this.textColor,
    this.mutedColor,
    this.accentColor,
    this.onAccentColor,
    this.radius = 16,
  });

  final Color? cardColor;
  final Color? borderColor;
  final Color? textColor;
  final Color? mutedColor;
  final Color? accentColor;
  final Color? onAccentColor;
  final double radius;

  Color card(BuildContext c) => cardColor ?? Theme.of(c).colorScheme.surfaceContainerHighest;
  Color border(BuildContext c) => borderColor ?? Theme.of(c).dividerColor;
  Color text(BuildContext c) => textColor ?? Theme.of(c).colorScheme.onSurface;
  Color muted(BuildContext c) => mutedColor ?? Theme.of(c).colorScheme.onSurfaceVariant;
  Color accent(BuildContext c) => accentColor ?? Theme.of(c).colorScheme.primary;
  Color onAccent(BuildContext c) => onAccentColor ?? Theme.of(c).colorScheme.onPrimary;
}

/// Icon app: tải từ URL, lỗi/chưa có thì hiện emoji.
class XPromoIcon extends StatelessWidget {
  const XPromoIcon({super.key, required this.app, this.size = 44, this.background});

  final PromoApp app;
  final double size;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final emoji = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: background ?? const Color(0xFFEEF0F3),
      child: Text(app.emoji, style: TextStyle(fontSize: size * 0.5)),
    );
    // Icon đóng gói sẵn trong package (không mạng vẫn đúng icon), lỗi nữa mới hiện emoji.
    final fallback = Image.asset(
      'packages/xpromo/assets/icons/${app.id}.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => emoji,
    );
    final url = app.icon;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: url == null
          ? fallback
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
              loadingBuilder: (_, child, progress) => progress == null ? child : fallback,
            ),
    );
  }
}

/// Mục "Ứng dụng khác của chúng tôi": tối đa [max] app. App chưa cài nút [installLabel] (mở Google Play),
/// app đã cài (khi [showInstalled]) nút [openLabel] (mở app). [ids] = chỉ các app này. Rỗng → không chiếm chỗ.
class MoreAppsSection extends StatefulWidget {
  const MoreAppsSection({
    super.key,
    this.placement = 'settings',
    this.title = 'Ứng dụng khác của chúng tôi',
    this.installLabel = 'Cài',
    this.openLabel = 'Mở',
    this.max = 4,
    this.ids,
    this.showInstalled = false,
    this.style = const XPromoStyle(),
    this.titleStyle,
    this.padding = EdgeInsets.zero,
  });

  final String placement;
  final String title;
  final String installLabel;
  final String openLabel;
  final int max;
  final List<String>? ids;
  final bool showInstalled;
  final XPromoStyle style;
  final TextStyle? titleStyle;
  final EdgeInsetsGeometry padding;

  @override
  State<MoreAppsSection> createState() => _MoreAppsSectionState();
}

class _MoreAppsSectionState extends State<MoreAppsSection> {
  List<PromoApp> _apps = const [];
  Set<String> _installed = const {};
  bool _logged = false;

  XPromo? get _xpromo => XPromo.instance;

  @override
  void initState() {
    super.initState();
    _xpromo?.feed.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _xpromo?.feed.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final x = _xpromo;
    if (x == null) return;
    final ids = widget.ids;
    final all = ids != null
        ? await x.targets(ids, includeInstalled: widget.showInstalled)
        : await x.candidates(includeInstalled: widget.showInstalled);
    final apps = all.take(widget.max).toList();
    final installed = await x.installedIds();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _installed = installed;
    });
    if (!_logged && apps.isNotEmpty) {
      _logged = true;
      x.onListShown(apps, widget.placement);
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = _xpromo;
    if (x == null || _apps.isEmpty) return const SizedBox.shrink();
    final s = widget.style;
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 10),
              child: Text(
                widget.title,
                style: widget.titleStyle ??
                    TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: s.muted(context)),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: s.card(context),
              borderRadius: BorderRadius.circular(s.radius),
              border: Border.all(color: s.border(context)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: Column(
              children: [
                for (var i = 0; i < _apps.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: s.border(context)),
                  _row(context, x, _apps[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, XPromo x, PromoApp app) {
    final s = widget.style;
    return InkWell(
      onTap: () => x.open(app, widget.placement),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            XPromoIcon(app: app),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: s.text(context)),
                  ),
                  if (app.tagline.isNotEmpty)
                    Text(
                      app.tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: s.muted(context), height: 1.3),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => x.open(app, widget.placement),
              style: TextButton.styleFrom(foregroundColor: s.accent(context)),
              child: Text(_installed.contains(app.id) ? widget.openLabel : widget.installLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thẻ gợi ý theo ngữ cảnh – đặt ở "điểm nghỉ", không chen vào luồng chính.
/// Tự giới hạn tần suất; nút ✕ ẩn app đó; ghi rõ là app cùng nhà phát triển.
class XPromoCard extends StatefulWidget {
  const XPromoCard({
    super.key,
    required this.placement,
    this.label = 'Ứng dụng cùng nhà phát triển',
    this.actionLabel = 'Xem',
    this.style = const XPromoStyle(),
    this.padding = EdgeInsets.zero,
  });

  final String placement;
  final String label;
  final String actionLabel;
  final XPromoStyle style;
  final EdgeInsetsGeometry padding;

  @override
  State<XPromoCard> createState() => _XPromoCardState();
}

class _XPromoCardState extends State<XPromoCard> {
  PromoApp? _app;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final x = XPromo.instance;
    if (x == null) return;
    final app = await x.nextCard();
    if (!mounted || app == null) return;
    setState(() => _app = app);
    x.onCardShown(app, widget.placement);
  }

  @override
  Widget build(BuildContext context) {
    final x = XPromo.instance;
    final app = _app;
    if (x == null || app == null || _hidden) return const SizedBox.shrink();
    final s = widget.style;
    return Padding(
      padding: widget.padding,
      child: Container(
        decoration: BoxDecoration(
          color: s.card(context),
          borderRadius: BorderRadius.circular(s.radius),
          border: Border.all(color: s.border(context)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(widget.label, style: TextStyle(fontSize: 11, color: s.muted(context)))),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 18, color: s.muted(context)),
                  onPressed: () {
                    setState(() => _hidden = true);
                    x.dismiss(app, widget.placement);
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(
                children: [
                  XPromoIcon(app: app, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: s.text(context)),
                        ),
                        if (app.tagline.isNotEmpty)
                          Text(
                            app.tagline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: s.muted(context), height: 1.3),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => x.open(app, widget.placement),
                    style: FilledButton.styleFrom(
                      backgroundColor: s.accent(context),
                      foregroundColor: s.onAccent(context),
                    ),
                    child: Text(widget.actionLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
