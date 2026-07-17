# Enhancers

Image processing and AI enhancement modules for the reading experience.

## Modules
- **ImageEnhancer** (Core/Utilities) — CoreImage pipeline for noise reduction, contrast, sharpening, white balance, and optional waifu2x upscaling
- **AITranslationBubble** (Core/Utilities) — Vision OCR + Translation framework for in-page translation overlays
- **ScanAssistant** (Core/Utilities) — VNDocumentCamera + perspective correction + CBZ export

## Design Principles
- All processing on background QoS (.utility)
- Auto-suspend on low battery
- Zero external dependencies — Apple system frameworks only
- Per-page latency budget: <50ms for enhancement, <1s for translation
