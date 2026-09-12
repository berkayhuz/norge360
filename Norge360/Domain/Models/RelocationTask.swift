import Foundation

enum TaskStatus: String, CaseIterable, Codable, Sendable, Identifiable {
    case notStarted, inProgress, completed
    var id: Self { self }
    var title: String { AppStrings.localized("task_status.\(rawValue)") }
}

enum TaskCategory: String, Codable, Sendable {
    case arrival, immigration, identity, employment, family
    var title: String { AppStrings.localized("task_category.\(rawValue)") }
    var symbolName: String {
        switch self {
        case .arrival: "airplane.arrival"
        case .immigration: "doc.text"
        case .identity: "person.text.rectangle"
        case .employment: "briefcase"
        case .family: "figure.2.and.child.holdinghands"
        }
    }
}

struct OfficialSource: Codable, Sendable, Equatable {
    let name: String
    /// Nil means the source has intentionally not been verified for release yet.
    let url: URL?
    let lastVerifiedAt: Date?
    let verificationNote: String?
}

struct RelocationTask: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let slug: String
    let title: String
    let taskDescription: String
    let category: TaskCategory
    let priority: Int
    let dependencies: [String]
    let officialSource: OfficialSource
    let regulatoryDisclaimer: String?
    private(set) var status: TaskStatus
    private(set) var completedAt: Date?

    init(
        id: UUID = UUID(), slug: String, title: String, taskDescription: String,
        category: TaskCategory, priority: Int, dependencies: [String] = [],
        officialSource: OfficialSource, regulatoryDisclaimer: String? = nil,
        status: TaskStatus = .notStarted, completedAt: Date? = nil
    ) {
        self.id = id
        self.slug = slug
        self.title = title
        self.taskDescription = taskDescription
        self.category = category
        self.priority = priority
        self.dependencies = dependencies
        self.officialSource = officialSource
        self.regulatoryDisclaimer = regulatoryDisclaimer
        self.status = status
        self.completedAt = completedAt
    }

    mutating func setStatus(_ newStatus: TaskStatus, now: Date = .now) {
        status = newStatus
        completedAt = newStatus == .completed ? now : nil
    }
}

struct RelocationPlan: Codable, Sendable, Equatable {
    let profile: RelocationProfile
    var tasks: [RelocationTask]

    var completedCount: Int { tasks.count(where: { $0.status == .completed }) }
    var progressFraction: Double { tasks.isEmpty ? 0 : Double(completedCount) / Double(tasks.count) }
}
