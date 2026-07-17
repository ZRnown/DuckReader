# Assistants

Reading companion modules: language learning, vocabulary tracking, and glossary helpers.

## Modules
- **GlossaryAssistant** (Features/Reader/NovelReader) — NaturalLanguage NLTagger for NER (names, places) + CJK surname rules, incremental tracking, alias detection, importance scoring
- **VocabularyManager** (Features/Reader/NovelReader) — Vocabulary building and review for language learners

## Design Principles
- Local-first, no cloud dependency
- Incremental scanning (<10ms per chapter)
- NLTagger + rule-based dual engine for high accuracy across CJK + Latin scripts
- User-triggered, not automatic full-book processing
