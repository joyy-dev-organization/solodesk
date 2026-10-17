# SoloDesk

SoloDesk is a local desktop productivity workspace designed for independent freelancers. It assists with brief analysis (**BriefCheck**), scope verification (**ScopeShield**), and polite payment tracking (**PolitePay**) using local open-weight models (`qwen3:1.7b`) and inspectable Mastra agent workflows, without sending client data to third-party cloud inference services.

## Current Implemented Features

This repository includes the completed implementations for Milestones M0 through M5:
- **Local Mastra Service**: Loopback Node.js service running on `127.0.0.1:3141` orchestrating deterministic `@mastra/core` workflows over local Ollama models (`qwen3:1.7b`), secured with ephemeral `.runtime-token` Bearer authentication, single-concurrency inference locks, and 75s bounded timeouts.
- **Flutter Windows Application**: Native Flutter desktop UI structured according to SoloDesk's Information Architecture, with durable local SQLite persistence (Schema v2) under the current user's application-support directory.
- **My Services**: Service category selection, custom rates, business branding, and default currency configuration.
- **BriefCheck**: Vague brief ingestion, distinction between explicitly stated requirements, assumptions, and omissions, clarifying question drafting, and user-initiated approval creating immutable versioned scopes in SQLite.
- **ScopeShield**: Semantic comparison of client requests against approved SQLite scopes, producing item-level classifications (`included`, `out_of_scope`, `needs_clarification`) with cited textual evidence and editable response drafting.
- **PolitePay**: Multi-currency accounting with integer minor units and calendar-date rules; model-assisted polite payment reminders calibrated across `gentle`, `polite`, and `firm` tones adhering strictly to verified invoice facts.
- **SoloDesk Boundary Policy**: Prominent policy enforcement stating that SoloDesk never processes payments, connects to payment gateways, or dispatches messages automatically. All invoice records and reminder drafts are strictly for user review.

## Architecture Overview

```
[ Flutter / Dart UI ]  <--- HTTP Loopback (127.0.0.1:3141) --->  [ TypeScript / Mastra Service ]
       │                                                                      │
(Local SQLite DB)                                                      (Local Ollama Model: qwen3:1.7b)
```

- **Frontend**: Flutter Windows Desktop (`app/`)
- **Backend Service**: Local loopback Node.js service using Mastra orchestrating deterministic workflows (`service/`)
- **Inference**: Local Ollama runtime (`127.0.0.1:11434`) running open-weight `qwen3:1.7b`
- **Data Storage**: Local SQLite database outside the repository with immutability triggers

## Prerequisites

- **OS**: Windows 10/11 (64-bit)
- **Visual Studio Build Tools 2022+** with Desktop development with C++
- **Flutter SDK**: 3.44+ (Dart 3.12+)
- **Node.js**: LTS (v24+)
- **Ollama for Windows**: Local-only loopback configuration with `qwen3:1.7b` pulled (`ollama pull qwen3:1.7b`)

## Setup and Verification

### 1. Flutter Desktop App
```powershell
cd app
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

### 2. Mastra Service
```powershell
cd service
npm install
npm run typecheck
npm test
npm run build
npm start
```

## Changes after submission

*(No changes after submission yet. Post-deadline changes, if any, will be documented here chronologically).*

## License

[MIT License](LICENSE) © 2026 joyy-dev (ladydiamond)
