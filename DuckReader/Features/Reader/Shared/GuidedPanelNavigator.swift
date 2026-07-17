import Foundation
import CoreGraphics

// MARK: - Guided Panel 阅读流导航
/// 基于已有 PanelDetector 的检测结果，生成推荐阅读路径
/// 支持漫画日漫(右→左)、欧美(左→右)、纵读(竖排)三种模式
/// 检测一次缓存，后续零额外消耗
@MainActor
final class GuidedPanelNavigator: ObservableObject {
    // MARK: - Config
    struct Config {
        /// 面板间跳转动画时长
        var transitionDuration: Double = 0.25
        /// 当前面板高亮边框宽度
        var highlightBorderWidth: CGFloat = 3
        /// 当前面板高亮颜色（Duck 主题色）
        var highlightColor: CGColor = UIColor.systemOrange.cgColor
        /// 自动滚动是否启用
        var autoScrollEnabled: Bool = true
        /// 超出视野时自动滚动边距 (归一化 0...1)
        var autoScrollMargin: CGFloat = 0.1
    }

    var config: Config = Config()

    // MARK: - Types
    enum ReadingDirection: String, CaseIterable, Codable, Sendable {
        case rightToLeft = "日漫 (右→左)"
        case leftToRight = "欧美 (左→右)"
        case topToBottom = "纵读 (上→下)"
    }

    struct PanelReadingPath: Sendable {
        let panels: [PanelRegion]
        let direction: ReadingDirection
        let totalPanels: Int
    }

    struct NavigationState {
        var currentPanelIndex: Int = 0
        var path: PanelReadingPath
        var isAutoScrolling: Bool = false
    }

    // MARK: - State
    @Published var currentIndex: Int = 0
    @Published var readingPath: PanelReadingPath?
    @Published var isActive: Bool = false

    private var direction: ReadingDirection = .rightToLeft
    private var pendingPath: PanelReadingPath?

    // MARK: - Public API

    /// 从面板检测结果生成阅读路径
    func buildPath(from panels: [PanelRegion], direction: ReadingDirection = .rightToLeft) -> PanelReadingPath {
        self.direction = direction
        let ordered = sortPanels(panels, direction: direction)
        let path = PanelReadingPath(
            panels: ordered,
            direction: direction,
            totalPanels: ordered.count
        )
        readingPath = path
        return path
    }

    /// 跳转到下一个面板
    func next() {
        guard let path = readingPath, currentIndex < path.totalPanels - 1 else { return }
        currentIndex += 1
    }

    /// 跳转到上一个面板
    func previous() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    /// 跳转到指定面板
    func jumpTo(index: Int) {
        guard let path = readingPath,
              index >= 0 && index < path.totalPanels else { return }
        currentIndex = index
    }

    /// 当前面板区域
    func currentPanel() -> PanelRegion? {
        guard let path = readingPath,
              currentIndex >= 0 && currentIndex < path.panels.count else { return nil }
        return path.panels[currentIndex]
    }

    /// 获取面板的中心点（用于自动滚动定位）
    func currentPanelCenter(in imageSize: CGSize) -> CGPoint? {
        guard let panel = currentPanel() else { return nil }
        let rect = panel.normalizedRect
        return CGPoint(
            x: rect.midX * imageSize.width,
            y: (1 - rect.midY) * imageSize.height  // CG 坐标系翻转
        )
    }

    /// 重置
    func reset() {
        currentIndex = 0
        readingPath = nil
        isActive = false
    }
}

// MARK: - Panel Sorting Algorithms

private extension GuidedPanelNavigator {

    /// 面板排序核心算法
    func sortPanels(_ panels: [PanelRegion], direction: ReadingDirection) -> [PanelRegion] {
        guard panels.count > 1 else { return panels }

        switch direction {
        case .rightToLeft:
            return sortRightToLeft(panels)
        case .leftToRight:
            return sortLeftToRight(panels)
        case .topToBottom:
            return sortTopToBottom(panels)
        }
    }

    /// 日漫排序：先按 Y 分组（行），组内从右到左
    func sortRightToLeft(_ panels: [PanelRegion]) -> [PanelRegion] {
        let rows = groupIntoRows(panels)
        var result: [PanelRegion] = []

        // 行从上到下
        for row in rows.sorted(by: { $0.minY < $1.minY }) {
            let sortedInRow = row.sorted { panelA, panelB in
                // 行内从右到左
                panelA.normalizedRect.maxX > panelB.normalizedRect.maxX
            }
            result.append(contentsOf: sortedInRow)
        }

        return result
    }

    /// 欧美排序：先按 Y 分组（行），组内从左到右
    func sortLeftToRight(_ panels: [PanelRegion]) -> [PanelRegion] {
        let rows = groupIntoRows(panels)
        var result: [PanelRegion] = []

        for row in rows.sorted(by: { $0.minY < $1.minY }) {
            let sortedInRow = row.sorted { panelA, panelB in
                panelA.normalizedRect.minX < panelB.normalizedRect.minX
            }
            result.append(contentsOf: sortedInRow)
        }

        return result
    }

    /// 纵读排序：从上到下
    func sortTopToBottom(_ panels: [PanelRegion]) -> [PanelRegion] {
        panels.sorted { a, b in
            if abs(a.normalizedRect.minY - b.normalizedRect.minY) < 0.05 {
                return a.normalizedRect.minX < b.normalizedRect.minX
            }
            return a.normalizedRect.minY < b.normalizedRect.minY
        }
    }

    /// 按 Y 轴分组 → 行
    func groupIntoRows(_ panels: [PanelRegion]) -> [[PanelRegion]] {
        let sorted = panels.sorted { $0.normalizedRect.minY < $1.normalizedRect.minY }

        var rows: [[PanelRegion]] = []
        var currentRow: [PanelRegion] = []

        for panel in sorted {
            if currentRow.isEmpty {
                currentRow.append(panel)
            } else {
                // 判断是否同一行：Y 重叠 >50%
                let rowMinY = currentRow.map { $0.normalizedRect.minY }.min() ?? 0
                let rowMaxY = currentRow.map { $0.normalizedRect.maxY }.max() ?? 0
                let rowCenter = (rowMinY + rowMaxY) / 2
                let panelCenter = (panel.normalizedRect.minY + panel.normalizedRect.maxY) / 2

                let overlap = min(rowMaxY, panel.normalizedRect.maxY) - max(rowMinY, panel.normalizedRect.minY)
                let panelHeight = panel.normalizedRect.height
                let overlapRatio = overlap / panelHeight

                if overlapRatio > 0.5 {
                    currentRow.append(panel)
                } else {
                    rows.append(currentRow)
                    currentRow = [panel]
                }
            }
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }
}

// MARK: - SwiftUI 辅助扩展

extension GuidedPanelNavigator {
    /// 面板导航指示器（底部小圆点或缩略图导航栏的数据）
    struct NavigationIndicatorItem: Identifiable, Sendable {
        let id: Int = 0  // will be set manually
        let panelIndex: Int
        let thumbnailRect: CGRect  // 缩略图中的位置
        let isCurrent: Bool
    }
}
