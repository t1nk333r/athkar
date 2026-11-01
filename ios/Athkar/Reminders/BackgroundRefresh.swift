import BackgroundTasks
import Foundation

/// `ReminderRefreshScheduler` on iOS's `BGTaskScheduler` (NATIVE_APP_PLAN.md §7.5). The app's scene runs the task
/// (`.backgroundTask(.appRefresh(…))` in `AthkarApp`); iOS decides whether and when, from how the app is used.
@MainActor
final class AppRefreshScheduler: ReminderRefreshScheduler {
    func submit(earliestBegin: Date) throws {
        let request = BGAppRefreshTaskRequest(identifier: ReminderModel.refreshTaskIdentifier)
        request.earliestBeginDate = earliestBegin
        // A request with the same identifier replaces the one already pending.
        try BGTaskScheduler.shared.submit(request)
    }
}
