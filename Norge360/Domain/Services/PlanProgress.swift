import Foundation

enum PlanProgress {
    static func completedTasks(in tasks: [RelocationTask]) -> Int {
        tasks.count(where: { $0.status == .completed })
    }
}
