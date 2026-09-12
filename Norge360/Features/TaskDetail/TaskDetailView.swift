import SwiftUI

struct TaskDetailView: View {
    @EnvironmentObject private var appState: AppState
    let task: RelocationTask

    var body: some View {
        List {
            Section { Text(task.taskDescription).fixedSize(horizontal: false, vertical: true) }
                .listRowBackground(Color.norgeAppBackground)
            Section(AppStrings.taskStatus) {
                Picker(AppStrings.taskStatus, selection: statusBinding) {
                    ForEach(TaskStatus.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(AppStrings.taskStatus)
            }
            .listRowBackground(Color.norgeAppBackground)
            Section(AppStrings.officialSource) {
                Text(task.officialSource.name).font(.headline)
                if let url = task.officialSource.url { Link(url.absoluteString, destination: url) }
                if let verified = task.officialSource.lastVerifiedAt {
                    Text("\(AppStrings.sourceLastVerified): \(verified.formatted(date: .abbreviated, time: .omitted))")
                }
                if let note = task.officialSource.verificationNote {
                    Label(note, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.norgeAppBackground)
            if let disclaimer = task.regulatoryDisclaimer {
                Section { Label(disclaimer, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary) }
                    .listRowBackground(Color.norgeAppBackground)
            }
        }
        .norgeScreen()
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusBinding: Binding<TaskStatus> {
        Binding(get: { task.status }, set: { appState.updateStatus($0, for: task.id) })
    }
}
