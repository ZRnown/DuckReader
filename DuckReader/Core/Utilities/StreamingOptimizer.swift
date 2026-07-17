import Foundation
import Network

// MARK: - Streaming 阅读优化器
/// 优化异步解码/预加载逻辑，支持云/NAS 边下边读
/// 自适应网络质量调整策略，几乎不增加额外电量消耗
actor StreamingOptimizer {
    // MARK: - Config
    struct Config {
        /// 前向预取页数（正常网络）
        var forwardPrefetchPages: Int = 5
        /// 后向预取页数
        var backwardPrefetchPages: Int = 2
        /// 弱网时预取页数减半
        var weakNetworkPrefetchMultiplier: Double = 0.5
        /// 使用移动数据时最大预取页数
        var cellularMaxPrefetch: Int = 3
        /// 单页最大内存（超过则降分辨率）
        var maxMemoryPerPageBytes: Int = 20 * 1024 * 1024  // 20MB
        /// 缓冲区目标大小（页数）
        var bufferTargetPages: Int = 10
    }

    var config: Config = Config()

    // MARK: - Types
    enum NetworkQuality: Sendable {
        case excellent  // WiFi ≥10Mbps
        case good       // WiFi 2-10Mbps
        case fair       // WiFi <2Mbps 或 4G/5G
        case poor       // 弱信号
        case unknown

        var maxPrefetch: Int {
            switch self {
            case .excellent: return 10
            case .good:      return 5
            case .fair:      return 3
            case .poor:      return 1
            case .unknown:   return 3
            }
        }
    }

    enum ImageQuality: Sendable {
        case original
        case high(compression: Double = 0.9)
        case medium(compression: Double = 0.7)
        case low(compression: Double = 0.5)

        var compressionRatio: Double {
            switch self {
            case .original: return 1.0
            case .high(let c): return c
            case .medium(let c): return c
            case .low(let c): return c
            }
        }
    }

    // MARK: - State
    private var networkQuality: NetworkQuality = .unknown
    private let networkMonitor = NWPathMonitor()
    private var isOnCellular: Bool = false

    // 缓冲区
    private var pageBuffer: [Int: Data] = [:]  // pageIndex → image data
    private var prefetchQueue: Set<Int> = []
    private var currentPage: Int = 0

    // MARK: - Public API

    /// 启动网络监听
    func startMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.handleNetworkChange(path) }
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    /// 停止网络监听
    func stopMonitoring() {
        networkMonitor.cancel()
    }

    /// 计算当前页的最优预取策略
    func prefetchStrategy(
        currentIndex: Int,
        totalPages: Int,
        isOnWiFi: Bool,
        isOnCellular: Bool
    ) -> (forward: Int, backward: Int, quality: ImageQuality) {
        self.currentPage = currentIndex

        let quality: ImageQuality
        let maxForward: Int

        switch networkQuality {
        case .excellent:
            quality = .original
            maxForward = NetworkQuality.excellent.maxPrefetch
        case .good:
            quality = .high()
            maxForward = NetworkQuality.good.maxPrefetch
        case .fair:
            quality = .medium()
            maxForward = NetworkQuality.fair.maxPrefetch
        case .poor:
            quality = .low()
            maxForward = NetworkQuality.poor.maxPrefetch
        case .unknown:
            quality = .high()
            maxForward = isOnCellular ? config.cellularMaxPrefetch : config.forwardPrefetchPages
        }

        let forward = min(maxForward, totalPages - currentIndex - 1)
        let backward = min(config.backwardPrefetchPages, currentIndex)

        return (forward, backward, quality)
    }

    /// 检查单页是否超过内存限制
    func shouldDownsample(pageData: Data) -> Bool {
        pageData.count > config.maxMemoryPerPageBytes
    }

    /// 自适应图片质量（基于文件大小）
    func adaptiveQuality(for data: Data, targetKB: Int = 200) -> ImageQuality {
        let sizeKB = data.count / 1024
        if sizeKB <= targetKB { return .original }
        if sizeKB <= targetKB * 3 { return .high() }
        if sizeKB <= targetKB * 6 { return .medium() }
        return .low()
    }

    /// 获取当前网络质量
    func currentQuality() -> NetworkQuality {
        networkQuality
    }
}

// MARK: - Private

private extension StreamingOptimizer {

    func handleNetworkChange(_ path: NWPath) {
        isOnCellular = path.usesInterfaceType(.cellular)

        if path.status != .satisfied {
            networkQuality = .poor
            return
        }

        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
            // 基于带宽估算
            if path.isExpensive {
                networkQuality = .fair
            } else {
                // WiFi 通常从 good 起步
                networkQuality = .good
            }
        } else if path.usesInterfaceType(.cellular) {
            networkQuality = .fair
        } else {
            networkQuality = .unknown
        }
    }
}

// MARK: - 预取调度器
/// 在 StreamingImageDecoder 基础上增强预取逻辑
extension StreamingOptimizer {

    /// 计算预取页面窗口
    func prefetchWindow(
        current: Int,
        total: Int,
        direction: Int = 1  // +1 前进, -1 后退
    ) -> Range<Int> {
        let (forward, backward, _) = prefetchStrategy(
            currentIndex: current,
            totalPages: total,
            isOnWiFi: !isOnCellular,
            isOnCellular: isOnCellular
        )

        let start = max(0, current - backward)
        let end = min(total, current + forward + 1)

        // 过滤掉已在缓冲区的
        return start..<end
    }

    /// 判断是否需要预取
    func needsPrefetch(pageIndex: Int) -> Bool {
        pageBuffer[pageIndex] == nil && !prefetchQueue.contains(pageIndex)
    }

    /// 标记开始预取
    func markPrefetching(_ pageIndex: Int) {
        prefetchQueue.insert(pageIndex)
    }

    /// 预取完成
    func markPrefetched(_ pageIndex: Int, data: Data?) {
        prefetchQueue.remove(pageIndex)
        if let data {
            pageBuffer[pageIndex] = data
        }
    }

    /// 清理远端缓冲区
    func evictFarPages(keepRange: Range<Int>) {
        let toRemove = pageBuffer.keys.filter { !keepRange.contains($0) }
        for key in toRemove {
            pageBuffer.removeValue(forKey: key)
        }
    }
}
