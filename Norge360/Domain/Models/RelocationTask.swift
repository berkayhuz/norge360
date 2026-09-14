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

struct RelocationTaskDefinition: Codable, Sendable, Equatable {
    static let currentContentVersion = 1
    static let currentRulesVersion = 1

    let id: UUID
    let slug: String
    let titleKey: String?
    let legacyTitle: String?
    let taskDescriptionKey: String?
    let legacyTaskDescription: String?
    let category: TaskCategory
    let priority: Int
    let dependencies: [String]
    let officialSource: OfficialSource
    let regulatoryDisclaimerKey: String?
    let legacyRegulatoryDisclaimer: String?
    let contentVersion: Int
    let rulesVersion: Int

    init(
        id: UUID = UUID(), slug: String, titleKey: String, taskDescriptionKey: String,
        category: TaskCategory, priority: Int, dependencies: [String] = [],
        officialSource: OfficialSource, regulatoryDisclaimerKey: String? = nil,
        contentVersion: Int = RelocationTaskDefinition.currentContentVersion,
        rulesVersion: Int = RelocationTaskDefinition.currentRulesVersion
    ) {
        self.id = id
        self.slug = slug
        self.titleKey = titleKey
        legacyTitle = nil
        self.taskDescriptionKey = taskDescriptionKey
        legacyTaskDescription = nil
        self.category = category
        self.priority = priority
        self.dependencies = dependencies
        self.officialSource = officialSource
        self.regulatoryDisclaimerKey = regulatoryDisclaimerKey
        legacyRegulatoryDisclaimer = nil
        self.contentVersion = contentVersion
        self.rulesVersion = rulesVersion
    }

    init(
        id: UUID, slug: String, legacyTitle: String, legacyTaskDescription: String,
        category: TaskCategory, priority: Int, dependencies: [String],
        officialSource: OfficialSource, legacyRegulatoryDisclaimer: String?,
        contentVersion: Int = 0, rulesVersion: Int = 0
    ) {
        self.id = id
        self.slug = slug
        titleKey = nil
        self.legacyTitle = legacyTitle
        taskDescriptionKey = nil
        self.legacyTaskDescription = legacyTaskDescription
        self.category = category
        self.priority = priority
        self.dependencies = dependencies
        self.officialSource = officialSource
        regulatoryDisclaimerKey = nil
        self.legacyRegulatoryDisclaimer = legacyRegulatoryDisclaimer
        self.contentVersion = contentVersion
        self.rulesVersion = rulesVersion
    }

    var title: String {
        localizedValue(key: titleKey, fallback: legacyTitle)
    }

    var taskDescription: String {
        localizedValue(key: taskDescriptionKey, fallback: legacyTaskDescription)
    }

    var regulatoryDisclaimer: String? {
        guard let key = regulatoryDisclaimerKey else { return legacyRegulatoryDisclaimer }
        let localized = AppStrings.localized(key)
        return localized == key ? legacyRegulatoryDisclaimer : localized
    }

    func replacingID(_ id: UUID) -> RelocationTaskDefinition {
        RelocationTaskDefinition(
            id: id,
            slug: slug,
            titleKey: titleKey,
            legacyTitle: legacyTitle,
            taskDescriptionKey: taskDescriptionKey,
            legacyTaskDescription: legacyTaskDescription,
            category: category,
            priority: priority,
            dependencies: dependencies,
            officialSource: officialSource,
            regulatoryDisclaimerKey: regulatoryDisclaimerKey,
            legacyRegulatoryDisclaimer: legacyRegulatoryDisclaimer,
            contentVersion: contentVersion,
            rulesVersion: rulesVersion
        )
    }

    private init(
        id: UUID, slug: String, titleKey: String?, legacyTitle: String?,
        taskDescriptionKey: String?, legacyTaskDescription: String?, category: TaskCategory,
        priority: Int, dependencies: [String], officialSource: OfficialSource,
        regulatoryDisclaimerKey: String?, legacyRegulatoryDisclaimer: String?,
        contentVersion: Int, rulesVersion: Int
    ) {
        self.id = id
        self.slug = slug
        self.titleKey = titleKey
        self.legacyTitle = legacyTitle
        self.taskDescriptionKey = taskDescriptionKey
        self.legacyTaskDescription = legacyTaskDescription
        self.category = category
        self.priority = priority
        self.dependencies = dependencies
        self.officialSource = officialSource
        self.regulatoryDisclaimerKey = regulatoryDisclaimerKey
        self.legacyRegulatoryDisclaimer = legacyRegulatoryDisclaimer
        self.contentVersion = contentVersion
        self.rulesVersion = rulesVersion
    }

    private func localizedValue(key: String?, fallback: String?) -> String {
        guard let key else { return fallback ?? "" }
        let localized = AppStrings.localized(key)
        return localized == key ? (fallback ?? localized) : localized
    }
}

struct RelocationTaskProgress: Codable, Sendable, Equatable {
    private(set) var status: TaskStatus
    private(set) var completedAt: Date?

    init(status: TaskStatus = .notStarted, completedAt: Date? = nil) {
        self.status = status
        self.completedAt = status == .completed ? completedAt : nil
    }

    mutating func setStatus(_ newStatus: TaskStatus, now: Date = .now) {
        status = newStatus
        completedAt = newStatus == .completed ? now : nil
    }
}

struct RelocationTask: Identifiable, Codable, Sendable, Equatable {
    let definition: RelocationTaskDefinition
    private(set) var progress: RelocationTaskProgress

    var id: UUID { definition.id }
    var slug: String { definition.slug }
    var title: String { definition.title }
    var taskDescription: String { definition.taskDescription }
    var category: TaskCategory { definition.category }
    var priority: Int { definition.priority }
    var dependencies: [String] { definition.dependencies }
    var officialSource: OfficialSource { definition.officialSource }
    var regulatoryDisclaimer: String? { definition.regulatoryDisclaimer }
    var status: TaskStatus { progress.status }
    var completedAt: Date? { progress.completedAt }

    init(definition: RelocationTaskDefinition, progress: RelocationTaskProgress = .init()) {
        self.definition = definition
        self.progress = progress
    }

    init(
        id: UUID = UUID(), slug: String, titleKey: String, taskDescriptionKey: String,
        category: TaskCategory, priority: Int, dependencies: [String] = [],
        officialSource: OfficialSource, regulatoryDisclaimerKey: String? = nil,
        status: TaskStatus = .notStarted, completedAt: Date? = nil
    ) {
        definition = RelocationTaskDefinition(
            id: id,
            slug: slug,
            titleKey: titleKey,
            taskDescriptionKey: taskDescriptionKey,
            category: category,
            priority: priority,
            dependencies: dependencies,
            officialSource: officialSource,
            regulatoryDisclaimerKey: regulatoryDisclaimerKey
        )
        progress = RelocationTaskProgress(status: status, completedAt: completedAt)
    }

    init(
        id: UUID = UUID(), slug: String, title: String, taskDescription: String,
        category: TaskCategory, priority: Int, dependencies: [String] = [],
        officialSource: OfficialSource, regulatoryDisclaimer: String? = nil,
        status: TaskStatus = .notStarted, completedAt: Date? = nil
    ) {
        definition = RelocationTaskDefinition(
            id: id,
            slug: slug,
            legacyTitle: title,
            legacyTaskDescription: taskDescription,
            category: category,
            priority: priority,
            dependencies: dependencies,
            officialSource: officialSource,
            legacyRegulatoryDisclaimer: regulatoryDisclaimer
        )
        progress = RelocationTaskProgress(status: status, completedAt: completedAt)
    }

    mutating func setStatus(_ newStatus: TaskStatus, now: Date = .now) {
        progress.setStatus(newStatus, now: now)
    }

    func replacingID(_ id: UUID) -> RelocationTask {
        RelocationTask(definition: definition.replacingID(id), progress: progress)
    }

    func withProgress(from task: RelocationTask) -> RelocationTask {
        RelocationTask(definition: definition, progress: task.progress)
    }

    private enum CodingKeys: String, CodingKey {
        case definition
        case progress
        case id
        case slug
        case title
        case taskDescription
        case category
        case priority
        case dependencies
        case officialSource
        case regulatoryDisclaimer
        case status
        case completedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let definition = try container.decodeIfPresent(RelocationTaskDefinition.self, forKey: .definition) {
            self.definition = definition
            progress = try container.decodeIfPresent(RelocationTaskProgress.self, forKey: .progress) ?? .init()
            return
        }

        let id = try container.decode(UUID.self, forKey: .id)
        let slug = try container.decode(String.self, forKey: .slug)
        let title = try container.decode(String.self, forKey: .title)
        let taskDescription = try container.decode(String.self, forKey: .taskDescription)
        let category = try container.decode(TaskCategory.self, forKey: .category)
        let priority = try container.decode(Int.self, forKey: .priority)
        let dependencies = try container.decodeIfPresent([String].self, forKey: .dependencies) ?? []
        let officialSource = try container.decode(OfficialSource.self, forKey: .officialSource)
        let regulatoryDisclaimer = try container.decodeIfPresent(String.self, forKey: .regulatoryDisclaimer)
        let status = try container.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .notStarted
        let completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)

        definition = RelocationTaskDefinition(
            id: id,
            slug: slug,
            legacyTitle: title,
            legacyTaskDescription: taskDescription,
            category: category,
            priority: priority,
            dependencies: dependencies,
            officialSource: officialSource,
            legacyRegulatoryDisclaimer: regulatoryDisclaimer
        )
        progress = RelocationTaskProgress(status: status, completedAt: completedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(definition, forKey: .definition)
        try container.encode(progress, forKey: .progress)
    }
}

struct RelocationPlan: Codable, Sendable, Equatable {
    let profile: RelocationProfile
    var tasks: [RelocationTask]

    var completedCount: Int { tasks.count(where: { $0.status == .completed }) }
    var progressFraction: Double { tasks.isEmpty ? 0 : Double(completedCount) / Double(tasks.count) }
}
