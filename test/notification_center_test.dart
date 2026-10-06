import 'package:almaworks/notifications/app_notification.dart';
import 'package:almaworks/notifications/notification_providers.dart';
import 'package:almaworks/notifications/notification_router.dart';
import 'package:flutter_test/flutter_test.dart';

AppNotification _n(String type, {bool read = false}) => AppNotification(
  id: type,
  collection: NotificationSources.user,
  title: 't',
  body: 'b',
  payload: {'type': type},
  createdAt: DateTime(2026, 10, 2, 9),
  isRead: read,
);

void main() {
  test('categorizes every notification family', () {
    expect(AppNotification.categoryForType('safety_training_attempt'), NotificationCategory.safety);
    expect(AppNotification.categoryForType('project_date_extension_requested'), NotificationCategory.projects);
    expect(AppNotification.categoryForType('schedule_overdue'), NotificationCategory.projects);
    expect(AppNotification.categoryForType('inventory_checkout_request'), NotificationCategory.inventory);
    expect(AppNotification.categoryForType('communication'), NotificationCategory.messages);
    expect(AppNotification.categoryForType('client_request'), NotificationCategory.access);
    expect(AppNotification.categoryForType('something_new'), NotificationCategory.other);
  });

  test('day labels', () {
    final now = DateTime(2026, 10, 2, 15);
    expect(notificationDayLabel(DateTime(2026, 10, 2, 8), now), 'Today');
    expect(notificationDayLabel(DateTime(2026, 10, 1, 23), now), 'Yesterday');
    expect(notificationDayLabel(DateTime(2026, 9, 29), now), 'Tuesday');
    expect(notificationDayLabel(DateTime(2026, 9, 1), now), '1 Sep');
    expect(notificationDayLabel(DateTime(2025, 9, 1), now), '1 Sep 2025');
  });

  test('filters', () {
    final unreadSafety = _n('safety_training_review');
    final readInventory = _n('inventory_overdue_return', read: true);
    expect(const UnreadNotifications().matches(unreadSafety), isTrue);
    expect(const UnreadNotifications().matches(readInventory), isFalse);
    expect(const CategoryNotifications(NotificationCategory.inventory).matches(readInventory), isTrue);
    expect(const CategoryNotifications(NotificationCategory.inventory).matches(unreadSafety), isFalse);
  });

  test('only payloads with somewhere to go are openable', () {
    expect(NotificationRouter.hasDestination({'type': 'safety_training_feedback'}), isTrue);
    expect(NotificationRouter.hasDestination({'type': 'inventory_overdue_return', 'assetId': 'a1'}), isTrue);
    expect(NotificationRouter.hasDestination({'type': 'inventory_overdue_return'}), isFalse);
    expect(NotificationRouter.hasDestination({'type': 'communication', 'messageId': 'm', 'projectId': 'p'}), isTrue);
    expect(
      NotificationRouter.hasDestination({'type': 'project_date_extension_approved', 'projectId': 'null'}),
      isFalse,
    );
    expect(NotificationRouter.hasDestination({'type': 'client_request'}), isFalse);
    expect(NotificationRouter.hasDestination({'type': 'client_request', 'requestId': 'r1'}), isTrue);
  });
}
