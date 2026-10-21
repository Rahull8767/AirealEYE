import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerial_eye/models/notification.dart';

class NotificationNotifier extends StateNotifier<List<AppNotification>> {
  NotificationNotifier()
    : super([
        AppNotification(
          id: 'not_1',
          title: 'Drone Arming Safe',
          body: 'MAVLink Pre-Arm checks complete. All systems nominal.',
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
          type: NotificationType.success,
          isRead: false,
        ),
        AppNotification(
          id: 'not_2',
          title: 'Low Battery Alert',
          body: 'Battery voltage at 14.8V (20%). Please monitor RTL threshold.',
          timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
          type: NotificationType.warning,
          isRead: false,
        ),
        AppNotification(
          id: 'not_3',
          title: 'Map Sync Complete',
          body: 'Offline cache loaded for Bay Area inspection zone.',
          timestamp: DateTime.now().subtract(const Duration(hours: 1)),
          type: NotificationType.info,
          isRead: true,
        ),
      ]);

  void addNotification(String title, String body, NotificationType type) {
    final newNot = AppNotification(
      id: 'not_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      body: body,
      timestamp: DateTime.now(),
      type: type,
      isRead: false,
    );
    state = [newNot, ...state];
  }

  void markAsRead(String id) {
    state = state
        .map((n) => n.id == id ? n.copyWith(isRead: true) : n)
        .toList();
  }

  void markAllAsRead() {
    state = state.map((n) => n.copyWith(isRead: true)).toList();
  }

  void clearAll() {
    state = [];
  }
}

final notificationProvider =
    StateNotifierProvider<NotificationNotifier, List<AppNotification>>((ref) {
      return NotificationNotifier();
    });
