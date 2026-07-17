import SwiftUI
import UniformTypeIdentifiers

// MARK: - Import Wizard

/// 多步骤导入向导：支持文件选择、WiFi传输、扫描、OPDS 四种导入方式。
public struct ImportWizardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep: ImportStep = .welcome
    @State private var selectedMethod: ImportMethod?
    @State private var importProgress: Double = 0
    @State private var importedCount = 0
    @State private var isImporting = false
    @State private var wifiServerURL: URL?

    let onComplete: ([Book]) -> Void

    public init(onComplete: @escaping ([Book]) -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            VStack {
                // 步骤指示器
                StepIndicator(currentStep: currentStep)

                // 内容区
                ScrollView {
                    switch currentStep {
                    case .welcome:
                        welcomeView
                    case .chooseMethod:
                        methodPicker
                    case .importing:
                        importingView
                    case .complete:
                        completeView
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: currentStep)

                // 底部按钮
                bottomBar
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if currentStep != .complete {
                        Button("取消") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 32)

            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue.gradient)

            Text("欢迎使用 DuckReader")
                .font(.title.bold())

            Text("让我们帮你把藏书快速导入进来\n选择最方便的方式开始阅读")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "doc.badge.plus", title: "支持格式", desc: "EPUB, PDF, CBZ, CBR, TXT, ZIP")
                FeatureRow(icon: "icloud.and.arrow.down", title: "多种导入方式", desc: "文件/Finder、WiFi传输、扫描、OPDS")
                FeatureRow(icon: "books.vertical", title: "自动管理", desc: "元数据抓取、系列分组、进度同步")
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Method Picker

    private var methodPicker: some View {
        VStack(spacing: 16) {
            Text("选择导入方式")
                .font(.headline)

            ForEach(ImportMethod.allCases) { method in
                MethodCard(method: method, isSelected: selectedMethod == method) {
                    selectedMethod = method
                }
            }
        }
        .padding()
    }

    // MARK: - Importing

    private var importingView: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 20)

            if let method = selectedMethod {
                Image(systemName: method.icon)
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text(method.importingDescription)
                    .font(.headline)
            }

            ProgressView(value: importProgress) {
                HStack {
                    Text("已导入 \(importedCount) 本")
                    Spacer()
                    Text("\(Int(importProgress * 100))%")
                }
                .font(.caption)
            }
            .padding(.horizontal, 32)

            if let url = wifiServerURL {
                VStack(spacing: 8) {
                    Text("在浏览器中打开以下地址上传文件：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(url.absoluteString)
                        .font(.headline.monospaced())
                        .padding(12)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }
                .padding()
            }

            Spacer()
        }
    }

    // MARK: - Complete

    private var completeView: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 32)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("导入完成")
                .font(.title.bold())

            Text("成功导入 \(importedCount) 本书籍")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Text("接下来你可以：")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Label("开始阅读第一本书", systemImage: "book.pages")
                Label("扫描库获取更多书籍", systemImage: "doc.viewfinder")
                Label("设置同步和备份", systemImage: "arrow.triangle.2.circlepath")
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            Spacer()
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            switch currentStep {
            case .welcome:
                Button("开始导入") {
                    currentStep = .chooseMethod
                }
                .buttonStyle(.borderedProminent)

            case .chooseMethod:
                Button("上一步") {
                    currentStep = .welcome
                }
                .buttonStyle(.plain)

                Button("开始导入") {
                    guard selectedMethod != nil else { return }
                    currentStep = .importing
                    Task { await performImport() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedMethod == nil)

            case .importing:
                EmptyView()

            case .complete:
                Button("开始阅读") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: - Nav Title

    private var navTitle: String {
        switch currentStep {
        case .welcome: return "导入向导"
        case .chooseMethod: return "选择导入方式"
        case .importing: return "正在导入..."
        case .complete: return "导入完成"
        }
    }

    // MARK: - Import Logic

    private func performImport() async {
        isImporting = true
        defer { isImporting = false }

        guard let method = selectedMethod else { return }

        switch method {
        case .files:
            // 文件选择通过系统文件选择器（由外部调用提供URLs）
            break

        case .wifi:
            // 启动WiFi传输服务器
            await startWiFiServer()

        case .scan:
            // 扫描在 ScanAssistant 中处理
            break

        case .calibre:
            // OPDS 浏览在 OPDSManager 中处理
            break
        }

        // 模拟导入完成（实际由各方法回调驱动）
        currentStep = .complete
    }

    private func startWiFiServer() async {
        // WiFi 传输由 NetworkBrowserService 管理
        // 这里提供占位URL
        wifiServerURL = URL(string: "http://localhost:8080")
    }
}

// MARK: - Import Method

public enum ImportMethod: String, Identifiable, CaseIterable {
    case files = "文件导入"
    case wifi = "WiFi传输"
    case scan = "扫描导入"
    case calibre = "Calibre/OPDS"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .files: return "doc.on.doc"
        case .wifi: return "wifi"
        case .scan: return "doc.viewfinder"
        case .calibre: return "externaldrive.connected.to.line.below"
        }
    }

    public var description: String {
        switch self {
        case .files: return "从文件App或Finder中选择EPUB/PDF/CBZ等文件"
        case .wifi: return "通过WiFi在电脑浏览器上传书籍"
        case .scan: return "用相机扫描实体书/文档为PDF"
        case .calibre: return "通过OPDS连接Calibre服务器下载"
        }
    }

    public var importingDescription: String {
        switch self {
        case .files: return "正在导入文件..."
        case .wifi: return "等待WiFi传输..."
        case .scan: return "正在扫描..."
        case .calibre: return "正在连接Calibre..."
        }
    }
}

// MARK: - Import Step

enum ImportStep {
    case welcome, chooseMethod, importing, complete
}

// MARK: - Step Indicator

struct StepIndicator: View {
    let currentStep: ImportStep

    private let steps: [(ImportStep, String)] = [
        (.welcome, "欢迎"),
        (.chooseMethod, "方式"),
        (.importing, "导入"),
        (.complete, "完成")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(steps.indices, id: \.self) { i in
                let (step, label) = steps[i]
                let isActive = stepIndex(step) <= stepIndex(currentStep)

                Circle()
                    .fill(isActive ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .overlay {
                        if stepIndex(step) < stepIndex(currentStep) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }

                if i < steps.count - 1 {
                    Rectangle()
                        .fill(isActive && stepIndex(step) < stepIndex(currentStep) ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 2)
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.top, 8)
    }

    private func stepIndex(_ step: ImportStep) -> Int {
        switch step {
        case .welcome: return 0
        case .chooseMethod: return 1
        case .importing: return 2
        case .complete: return 3
        }
    }
}

// MARK: - Method Card

struct MethodCard: View {
    let method: ImportMethod
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                Image(systemName: method.icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : .blue)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.blue : Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(method.rawValue)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(method.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .gray.opacity(0.4))
                    .font(.title3)
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.08) : Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let title: String
    let desc: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Empty Library State

/// 空书架状态视图：引导用户开始导入
public struct EmptyLibraryView: View {
    @State private var showImportWizard = false

    public init() {}

    public var body: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 20)

            Image(systemName: "books.vertical")
                .font(.system(size: 64))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 8) {
                Text("书架是空的")
                    .font(.title2.bold())
                Text("导入你的第一本书开始阅读之旅")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                QuickActionButton(
                    icon: "doc.badge.plus",
                    title: "从文件导入",
                    subtitle: "EPUB, PDF, CBZ, CBR, TXT",
                    action: { showImportWizard = true }
                )
                QuickActionButton(
                    icon: "wifi",
                    title: "WiFi传输",
                    subtitle: "在浏览器中上传书籍",
                    action: { showImportWizard = true }
                )
                QuickActionButton(
                    icon: "externaldrive.connected.to.line.below",
                    title: "连接Calibre",
                    subtitle: "通过OPDS同步",
                    action: { showImportWizard = true }
                )
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showImportWizard) {
            ImportWizardView(onComplete: { _ in
                showImportWizard = false
            })
        }
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
