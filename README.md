# SoloDesk

SoloDesk is a local desktop productivity workspace designed for independent freelancers. It assists with brief analysis (**BriefCheck**), scope verification (**ScopeShield**), and polite payment tracking (**PolitePay**) using local open-weight models and inspectable Mastra agent workflows, without sending client data to third-party cloud inference services.

## Current Project Status

This repository is currently at **Milestone M0 (Toolchain, repository and rules setup)**:
- Windows Flutter desktop application shell initialized.
- Local loopback TypeScript service initialized with `@mastra/core`, `zod`, and `ollama-ai-provider-v2`.
- Verification baselines (`flutter analyze`, TypeScript `tsc --noEmit`, service ESM build) passing.
- Next active milestone: **M1 (Mastra + local Ollama model integration spike)**.

*Note: UI screens, model inference endpoints, and SQLite storage are active milestone deliverables and have not yet been implemented in this repository.*

## Architecture Overview

```
[ Flutter / Dart UI ]  <--- HTTP Loopback (127.0.0.1) --->  [ TypeScript / Mastra Service ]
       │                                                              │
(Local SQLite DB)                                              (Local Ollama Model)
```

- **Frontend**: Flutter Windows Desktop (`app/`)
- **Backend Service**: Local loopback Node.js service using Mastra orchestrating deterministic workflows (`service/`)
- **Inference**: Local Ollama runtime (`127.0.0.1:11434`) running open-weight models (e.g. Qwen3)

## Prerequisites

- **OS**: Windows 10/11 (64-bit)
- **Visual Studio Build Tools 2022+** with Desktop development with C++ (required by Flutter for Windows compilation)
- **Flutter SDK**: 3.44+ (Dart 3.12+)
- **Node.js**: LTS (v24+)
- **Ollama for Windows**: Local-only loopback configuration

## Setup and Verification

### 1. Flutter Desktop App
```powershell
cd app
flutter pub get
flutter analyze
flutter run -d windows
```

### 2. Mastra Service
```powershell
cd service
npm install
npm run typecheck
npm run build
npm start
```

## Changes after submission

*(No changes after submission yet. Post-deadline changes, if any, will be documented here chronologically).*

## License

[MIT License](LICENSE) © 2026 joyy-dev (ladydiamond)
