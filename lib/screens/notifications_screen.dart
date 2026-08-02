import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:aerial_eye/core/theme/app_theme.dart';
import 'package:aerial_eye/models/notification.dart';
import 'package:aerial_eye/providers/notification_provider.dart';
import 'package:aerial_eye/widgets/glass_panel.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationProvider);
    final notifier = ref.read(notificationProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications Panel'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (notifications.any((n) => !n.isRead))
            TextButton.icon(
              icon: const Icon(LucideIcons.checkSquare, size: 16, color: AppTheme.secondary),
              label: const Text('Mark all read', style: TextStyle(color: AppTheme.secondary, fontSize: 12)),
              onPressed: () => notifier.markAllAsRead(),
            ),
        ],
      ),
      body: notifications.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.bellOff, size: 48, color: AppTheme.textSecondary),
                  const SizedBox(height: 16),
                  Text(
                    'No new alerts or logs',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final n = notifications[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildNotificationTile(context, n, notifier),
                );
              },
            ),
    );
  }

  Widget _buildNotificationTile(BuildContext context, AppNotification n, NotificationNotifier notifier) {
    final iconColor = _iconColor(n.type);
    final icon = _icon(n.type);

    return GestureDetector(
      onTap: () => notifier.markAsRead(n.id),
      child: GlassPanel(
        padding: const EdgeInsets.all(16),
        color: n.isRead ? AppTheme.card.withOpacity(0.5) : AppTheme.card.withOpacity(0.85),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Icon with flash color background
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 14),

            // Content specs
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          style: TextStyle(
                            fontWeight: n.isRead ? FontWeight.bold : FontWeight.w900,
                            fontSize: 14,
                            color: n.isRead ? AppTheme.textPrimary.withOpacity(0.8) : Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!n.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: AppTheme.secondary, shape: BoxShape.circle),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    n.body,
                    style: TextStyle(
                      fontSize: 12,
                      color: n.isRead ? AppTheme.textSecondary : AppTheme.textPrimary.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${n.timestamp.hour.toString().padLeft(2, '0')}:${n.timestamp.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _iconColor(NotificationType type) {
    switch (type) {
      case NotificationType.critical:
        return AppTheme.danger;
      case NotificationType.warning:
        return AppTheme.warning;
      case NotificationType.success:
        return AppTheme.success;
      default:
        return AppTheme.secondary;
    }
  }

  IconData _icon(NotificationType type) {
    switch (type) {
      case NotificationType.critical:
        return LucideIcons.alertOctagon;
      case NotificationType.warning:
        return LucideIcons.alertTriangle;
      case NotificationType.success:
        return LucideIcons.checkCircle;
      default:
        return LucideIcons.info;
    }
  }
}
