import SwiftUI

struct CanaryView: View {
    @ObservedObject var model: CanaryViewModel

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bubbl iOS Canary")
                            .font(.title.bold())
                        Text(model.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(model.statusText)
                        .font(.headline)
                        .foregroundStyle(model.passed ? .green : model.failed ? .red : .blue)
                        .accessibilityIdentifier(model.passed ? "canary-status-passed" : model.failed ? "canary-status-failed" : "canary-status-running")

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.steps) { step in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.title)
                                    .font(.body.weight(.semibold))
                                    .accessibilityIdentifier(step.accessibilityIdentifier)
                                Text(step.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

@MainActor
final class CanaryViewModel: ObservableObject {
    @Published var statusText = "Running canary"
    @Published var summary = "Booting the local SDK package inside an app runtime."
    @Published var steps: [CanaryStep] = []
    @Published var passed = false
    @Published var failed = false

    private var hasRun = false

    func runIfNeeded() async {
        guard !hasRun else { return }
        hasRun = true

        do {
            let report = try await CanaryRunner().run()
            steps = report.steps
            summary = report.summary
            statusText = "Canary Passed"
            passed = true
            failed = false
        } catch {
            summary = String(describing: error)
            statusText = "Canary Failed"
            passed = false
            failed = true
            steps.append(
                CanaryStep(
                    title: "Failure",
                    detail: String(describing: error),
                    accessibilityIdentifier: "canary-step-failure"
                )
            )
        }
    }
}

struct CanaryStep: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String
    let accessibilityIdentifier: String
}
