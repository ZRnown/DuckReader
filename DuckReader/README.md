# DuckReader — 哎鸭阅读器

高品质 iOS 漫画/小说阅读器 | SwiftUI + Swift 6 | iOS 18+

## Architecture

Clean Architecture + Feature Modules

```
DuckReader/
├── App/                     # App 入口
│   └── DuckReaderApp.swift
├── Domain/                  # 纯 Swift 业务逻辑（无框架依赖）
│   ├── Models/              # Book, Chapter, PageData, ReadingProgress...
│   ├── Protocols/           # ArchiveParserProtocol, ReadingEngineProtocol...
│   └── UseCases/            # ImportBookUseCase, OpenBookUseCase, ScanLibraryUseCase
├── Data/                    # 数据持久化 + 外部服务
│   ├── Repositories/        # LibraryRepository (SwiftData)
│   ├── DataSources/Local/   # SwiftDataModels + SwiftDataStack
│   ├── DataSources/Remote/  # CloudSyncService (占位)
│   └── Parsers/             # ArchiveParser, ComicArchiveParser, FormatDetector
├── Core/                    # 跨层工具
│   ├── Extensions/          # FileManager+, String+, Date+, URL+...
│   ├── Utilities/           # ImageProcessor, TTSManager, ThumbnailGenerator
│   └── Components/          # CachedAsyncImage, ErrorView, LoadingView, EmptyStateView
├── Features/                # SwiftUI 功能模块
│   ├── Library/             # 图书馆 (View + ViewModel)
│   ├── Reader/
│   │   ├── ComicReader/     # 漫画阅读器
│   │   ├── NovelReader/     # 小说阅读器
│   │   └── Shared/          # 通用阅读组件
│   ├── Settings/            # 设置页
│   └── Store/               # 内购/付费墙
├── Resources/               # Assets, Localizable, Info.plist
└── Tests/
    ├── DuckReaderTests/     # Unit Tests (swift-testing)
    └── DuckReaderUITests/   # UI Tests
```

## Tech Stack

| 层 | 技术选型 | 原因 |
|---|---|---|
| UI | SwiftUI | 声明式、iOS 18+ |
| 并发 | Swift 6 Concurrency (async/await) | 编译期数据竞争检查 |
| 持久化 | SwiftData | Apple 官方、与 CloudKit 深度集成 |
| 状态管理 | @Observable (iOS 17+) | Observation 框架 |
| 阅读引擎 | Readium Swift Toolkit | BSD-3 开源、商业友好 |
| ZIP | ZIPFoundation | MIT 许可 |
| RAR | UnrarKit | 开源 |
| 图片 | Nuke + Core Image | 高性能缓存 + 原生处理 |
| 测试 | swift-testing (XCTest) | 现代 Swift 测试框架 |

## Supported Formats

### Comic
- CBZ (ZIP-based) — ZIPFoundation
- CBR (RAR-based) — UnrarKit
- ZIP/GZIP
- RAR (4.x, 5.x)
- 7z — LZMA SDK (additional dependency)
- PDF — Readium
- Image folders (jpg/png/webp/heic)

### Novel
- EPUB — Readium + SwiftSoup
- TXT — native
- Markdown — native
- HTML — SwiftSoup
- MOBI/AZW3 — experimental

## Freemium Model

| Tier | Price | Features |
|---|---|---|
| Free | ¥0 | 基础本地阅读、5本图书馆 |
| Pro (一次性) | ¥68-98 | 无限图书馆、全部格式、AI增强、面板检测、主题、手势、无广告 |
| AI 订阅 | ¥18/月 | LLM 推荐、AI 总结、超分辨率增强 |
| 云同步 | ¥8/月 | WebDAV/SMB 同步（可选） |
| 打赏 | ¥6/18/68 | 支持开发者 |

## Build

```bash
# Open in Xcode 16+
open DuckReader.xcodeproj

# Or use SPM
swift build
swift test
```

## Design Principles

1. **Local First** — 所有数据默认保存在设备上
2. **Privacy First** — 无默认追踪，支持 FaceID 锁定
3. **Error Resilience** — 优雅降级：损坏档案提示，部分加载
4. **Performance** — 流式提取，不将大文件全部读入内存
5. **Testability** — 协议驱动、依赖注入、Preview 数据分离

## Next Steps (Roadmap)

- [x] Project skeleton + Domain models
- [x] Archive parser (ZIP/CBZ + RAR/CBR)
- [x] SwiftData persistence layer
- [x] Library UI + Comic Reader UI + Novel Reader UI
- [x] StoreKit IAP integration
- [x] Settings + Unit tests
- [ ] Readium integration (EPUB rendering, PDF)
- [ ] Panel detection (Vision/Core ML)
- [ ] AI image enhancement (Core ML Super Resolution)
- [ ] TTS integration for novels
- [ ] Cloud sync (CloudKit / WebDAV)
- [ ] Achievement system
- [ ] Dynamic Island / Lock Screen widgets
- [ ] Keyboard + Game Controller support
- [ ] NAS/SMB/WebDAV browser

## License

Source: Proprietary (All Rights Reserved)

Third-party dependencies licensed under their respective terms (BSD-3, MIT, etc.)
