import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import 'common.dart';

/// 显示服务端公告，返回用户点击的动作（open_url / dismiss / reload / ...）。
Future<String?> showAnnouncementDialog(
  BuildContext context,
  Announcement announcement,
) {
  final List<AnnouncementButton> visible = announcement.buttons
      .where((AnnouncementButton button) => button.isVisible)
      .toList(growable: false);

  return showDialog<String>(
    context: context,
    barrierDismissible: announcement.dismissible,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text(announcement.title.isEmpty ? '公告' : announcement.title),
      content: announcement.body.isEmpty
          ? null
          : SingleChildScrollView(
              child: Text(
                announcement.body,
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
            ),
      actions: <Widget>[
        ...visible.map(
          (AnnouncementButton button) => FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(button.action),
            child: Text(button.label),
          ),
        ),
        if (visible.isEmpty && announcement.dismissible)
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('dismiss'),
            child: const Text('知道了'),
          ),
      ],
    ),
  );
}

/// 执行公告按钮的动作。只认白名单，未知动作忽略。
Future<void> runAnnouncementAction(
  BuildContext context,
  String action,
  String target, {
  VoidCallback? onReload,
  VoidCallback? onAbout,
}) async {
  switch (action) {
    case 'open_url':
      if (target.trim().isNotEmpty) {
        final bool ok = await launchUrl(
          Uri.parse(target.trim()),
          mode: LaunchMode.externalApplication,
        );
        if (!ok && context.mounted) {
          showSnack(context, '没有可用的浏览器打开这个链接', error: true);
        }
      }
      break;
    case 'reload':
      onReload?.call();
      break;
    case 'open_about':
      onAbout?.call();
      break;
    case 'copy':
      if (target.trim().isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: target.trim()));
        if (context.mounted) showSnack(context, '已复制');
      }
      break;
    case 'dismiss':
    case 'none':
    default:
      break;
  }
}
