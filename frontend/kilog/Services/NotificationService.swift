import Foundation
import UserNotifications

/// 아침·점심·저녁 식사 영상 리마인더 (로컬 알림, 매일 반복)
enum NotificationService {
    private static let ids = [
        "kilog.meal.morning", "kilog.meal.lunch", "kilog.meal.evening",
    ]

    /// 권한 요청 후 매일 반복되는 식사 알림 3개 등록.
    /// 같은 identifier로 다시 등록하면 교체되므로 중복 걱정 없이 매번 호출해도 된다.
    static func scheduleMealReminders() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(
            options: [.alert, .sound, .badge]
        )) ?? false
        guard granted else { return }

        let plans: [(id: String, hour: Int, minute: Int, title: String, body: String)] = [
            ("kilog.meal.morning", 8, 0,
             "좋은 아침 ☀️", "아침 먹는 모습, 식사 영상으로 공유해 주세요~"),
            ("kilog.meal.lunch", 11, 30,
             "점심시간 🍚", "오늘 점심은 뭐예요? 식사 영상 공유해 주세요~"),
            ("kilog.meal.evening", 18, 0,
             "저녁이에요 🌙", "저녁 식사 영상 공유해 주세요~ 오늘의 마지막 컷!"),
        ]

        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default

            var date = DateComponents()
            date.hour = plan.hour
            date.minute = plan.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)

            try? await center.add(UNNotificationRequest(
                identifier: plan.id, content: content, trigger: trigger
            ))
        }
    }

    static func cancelMealReminders() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ids)
    }
}
