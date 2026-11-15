import SwiftUI
import AppKit

@main
struct AncientOCRApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("正心OCR") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 880, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

enum OCRProfile: String, CaseIterable, Identifiable {
    case modern = "modern"
    case complex = "complex"
    case ancient = "ancient"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modern: return "普通扫描"
        case .complex: return "复杂排版"
        case .ancient: return "古籍正本"
        }
    }

    var detail: String {
        switch self {
        case .modern: return "PP-OCRv6：现代印刷体与规整扫描件"
        case .complex: return "PP-StructureV3：多栏、表格、公式和图文混排"
        case .ancient: return "PaddleOCR-VL 1.6：竖排、夹注、生僻字与印章"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var inputPath = ""
    @Published var outputPath = ""
    @Published var selectedProfile: OCRProfile = .ancient
    @Published var environmentSummary = "正在检查本地环境…"
    @Published var jobSummary = "尚未提交任务"
    @Published var logText = ""
    @Published var progress = 0.0
    @Published var isBusy = false
    @Published var jobID: String?

    private var pollTimer: Timer?

    init() {
        Task { await refreshEnvironment() }
    }

    deinit {
        pollTimer?.invalidate()
    }

    private var cliPath: String {
        Bundle.main.resourceURL!
            .appendingPathComponent("bin/localocr")
            .path
    }

    func chooseInput() {
        let panel = NSOpenPanel()
        panel.title = "选择要识别的PDF或图像"
        panel.allowedContentTypes = [.pdf, .png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            inputPath = url.path
            if outputPath.isEmpty {
                outputPath = url.deletingLastPathComponent()
                    .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-OCR结果")
                    .path
            }
        }
    }

    func chooseOutput() {
        let panel = NSOpenPanel()
        panel.title = "选择结果保存目录"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            outputPath = url.path
        }
    }

    func refreshEnvironment() async {
        let result = await runCLI(["doctor", "--json"])
        environmentSummary = result.summary
        appendLog(result.output)
    }

    func prepareRuntime() {
        guard !isBusy else { return }
        isBusy = true
        jobSummary = "正在创建外部运行环境并安装依赖，这可能需要较长时间…"
        Task {
            let result = await runCLI(["setup-runtime"])
            appendLog(result.output)
            isBusy = false
            await refreshEnvironment()
        }
    }

    func prepareModels() {
        guard !isBusy else { return }
        isBusy = true
        jobSummary = "正在下载模型到用户数据目录，请保持联网…"
        Task {
            let result = await runCLI(["setup-models"])
            appendLog(result.output)
            isBusy = false
            await refreshEnvironment()
        }
    }

    func submit() {
        guard !inputPath.isEmpty, !outputPath.isEmpty, !isBusy else { return }
        isBusy = true
        jobSummary = "正在提交任务…"
        Task {
            let result = await runCLI([
                "submit", inputPath,
                "--profile", selectedProfile.rawValue,
                "--output", outputPath,
                "--start",
                "--json"
            ])
            appendLog(result.output)
            if let data = result.output.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = object["job_id"] as? String {
                jobID = id
                jobSummary = "任务已提交：\(id)"
                startPolling()
            } else {
                jobSummary = result.summary
                isBusy = false
            }
        }
    }

    func cancel() {
        guard let id = jobID else { return }
        Task {
            let result = await runCLI(["cancel", id, "--json"])
            appendLog(result.output)
            await pollStatus()
        }
    }

    func revealOutput() {
        guard !outputPath.isEmpty else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: outputPath)
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.pollStatus() }
        }
        Task { await pollStatus() }
    }

    private func pollStatus() async {
        guard let id = jobID else { return }
        let result = await runCLI(["status", id, "--json"])
        guard let data = result.output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            jobSummary = result.summary
            return
        }
        let status = object["status"] as? String ?? "unknown"
        let done = object["completed_pages"] as? Int ?? 0
        let total = object["total_pages"] as? Int ?? 0
        let failed = object["failed_pages"] as? Int ?? 0
        progress = total > 0 ? Double(done) / Double(total) : 0
        jobSummary = "状态：\(status)　页数：\(done)/\(total)　失败：\(failed)"
        if ["completed", "failed", "cancelled"].contains(status) {
            pollTimer?.invalidate()
            isBusy = false
        }
    }

    private func appendLog(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        logText += (logText.isEmpty ? "" : "\n") + text
        if logText.count > 30_000 {
            logText = String(logText.suffix(30_000))
        }
    }

    private func runCLI(_ arguments: [String]) async -> (output: String, summary: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cliPath)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.terminationHandler = { process in
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let summary = process.terminationStatus == 0 ? "操作完成" : "操作失败（\(process.terminationStatus)）"
                    continuation.resume(returning: (output, summary))
                }
            } catch {
                continuation.resume(returning: ("\(error)", "无法启动本地OCR工具"))
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List {
                Label("识别任务", systemImage: "doc.text.viewfinder")
                Label("环境与模型", systemImage: "cpu")
                Label("使用说明", systemImage: "questionmark.circle")
            }
            .navigationTitle("正心OCR")
            .frame(minWidth: 190)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    environmentCard
                    fileCard
                    profileCard
                    actionCard
                    logCard
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("文献识别")
                .font(.system(size: 28, weight: .semibold))
            Text("原生Apple Silicon应用 · 模型与结果留在本机 · 16GB串行优化")
                .foregroundStyle(.secondary)
        }
    }

    private var environmentCard: some View {
        GroupBox("运行环境") {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.environmentSummary)
                    .textSelection(.enabled)
                HStack {
                    Button("重新检查") { Task { await model.refreshEnvironment() } }
                    Button("安装运行依赖") { model.prepareRuntime() }
                        .disabled(model.isBusy)
                    Button("下载本地模型") { model.prepareModels() }
                        .disabled(model.isBusy)
                }
                Text("基于PaddleOCR开发")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private var fileCard: some View {
        GroupBox("输入与输出") {
            VStack(spacing: 12) {
                pathRow(title: "输入文件", value: model.inputPath, button: "选择PDF或图像", action: model.chooseInput)
                pathRow(title: "输出目录", value: model.outputPath, button: "选择目录", action: model.chooseOutput)
            }
            .padding(6)
        }
    }

    private func pathRow(title: String, value: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value.isEmpty ? "尚未选择" : value)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            Button(button, action: action)
        }
    }

    private var profileCard: some View {
        GroupBox("识别模式") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("模式", selection: $model.selectedProfile) {
                    ForEach(OCRProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .pickerStyle(.segmented)
                Text(model.selectedProfile.detail)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
        }
    }

    private var actionCard: some View {
        GroupBox("任务状态") {
            VStack(alignment: .leading, spacing: 12) {
                ProgressView(value: model.progress)
                Text(model.jobSummary).textSelection(.enabled)
                HStack {
                    Button("开始识别") { model.submit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.inputPath.isEmpty || model.outputPath.isEmpty || model.isBusy)
                    Button("取消") { model.cancel() }
                        .disabled(model.jobID == nil || !model.isBusy)
                    Button("在Finder中显示结果") { model.revealOutput() }
                        .disabled(model.outputPath.isEmpty)
                }
            }
            .padding(6)
        }
    }

    private var logCard: some View {
        GroupBox("运行记录") {
            ScrollView {
                Text(model.logText.isEmpty ? "暂无记录" : model.logText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .frame(minHeight: 130, maxHeight: 220)
        }
    }
}
