import SwiftUI
import UniformTypeIdentifiers
import CNCRepeatJobEngine

struct CNCFeatureProvider: FeatureCanvasProviding {
    let bench: BenchAppModel
    func makeCanvas(for destination: ShellDestination, context: FeatureCanvasContext) -> AnyView {
        AnyView(CNCFeatureCanvas(destination: destination, context: context, bench: bench))
    }
}

private struct CNCFeatureCanvas: View {
    let destination: ShellDestination
    let context: FeatureCanvasContext
    let bench: BenchAppModel
    var body: some View {
        Group {
            switch destination.id {
            case "jobs": JobsCanvas(bench: bench, onUpgrade: context.requestUpgrade)
            case "run": RunCanvas(bench: bench)
            case "setups": SetupsCanvas(bench: bench, onUpgrade: context.requestUpgrade)
            case "records": RecordsCanvas(bench: bench)
            default: ContentUnavailableView("Unknown section", systemImage: "questionmark.square")
            }
        }
        .task { await bench.load() }
        .alert("Cannot record this action", isPresented: Binding(
            get: { bench.errorMessage != nil }, set: { if !$0 { bench.dismissError() } }
        )) { Button("OK", role: .cancel) { bench.dismissError() } }
          message: { Text(bench.errorMessage ?? "") }
    }
}

private extension Checkpoint {
    var title: LocalizedStringKey { LocalizedStringKey("cnc.checkpoint.\(rawValue)") }
}
private extension RunStatus {
    var title: LocalizedStringKey { LocalizedStringKey("cnc.status.\(rawValue)") }
}
private extension PieceDisposition {
    var title: LocalizedStringKey { LocalizedStringKey("cnc.disposition.\(rawValue)") }
}
private extension Audit {
    var displayTitle: LocalizedStringKey {
        let known: Set<String> = ["draftSetup", "reviseDraft", "setInspectionPolicy", "approveSetup",
            "replaceDrawing", "approveCoexistingDrawing", "start", "confirm", "measure", "review",
            "recordCount", "requestInspection", "measureInspection", "reviewInspection", "correctCount",
            "change", "authorizeDeviation", "acknowledgeHandoff", "reassignHandoff", "issue", "resolve",
            "handoff", "attach", "proposeSetup", "close", "abort", "setLocale", "archiveRuns",
            "restoreArchive"]
        return known.contains(action) ? LocalizedStringKey("cnc.audit.\(action)") : "Action recorded"
    }
}

private struct JobsCanvas: View {
    let bench: BenchAppModel
    let onUpgrade: () -> Void
    @Environment(ShellModel.self) private var shell
    @State private var isStarting = false
    var body: some View {
        List {
            Section {
                Button { isStarting = true } label: {
                    Label("Start repeat job", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.borderedProminent)
                if bench.operatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    TextField("Operator name", text: Binding(get: { bench.operatorName }, set: { bench.operatorName = $0 }))
                        .textContentType(.name)
                }
            }
            Section { Button("Pro · More part and machine families", action: onUpgrade) }
            Section("Open jobs") {
                if bench.activeRuns.isEmpty {
                    ContentUnavailableView("No open jobs", systemImage: "tray", description: Text("Approve a setup, then start the next repeat job."))
                }
                ForEach(bench.activeRuns, id: \.id) { run in
                    Button {
                        bench.selectedRunID = run.id
                        shell.selectedDestination = "run"
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(run.job).font(.headline); Spacer(); Text(run.status.title).font(.subheadline).foregroundStyle(run.status == .held ? .orange : .secondary) }
                            Text("\(run.part) · \(run.drawing) · \(run.machine)").font(.subheadline).foregroundStyle(.secondary)
                            Text("\(run.count(.good)) of \(run.targetGood) good").font(.footnote).foregroundStyle(.secondary)
                        }.contentShape(Rectangle()).frame(minHeight: 55)
                    }.buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $isStarting) { NavigationStack { StartJobForm(bench: bench, isPresented: $isStarting) } }
    }
}

private struct StartJobForm: View {
    let bench: BenchAppModel
    @Environment(ShellModel.self) private var shell
    @Binding var isPresented: Bool
    @State private var setupID: UUID?
    @State private var job = ""
    @State private var target = ""
    var body: some View {
        Form {
            Section("Approved setup") {
                Picker("Part · drawing · machine", selection: $setupID) {
                    Text("Choose a setup").tag(UUID?.none)
                    ForEach(bench.approvedSetups, id: \.id) { setup in
                        Text("\(setup.part) · \(setup.drawing) · \(setup.machine)").tag(Optional(setup.id))
                    }
                }
            }
            Section("Job") {
                TextField("Work order", text: $job)
                TextField("Target good parts", text: $target).keyboardType(.numberPad)
                TextField("Operator name", text: Binding(get: { bench.operatorName }, set: { bench.operatorName = $0 }))
                    .textContentType(.name)
            }
            Section { Text("The run starts in preparation. Confirm six observed references before measuring the first piece.").font(.footnote) }
        }
        .navigationTitle("Start repeat job")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Start") {
                    guard let setupID, let setup = bench.state.setups[setupID], let targetGood = Int(target) else { return }
                    Task {
                        let previousIDs = Set(bench.state.runs.keys)
                        if await bench.perform(.start(job: job, part: setup.part, drawing: setup.drawing,
                                                      machine: setup.machine, setupID: setupID, targetGood: targetGood)) {
                            bench.selectedRunID = bench.state.runs.keys.first { !previousIDs.contains($0) }
                            isPresented = false
                            shell.selectedDestination = "run"
                        }
                    }
                }
                .disabled(bench.busy || setupID == nil || job.trimmingCharacters(in: .whitespaces).isEmpty || (Int(target) ?? 0) <= 0)
            }
        }
    }
}

private struct SetupsCanvas: View {
    let bench: BenchAppModel
    let onUpgrade: () -> Void
    @State private var creating = false
    var body: some View {
        List {
            Section { Button { creating = true } label: { Label("New setup draft", systemImage: "plus.circle.fill").frame(maxWidth: .infinity, minHeight: 48) }.buttonStyle(.borderedProminent) }
            Section { Button("Pro · More part and machine families", action: onUpgrade) }
            Section("Drafts requiring approval") {
                if bench.draftSetups.isEmpty { Text("No drafts").foregroundStyle(.secondary) }
                ForEach(bench.draftSetups, id: \.id) { setup in
                    NavigationLink { SetupDetail(bench: bench, setupID: setup.id) } label: {
                        VStack(alignment: .leading) { Text("\(setup.part) · \(setup.drawing)").font(.headline); Text("\(setup.machine) · setup \(setup.revision)").foregroundStyle(.secondary) }
                    }
                }
            }
            Section("Approved for repeat use") {
                if bench.approvedSetups.isEmpty { Text("No approved setups").foregroundStyle(.secondary) }
                ForEach(bench.approvedSetups, id: \.id) { setup in
                    NavigationLink { SetupDetail(bench: bench, setupID: setup.id) } label: {
                        VStack(alignment: .leading) { Text("\(setup.part) · \(setup.drawing)").font(.headline); Text("\(setup.machine) · setup \(setup.revision)").foregroundStyle(.secondary) }
                    }
                }
            }
        }.listStyle(.insetGrouped)
            .sheet(isPresented: $creating) { NavigationStack { DraftSetupForm(bench: bench, isPresented: $creating) } }
    }
}

private struct DraftSetupForm: View {
    let bench: BenchAppModel
    let editingSetup: Setup?
    @Binding var isPresented: Bool
    @State private var part = ""
    @State private var drawing = ""
    @State private var machine = ""
    @State private var revision = ""
    @State private var notes = ""
    @State private var references: [Checkpoint: String] = [:]
    @State private var dimensions: [Dimension] = []
    @State private var code = "D1"
    @State private var nominal = ""
    @State private var minus = ""
    @State private var plus = ""
    @State private var unit = "mm"

    init(bench: BenchAppModel, editingSetup: Setup? = nil, isPresented: Binding<Bool>) {
        self.bench = bench
        self.editingSetup = editingSetup
        _isPresented = isPresented
    }

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Part", text: $part).disabled(editingSetup != nil)
                TextField("Drawing revision", text: $drawing).disabled(editingSetup != nil)
                TextField("Machine", text: $machine).disabled(editingSetup != nil)
                TextField("Setup revision", text: $revision).disabled(editingSetup != nil)
            }
            Section("Approved reference values") {
                ForEach(Checkpoint.allCases, id: \.self) { checkpoint in
                    TextField(checkpoint.title, text: Binding(
                        get: { references[checkpoint] ?? "" }, set: { references[checkpoint] = $0 }
                    ))
                }
            }
            Section("Dimensions") {
                ForEach(dimensions, id: \.code) { d in
                    HStack { Text(d.code); Spacer(); Text("\(d.nominal) −\(d.minus) / +\(d.plus) \(d.unit)").foregroundStyle(.secondary) }
                }.onDelete { dimensions.remove(atOffsets: $0) }
                TextField("Dimension code", text: $code)
                TextField("Nominal", text: $nominal).keyboardType(.decimalPad)
                TextField("Minus tolerance", text: $minus).keyboardType(.decimalPad)
                TextField("Plus tolerance", text: $plus).keyboardType(.decimalPad)
                TextField("Unit", text: $unit)
                Button("Add dimension") {
                    dimensions.append(Dimension(code: code, nominal: nominal, minus: minus, plus: plus, unit: unit))
                    code = ""; nominal = ""; minus = ""; plus = ""
                }.disabled(code.isEmpty || nominal.isEmpty || minus.isEmpty || plus.isEmpty || unit.isEmpty || dimensions.count >= 100)
            }
            Section { TextField("Setup notes", text: $notes, axis: .vertical) }
            Section { Text("A lead must select an inspection policy before approving this draft.").font(.footnote) }
        }
        .navigationTitle(editingSetup == nil ? "Setup draft" : "Edit draft")
        .onAppear {
            guard let editingSetup else { return }
            part = editingSetup.part; drawing = editingSetup.drawing; machine = editingSetup.machine
            revision = editingSetup.revision; notes = editingSetup.notes
            references = editingSetup.expected; dimensions = editingSetup.dimensions
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save draft") {
                    Task {
                        let command: BenchCommand = editingSetup.map { .reviseDraft(setupID: $0.id, expected: references,
                            dimensions: dimensions, notes: notes) } ?? .draftSetup(part: part, drawing: drawing,
                                machine: machine, revision: revision, expected: references,
                                dimensions: dimensions, notes: notes)
                        if await bench.perform(command) { isPresented = false }
                    }
                }.disabled(bench.busy || part.isEmpty || drawing.isEmpty || machine.isEmpty || revision.isEmpty || dimensions.isEmpty || Checkpoint.allCases.contains { (references[$0] ?? "").isEmpty })
            }
        }
    }
}

private struct SetupDetail: View {
    let bench: BenchAppModel
    let setupID: UUID
    @State private var showingApproval = false
    @State private var showingEdit = false
    var body: some View {
        Group {
            if let setup = bench.state.setups[setupID] {
                List {
                    Section("Identity") {
                        LabeledContent("Part", value: setup.part)
                        LabeledContent("Drawing", value: setup.drawing)
                        LabeledContent("Machine", value: setup.machine)
                        LabeledContent("Setup revision", value: setup.revision)
                    }
                    Section("Six preparation references") {
                        ForEach(Checkpoint.allCases, id: \.self) { checkpoint in
                            LabeledContent { Text(setup.expected[checkpoint] ?? "—") } label: { Text(checkpoint.title) }
                        }
                    }
                    Section("Dimensions") {
                        ForEach(setup.dimensions, id: \.code) { dimension in
                            LabeledContent(dimension.code, value: "\(dimension.nominal) −\(dimension.minus) / +\(dimension.plus) \(dimension.unit)")
                        }
                    }
                    Section("Inspection policy") {
                        if let policy = bench.state.inspectionPolicies[setupID] {
                            Text(policy.everyGood.map { "Every \($0) good parts" } ?? "Manual inspections only")
                            if !policy.reason.isEmpty { Text(policy.reason).foregroundStyle(.secondary) }
                        } else { Text("No policy chosen").foregroundStyle(.secondary) }
                    }
                    if setup.status == .draft {
                        Section {
                            Button("Edit draft") { showingEdit = true }.frame(maxWidth: .infinity, minHeight: 44)
                            Button("Set policy and approve") { showingApproval = true }.frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                }.listStyle(.insetGrouped)
                    .navigationTitle("Approved setup")
                    .sheet(isPresented: $showingApproval) { NavigationStack { ApproveSetupForm(bench: bench, setupID: setupID, isPresented: $showingApproval) } }
                    .sheet(isPresented: $showingEdit) { NavigationStack { DraftSetupForm(bench: bench, editingSetup: setup, isPresented: $showingEdit) } }
            } else { ContentUnavailableView("Setup unavailable", systemImage: "wrench.adjustable") }
        }
    }
}

private struct ApproveSetupForm: View {
    let bench: BenchAppModel
    let setupID: UUID
    @Binding var isPresented: Bool
    @State private var interval = ""
    @State private var reason = ""
    @State private var manualOnly = false
    @State private var drawingChoice = "replace"
    @State private var drawingReason = ""
    var body: some View {
        Form {
            Section("Inspection during production") {
                Toggle("Manual inspections only", isOn: $manualOnly)
                if !manualOnly { TextField("Every N good parts", text: $interval).keyboardType(.numberPad) }
                TextField("Reason for this policy", text: $reason, axis: .vertical)
            }
            if let setup = bench.state.setups[setupID] {
                let others = bench.approvedSetups.filter { $0.part == setup.part && $0.machine == setup.machine && $0.drawing != setup.drawing }
                if !others.isEmpty {
                    Section("Another drawing is approved") {
                        Picker("Decision", selection: $drawingChoice) {
                            Text("Replace prior drawing").tag("replace")
                            Text("Keep both drawings").tag("coexist")
                        }
                        if drawingChoice == "replace" { Text("Existing drawing: \(others.map(\.drawing).joined(separator: ", "))") }
                        TextField("Decision reason", text: $drawingReason, axis: .vertical)
                    }
                }
            }
            Section { Text("Lead approval is a named assertion. The app cannot verify shop authority or measurements.").font(.footnote) }
        }
        .navigationTitle("Approve setup")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Approve") {
                    Task {
                        let every = manualOnly ? nil : Int(interval)
                        guard await bench.perform(.setDraftInspectionPolicy(setupID: setupID, everyGood: every, reason: reason)) else { return }
                        guard let setup = bench.state.setups[setupID] else { return }
                        let others = bench.approvedSetups.filter { $0.part == setup.part && $0.machine == setup.machine && $0.drawing != setup.drawing }
                        let command: BenchCommand
                        if others.isEmpty { command = .approveSetup(setupID: setupID) }
                        else if drawingChoice == "coexist" { command = .approveCoexistingDrawing(setupID: setupID, reason: drawingReason) }
                        else if others.count == 1 { command = .replaceDrawing(setupID: setupID, previousDrawing: others[0].drawing, reason: drawingReason) }
                        else { bench.show(BenchError.blocked("Several drawings are approved; choose coexistence or resolve the existing drawing first.")); return }
                        if await bench.perform(command) { isPresented = false }
                    }
                }.disabled(bench.busy || reason.trimmingCharacters(in: .whitespaces).isEmpty || (!manualOnly && (Int(interval) ?? 0) <= 0) ||
                    (bench.state.setups[setupID].map { setup in bench.approvedSetups.contains { $0.part == setup.part && $0.machine == setup.machine && $0.drawing != setup.drawing } } == true && drawingReason.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
    }
}

private struct RunCanvas: View {
    let bench: BenchAppModel
    @State private var observed: [Checkpoint: String] = [:]
    @State private var readings: [String: String] = [:]
    @State private var reviewer = ""
    @State private var reviewReason = ""
    @State private var countReason = ""
    @State private var countQuantity = "1"
    @State private var disposition: PieceDisposition = .good
    @State private var handoffTo = ""
    @State private var handoffNote = ""
    @State private var closeReason = ""
    @State private var issueResolution: [UUID: String] = [:]
    @State private var correctionQuantity: [UUID: String] = [:]
    @State private var correctionReason: [UUID: String] = [:]
    @State private var showClose = false
    @State private var showAbort = false
    @State private var showActions = false
    @State private var changeCheckpoint: Checkpoint = .offsets
    @State private var changeValue = ""
    @State private var changeReviewer = ""
    @State private var changeReason = ""
    @State private var issueDetail = ""
    @State private var reassignTo = ""
    @State private var reassignReason = ""
    @State private var proposedRevision = ""
    @State private var proposedNotes = ""
    @State private var repeatReason = ""
    @State private var importingAttachment = false

    var body: some View {
        Group {
            if let run = bench.selectedRun, let setup = bench.state.setups[run.setupID] {
                List {
                    if bench.activeRuns.count > 1 {
                        Section("Choose run") {
                            Picker("Active job", selection: Binding(
                                get: { bench.selectedRunID ?? run.id }, set: { bench.selectedRunID = $0 }
                            )) {
                                ForEach(bench.activeRuns, id: \.id) { candidate in
                                    Text("\(candidate.job) · \(candidate.part)").tag(candidate.id)
                                }
                            }
                        }
                    }
                    Section {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("\(run.part) · \(run.job)").font(.title2.bold())
                            Text("\(run.drawing) · \(run.machine)").foregroundStyle(.secondary)
                            Label(run.status.title, systemImage: run.status == .held ? "exclamationmark.octagon.fill" : "gearshape.2")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(run.status == .held ? Color.orange : ShellConfiguration.tint)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                    }
                    if run.handoffs.last?.acknowledgedAt == nil, let last = run.handoffs.last {
                        Section("Handoff waiting") {
                            TextField("Current operator", text: Binding(get: { bench.operatorName }, set: { bench.operatorName = $0 }))
                            Text("For \(last.to) · \(last.note)")
                            Button("Acknowledge as \(last.to)") { Task { await bench.perform(.acknowledgeHandoff(runID: run.id)) } }
                                .disabled(bench.busy || bench.operatorName != last.to)
                            Text("The named recipient must enter their own operator name before acknowledging.").font(.footnote).foregroundStyle(.secondary)
                            TextField("Reassign to", text: $reassignTo)
                            TextField("Reassignment reason", text: $reassignReason)
                            Button("Reassign handoff") {
                                Task { await bench.perform(.reassignHandoff(runID: run.id, to: reassignTo, reason: reassignReason)) }
                            }.disabled(bench.busy || reassignTo.isEmpty || reassignReason.isEmpty)
                        }
                    } else {
                        if run.status == .preparing || (run.status == .held && run.pendingInspection == nil && run.changes.isEmpty && Checkpoint.allCases.contains { run.confirmations[$0]?.matches != true }) { preparation(run) }
                        if run.status == .firstPiece { firstPiece(run, setup: setup) }
                        if run.status == .running || run.status == .paused { production(run) }
                        if run.pendingInspection != nil { inspection(run, setup: setup) }
                        if run.status == .held && run.pendingInspection == nil {
                            Section("Hold") { Text(run.unresolvedIssues.isEmpty ? "Review the changed setup before continuing." : "Resolve the recorded issue before continuing.") }
                        }
                        if !run.unresolvedIssues.isEmpty { issues(run) }
                        if !run.counts.isEmpty && run.pendingInspection == nil { corrections(run) }
                        if run.status == .held, let change = run.changes.last, run.deviations[Checkpoint(rawValue: change.kind) ?? .offsets]?.changeID != change.id { changeApproval(run, change: change) }
                        if run.status != .closed && run.status != .aborted {
                            Section { Button("More run actions") { showActions = true } }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .sheet(isPresented: $showActions) {
                    NavigationStack {
                        Form { moreActions(run) }
                            .navigationTitle("Run actions")
                            .toolbar { ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showActions = false }
                            } }
                            .confirmationDialog("Close this run?", isPresented: $showClose) {
                                Button("Close run") { Task { if await bench.perform(.close(runID: run.id, reason: closeReason)) { showActions = false } } }
                            } message: { Text("Good count and quarantine must reconcile before closeout.") }
                            .confirmationDialog("Abort this run?", isPresented: $showAbort) {
                                Button("Abort run", role: .destructive) { Task { if await bench.perform(.abort(runID: run.id, reason: closeReason)) { showActions = false } } }
                            } message: { Text("The run remains in Records with its audit history.") }
                    }
                }
                .fileImporter(isPresented: $importingAttachment, allowedContentTypes: [.jpeg, .png, .pdf]) { result in
                    do {
                        let url = try result.get()
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let bytes = try Data(contentsOf: url)
                        let mime: String = switch url.pathExtension.lowercased() {
                        case "jpg", "jpeg": "image/jpeg"
                        case "png": "image/png"
                        case "pdf": "application/pdf"
                        default: ""
                        }
                        Task { await bench.perform(.attach(runID: run.id, filename: url.lastPathComponent,
                                                          mimeType: mime, bytes: bytes)) }
                    } catch { bench.show(error) }
                }
            } else {
                ContentUnavailableView("No active run", systemImage: "gearshape.2", description: Text("Start a job from an approved setup in Jobs."))
            }
        }
    }

    private func preparation(_ run: Run) -> some View {
        Section("Check the physical setup") {
            Text("Observe each reference on the machine. A mismatch opens a hold; correct it, then resolve the issue explicitly.")
                .font(.footnote).foregroundStyle(.secondary)
            ForEach(Checkpoint.allCases, id: \.self) { checkpoint in
                VStack(alignment: .leading, spacing: 5) {
                    Text(checkpoint.title).font(.headline)
                    Text("Approved: \(run.deviations[checkpoint]?.runReference ?? run.confirmations[checkpoint]?.expected ?? bench.state.setups[run.setupID]?.expected[checkpoint] ?? "—")")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if run.confirmations[checkpoint]?.matches == true {
                        Label("Confirmed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        TextField("Observed reference", text: Binding(
                            get: { observed[checkpoint] ?? "" }, set: { observed[checkpoint] = $0 }
                        ))
                        Button { 
                            Task { await bench.perform(.confirm(runID: run.id, checkpoint: checkpoint, observed: observed[checkpoint] ?? "")) }
                        } label: { Text("Confirm ") + Text(checkpoint.title) }
                        .disabled(bench.busy || (observed[checkpoint] ?? "").isEmpty)
                    }
                }.padding(.vertical, 3)
            }
        }
    }

    private func firstPiece(_ run: Run, setup: Setup) -> some View {
        Section("First-piece measurements") {
            Text("Enter the measured value for each dimension. Acceptance requires a named reviewer and all readings within tolerance.")
                .font(.footnote).foregroundStyle(.secondary)
            ForEach(setup.dimensions, id: \.code) { d in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(d.code) · \(d.nominal) −\(d.minus) / +\(d.plus) \(d.unit)").font(.headline)
                    if let prior = run.firstPiece.observations[d.code] {
                        Text("Recorded: \(prior.value) \(d.unit)").foregroundStyle(prior.withinTolerance ? .green : .orange)
                        TextField("New observed reading", text: Binding(get: { readings[d.code] ?? "" }, set: { readings[d.code] = $0 }))
                            .keyboardType(.decimalPad)
                        TextField("Repeat reason", text: $repeatReason)
                        Button("Repeat measurement") {
                            Task { await bench.perform(.repeatMeasurement(runID: run.id, code: d.code,
                                value: readings[d.code] ?? "", reason: repeatReason)) }
                        }.disabled(bench.busy || (readings[d.code] ?? "").isEmpty || repeatReason.isEmpty)
                    } else {
                        TextField("Observed \(d.unit)", text: Binding(get: { readings[d.code] ?? "" }, set: { readings[d.code] = $0 }))
                            .keyboardType(.decimalPad)
                        Button("Record measurement") { Task { await bench.perform(.measure(runID: run.id, code: d.code, value: readings[d.code] ?? "")) } }
                            .disabled(bench.busy || (readings[d.code] ?? "").isEmpty)
                    }
                }.padding(.vertical, 3)
            }
            TextField("Reviewer name", text: $reviewer)
            TextField("Reason if rejected", text: $reviewReason)
            Button("Accept first piece") {
                Task { await bench.perform(.review(runID: run.id, decision: .accept, reviewer: reviewer, reason: "")) }
            }.buttonStyle(.borderedProminent)
                .disabled(bench.busy || reviewer.isEmpty || setup.dimensions.contains { run.firstPiece.observations[$0.code]?.withinTolerance != true })
            Button("Reject and hold") {
                Task { await bench.perform(.review(runID: run.id, decision: .reject, reviewer: reviewer, reason: reviewReason)) }
            }.disabled(bench.busy || reviewer.isEmpty || reviewReason.isEmpty)
        }
    }

    private func production(_ run: Run) -> some View {
        Section("Production count") {
            HStack {
                LabeledContent("Good", value: "\(run.count(.good)) / \(run.targetGood)")
            }
            HStack { LabeledContent("Scrap", value: "\(run.count(.scrap))"); LabeledContent("Quarantine", value: "\(run.count(.quarantine))") }
            if let next = run.nextInspectionGood { Text("Next required check: \(next) good").font(.subheadline).foregroundStyle(.secondary) }
            if run.status == .running {
                Picker("Disposition", selection: $disposition) {
                    Text("Good").tag(PieceDisposition.good)
                    Text("Scrap").tag(PieceDisposition.scrap)
                    Text("Quarantine").tag(PieceDisposition.quarantine)
                }
                TextField("Quantity", text: $countQuantity).keyboardType(.numberPad)
                TextField("Reason (required for scrap/quarantine)", text: $countReason)
                Button("Record count") {
                    guard let quantity = Int(countQuantity) else { return }
                    Task { await bench.perform(.recordCount(runID: run.id, disposition: disposition, quantity: quantity, reason: countReason)) }
                }.buttonStyle(.borderedProminent)
                    .disabled(bench.busy || (Int(countQuantity) ?? 0) <= 0 || (disposition != .good && countReason.isEmpty))
                Button("Request manual inspection") { Task { await bench.perform(.requestInspection(runID: run.id, reason: "Operator requested a check")) } }
                Button("Pause run") { Task { await bench.perform(.pause(runID: run.id)) } }
            } else {
                Button("Resume production") { Task { await bench.perform(.resume(runID: run.id)) } }
                    .buttonStyle(.borderedProminent).disabled(bench.busy)
            }
        }
    }

    private func inspection(_ run: Run, setup: Setup) -> some View {
        Section("Inspection hold · \(run.pendingInspection?.dueGood ?? run.count(.good)) good") {
            Text("Measure every approved dimension. Production resumes only after a named acceptance, then a separate Resume tap.")
                .font(.footnote).foregroundStyle(.secondary)
            ForEach(setup.dimensions, id: \.code) { d in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(d.code) · \(d.nominal) −\(d.minus) / +\(d.plus) \(d.unit)").font(.headline)
                    if let prior = run.pendingInspection?.observations[d.code] {
                        Text("Recorded: \(prior.value) \(d.unit)").foregroundStyle(prior.withinTolerance ? .green : .orange)
                        TextField("New observed reading", text: Binding(get: { readings[d.code] ?? "" }, set: { readings[d.code] = $0 }))
                            .keyboardType(.decimalPad)
                        TextField("Repeat reason", text: $repeatReason)
                        Button("Repeat inspection reading") {
                            Task { await bench.perform(.measureInspection(runID: run.id, code: d.code,
                                value: readings[d.code] ?? "", repeatReason: repeatReason)) }
                        }.disabled(bench.busy || (readings[d.code] ?? "").isEmpty || repeatReason.isEmpty)
                    } else {
                        TextField("Observed \(d.unit)", text: Binding(get: { readings[d.code] ?? "" }, set: { readings[d.code] = $0 }))
                            .keyboardType(.decimalPad)
                        Button("Record inspection reading") {
                            Task { await bench.perform(.measureInspection(runID: run.id, code: d.code, value: readings[d.code] ?? "", repeatReason: nil)) }
                        }.disabled(bench.busy || (readings[d.code] ?? "").isEmpty)
                    }
                }.padding(.vertical, 3)
            }
            TextField("Reviewer name", text: $reviewer)
            TextField("Rejection reason", text: $reviewReason)
            Button("Accept inspection") {
                Task { await bench.perform(.reviewInspection(runID: run.id, decision: .accept, reviewer: reviewer, reason: "")) }
            }.buttonStyle(.borderedProminent)
                .disabled(bench.busy || reviewer.isEmpty || setup.dimensions.contains { run.pendingInspection?.observations[$0.code]?.withinTolerance != true })
            Button("Reject inspection") {
                Task { await bench.perform(.reviewInspection(runID: run.id, decision: .reject, reviewer: reviewer, reason: reviewReason)) }
            }.disabled(bench.busy || reviewer.isEmpty || reviewReason.isEmpty)
        }
    }

    private func issues(_ run: Run) -> some View {
        Section("Open issues") {
            ForEach(run.unresolvedIssues, id: \.id) { issue in
                VStack(alignment: .leading, spacing: 5) {
                    Text(issue.detail).font(.subheadline)
                    TextField("Verified resolution", text: Binding(
                        get: { issueResolution[issue.id] ?? "" }, set: { issueResolution[issue.id] = $0 }
                    ))
                    Button("Resolve issue") {
                        Task { await bench.perform(.resolve(runID: run.id, issueID: issue.id, resolution: issueResolution[issue.id] ?? "")) }
                    }.disabled(bench.busy || (issueResolution[issue.id] ?? "").isEmpty)
                }.padding(.vertical, 3)
            }
        }
    }

    private func corrections(_ run: Run) -> some View {
        Section("Correct a recorded count") {
            ForEach(run.counts.filter { original in
                original.delta > 0 && original.corrects == nil &&
                    !run.counts.contains { $0.corrects == original.id }
            }, id: \.id) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(entry.delta) ") + Text(entry.disposition.title) + Text(" · \(entry.actor)")
                    TextField("Correct total", text: Binding(get: { correctionQuantity[entry.id] ?? "" },
                                                           set: { correctionQuantity[entry.id] = $0 }))
                        .keyboardType(.numberPad)
                    TextField("Correction reason", text: Binding(get: { correctionReason[entry.id] ?? "" },
                                                              set: { correctionReason[entry.id] = $0 }))
                    Button("Record correction") {
                        guard let quantity = Int(correctionQuantity[entry.id] ?? "") else { return }
                        Task { await bench.perform(.correctCount(runID: run.id, entryID: entry.id,
                            replacementQuantity: quantity, reason: correctionReason[entry.id] ?? "")) }
                    }.disabled(bench.busy || Int(correctionQuantity[entry.id] ?? "") == nil || (correctionReason[entry.id] ?? "").isEmpty)
                }.padding(.vertical, 4)
            }
        }
    }

    private func changeApproval(_ run: Run, change: Change) -> some View {
        Section("Changed preparation reference") {
            Text("\(change.kind): \(change.detail)")
            TextField("Reviewer name", text: $changeReviewer)
            TextField("Approval reason", text: $changeReason)
            Button("Approve run-specific deviation") {
                guard let checkpoint = Checkpoint(rawValue: change.kind) else { return }
                Task { await bench.perform(.authorizeDeviation(runID: run.id, changeID: change.id,
                    checkpoint: checkpoint, observed: change.detail, reviewer: changeReviewer, reason: changeReason)) }
            }.disabled(bench.busy || changeReviewer.isEmpty || changeReason.isEmpty)
        }
    }

    private func moreActions(_ run: Run) -> some View {
        Section("Run exceptions") {
            TextField("Issue detail", text: $issueDetail)
            Button("Open issue and hold") { Task { await bench.perform(.issue(runID: run.id, detail: issueDetail)) } }
                .disabled(bench.busy || issueDetail.isEmpty)
            Button("Attach photo or PDF") { importingAttachment = true }
            TextField("Proposed next setup revision", text: $proposedRevision)
            TextField("Proposed setup notes", text: $proposedNotes)
            Button("Propose draft from this run") {
                guard let setup = bench.state.setups[run.setupID] else { return }
                Task { await bench.perform(.proposeSetup(runID: run.id, revision: proposedRevision,
                    expected: setup.expected, dimensions: setup.dimensions, notes: proposedNotes)) }
            }.disabled(bench.busy || proposedRevision.isEmpty)
        }
        Section("Process reference change") {
            Picker("Changed reference", selection: $changeCheckpoint) {
                ForEach(Checkpoint.allCases, id: \.self) { key in Text(key.title).tag(key) }
            }
            TextField("New observed reference", text: $changeValue)
            Button("Log change and hold") { Task { await bench.perform(.change(runID: run.id, kind: changeCheckpoint.rawValue, detail: changeValue)) } }
                .disabled(bench.busy || changeValue.isEmpty)
        }
        Section("Handoff and closeout") {
            TextField("Next operator", text: $handoffTo)
            TextField("Shift note", text: $handoffNote)
            Button("Hand off shift") { Task { await bench.perform(.handoff(runID: run.id, to: handoffTo, note: handoffNote)) } }
                .disabled(bench.busy || handoffTo.isEmpty)
            if run.status == .running || run.status == .paused {
                TextField("Closeout reason", text: $closeReason)
                Button("Close reconciled run") { showClose = true }.disabled(bench.busy || closeReason.isEmpty || run.count(.quarantine) != 0)
            }
            if run.status != .closed && run.status != .aborted {
                TextField("Abort reason", text: $closeReason)
                Button("Abort run", role: .destructive) { showAbort = true }.disabled(bench.busy || closeReason.isEmpty)
            }
        }
    }
}

private struct RecordsCanvas: View {
    let bench: BenchAppModel
    @State private var shareURL: URL?
    @State private var importedBackup: Data?
    @State private var importedArchive: Data?
    @State private var choosingBackup = false
    @State private var choosingArchive = false
    @State private var confirmingRestore = false
    @State private var confirmingArchive = false
    @State private var confirmingArchiveRestore = false
    @State private var selectedReceiptID: UUID?

    var body: some View {
        List {
            Section("Share a factual record") {
                Button { prepare { try bench.exportCSV() } } label: { Label("Runs CSV", systemImage: "tablecells") }
                Button { Task { do { shareURL = try await bench.exportBackup() } catch { bench.show(error) } } } label: {
                    Label("Local JSON backup", systemImage: "externaldrive")
                }
                if let run = bench.selectedRun {
                    Button { prepare { try bench.exportHandoff(runID: run.id, pdf: true) } } label: {
                        Label("Selected run handoff PDF", systemImage: "doc.richtext")
                    }
                }
                if let shareURL { ShareLink(item: shareURL) { Label("Share prepared file", systemImage: "square.and.arrow.up") } }
            }
            Section("Restore") {
                Button { choosingBackup = true } label: { Label("Choose JSON backup", systemImage: "square.and.arrow.down") }
                Text("Restore replaces this device's live database. Review the file and confirm before applying it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Verified archive") {
                if !bench.completedRuns.isEmpty {
                    Button("Archive completed runs") { confirmingArchive = true }
                }
                if !bench.state.archiveReceipts.isEmpty {
                    Picker("Archive receipt", selection: $selectedReceiptID) {
                        Text("Choose receipt").tag(UUID?.none)
                        ForEach(bench.state.archiveReceipts, id: \.id) { receipt in
                            Text("\(receipt.filename) · \(receipt.runIDs.count) runs").tag(Optional(receipt.id))
                        }
                    }
                    Button("Choose archive to restore") { choosingArchive = true }
                        .disabled(selectedReceiptID == nil)
                }
                Text("Keep each archive file together with the JSON backup; the receipt alone cannot restore its jobs.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Completed runs") {
                if bench.completedRuns.isEmpty { Text("No completed runs yet").foregroundStyle(.secondary) }
                ForEach(bench.completedRuns, id: \.id) { run in
                    NavigationLink { RunRecordDetail(bench: bench, runID: run.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(run.job) · \(run.part)").font(.headline)
                            Text("\(run.drawing) · \(run.machine)").font(.subheadline).foregroundStyle(.secondary)
                            Text(run.status.title).font(.footnote).foregroundStyle(.secondary)
                        }.padding(.vertical, 3)
                    }
                }
            }
            Section("Audit") {
                ForEach(Array(bench.state.audit.suffix(30).reversed()), id: \.operationID) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.displayTitle).font(.subheadline.weight(.semibold))
                        Text("\(event.actor) · \(event.at.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                importedBackup = try Data(contentsOf: url)
                confirmingRestore = true
            } catch { bench.show(error) }
        }
        .fileImporter(isPresented: $choosingArchive, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                importedArchive = try Data(contentsOf: url)
                confirmingArchiveRestore = true
            } catch { bench.show(error) }
        }
        .confirmationDialog("Archive completed runs?", isPresented: $confirmingArchive) {
            Button("Create verified archive") {
                Task { shareURL = await bench.archive(bench.completedRuns.map(\.id)) }
            }
        } message: { Text("The verified file is retained on this device. Share and keep it with the JSON backup before relying on an external copy.") }
        .confirmationDialog("Restore these archived runs?", isPresented: $confirmingArchiveRestore) {
            Button("Restore matching archive") {
                guard let selectedReceiptID, let importedArchive else { return }
                Task { await bench.restoreArchive(importedArchive, receiptID: selectedReceiptID) }
                self.importedArchive = nil
            }
        } message: { Text("The file must match the selected receipt's checksum and run IDs.") }
        .confirmationDialog("Replace this device's live records?", isPresented: $confirmingRestore) {
            Button("Restore backup", role: .destructive) {
                guard let importedBackup else { return }
                Task { await bench.restoreBackup(importedBackup) }
                self.importedBackup = nil
            }
        } message: { Text("The engine validates the backup before replacing local records. Archived files must be kept separately.") }
    }
    private func prepare(_ make: () throws -> URL) { do { shareURL = try make() } catch { bench.show(error) } }
}

private struct RunRecordDetail: View {
    let bench: BenchAppModel
    let runID: UUID
    @State private var shareURL: URL?
    var body: some View {
        Group {
            if let run = bench.state.runs[runID], let setup = bench.state.setups[run.setupID] {
                List {
                    Section("Recorded outcome") {
                        LabeledContent("Job", value: run.job)
                        LabeledContent("Part and drawing", value: "\(run.part) · \(run.drawing)")
                        LabeledContent("Good", value: "\(run.count(.good))")
                        LabeledContent("Scrap", value: "\(run.count(.scrap))")
                        LabeledContent("Quarantine", value: "\(run.count(.quarantine))")
                    }
                    Section("Reviews") {
                        LabeledContent("First piece", value: run.firstPiece.reviewer ?? "Not accepted")
                        LabeledContent("In-process checks", value: "\((run.inspections ?? []).count)")
                        LabeledContent("Handoffs", value: "\(run.handoffs.count)")
                    }
                    Section("Handoff") {
                        Button("Prepare PDF") {
                            do { shareURL = try bench.exportHandoff(runID: runID, pdf: true) }
                            catch { bench.show(error) }
                        }
                        if let shareURL { ShareLink(item: shareURL) { Text("Share handoff") } }
                        Text(BenchExport.handoff(run, setup: setup)).font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                }.listStyle(.insetGrouped).navigationTitle(run.job)
            }
        }
    }
}
