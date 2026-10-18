# SoloDesk

SoloDesk is a private, local desktop productivity workspace designed for independent freelancers. It assists with brief analysis (**BriefCheck**), scope verification (**ScopeShield**), polite payment tracking (**PolitePay**), client pipeline tracking (**LeadLoop**), and follow-up proposal drafting (**Repeat Work**) using local open-weight models (`qwen3:1.7b`) and inspectable Mastra agent workflows, without sending client data to third-party cloud inference services.

> [!NOTE]
> **Release Status**: `v0.1.0-challenge` · **Feature Freeze Active** (as of Sunday 2026-10-18T12:00 Africa/Lagos). All completed features and roadmap boundaries are locked for challenge submission.

---

## Current Implemented Features (v0.1.0-challenge)

This repository includes the complete implementations for Milestones M0 through M7:
- **Local Mastra Service**: Loopback Node.js service running strictly on `127.0.0.1:3141` orchestrating deterministic `@mastra/core` workflows over local Ollama models (`qwen3:1.7b`), secured with ephemeral `.runtime-token` Bearer authentication, single-concurrency inference locks, and 120s bounded timeouts.
- **Flutter Windows Application**: Native Flutter desktop UI structured according to SoloDesk's Information Architecture, with durable local SQLite persistence (Schema V4) under the current user's `%APPDATA%\solodesk\` directory.
- **My Services**: Service category selection, custom rates, business branding, and default currency configuration.
- **BriefCheck**: Vague brief ingestion, distinction between explicitly stated requirements, assumptions, and omissions, clarifying question drafting, and user-initiated approval creating immutable versioned scopes in SQLite.
- **ScopeShield**: Semantic comparison of client requests against approved SQLite scopes, producing item-level classifications (`included`, `out_of_scope`, `needs_clarification`) with cited textual evidence and editable response drafting.
- **PolitePay**: Multi-currency accounting with integer minor units and calendar-date rules; model-assisted polite payment reminders calibrated across `gentle`, `polite`, and `firm` tones adhering strictly to verified invoice facts.
- **LeadLoop**: Inbound lead capture, inquiry qualification, timeline estimation, and lead status tracking stored locally in SQLite.
- **Repeat Work**: Prior client relationship tracking, project milestone completion follow-ups, and model-assisted non-binding proposal draft generation.
- **SoloDesk Boundary Policy**: Clear policy enforcement stating that SoloDesk never processes payments, connects to payment gateways, or dispatches messages automatically. All invoice records and AI drafts are strictly for user review and editorial assistance.

---

## Scope & Non-Goals (What SoloDesk Is NOT)

Per the build handbook specification (Section 01, line 48), the following capabilities are **explicitly out of scope** for this release and are not included:
- **No Client Portal**: Freelancers interact directly with clients via their own communication tools.
- **No Payment Gateway / Real Payment Processing**: "Marked as Paid" is an internal local ledger status; no Stripe, PayPal, or card gateways.
- **No External Dispatch**: Zero email, SMS, or WhatsApp sending. All drafts must be copied or exported by the user.
- **No Cloud Sync or Remote Storage**: Zero cloud databases or external telemetry.
- **No Multi-User / Team Accounts**: Strictly single-user local workstation design.
- **No Currency Conversion**: Fixed currency display per invoice.
- **No Legal Determinations**: SoloDesk produces editorial drafting suggestions, not legal advice, binding contracts, or statutory determinations.
- **No Automatic Pricing Algorithms**: Pricing is set manually by the freelancer based on their saved service rates.
- **No Model Fine-Tuning**: Uses off-the-shelf open-weight models (`qwen3:1.7b`).
- **No Mobile Release**: Windows desktop native target only.
- **No RAG or Vector Databases**: Uses structured SQL indexing and targeted prompt schemas.
- **No Always-On Autonomous Agents**: All AI actions are discrete, user-initiated loopback requests.

---

## Data Privacy, Security & Storage Disclosure

- **Loopback Isolation**: The backend service binds strictly to `127.0.0.1:3141` and Ollama to `127.0.0.1:11434`. Web browser `Origin` headers are rejected with HTTP 403 to prevent DNS rebinding or cross-site scripting attacks.
- **Data at Rest**: SQLite database (`solodesk.db`) is stored in `%APPDATA%\solodesk\`. **Data at rest is unencrypted** and relies on Windows operating system file permissions and user profile access controls. Do not rely on SoloDesk to protect data against unauthorized physical or administrative compromise of the host machine.
- **Zero Cloud Fallback**: All AI workflows execute entirely on local hardware via Ollama. No telemetry, prompt logs, or inference requests are ever transmitted over the internet.

---

## Architecture Overview

```
[ Flutter / Dart UI ]  <--- HTTP Loopback (127.0.0.1:3141) --->  [ TypeScript / Mastra Service ]
       │                                                                      │
(Local SQLite DB V4)                                                   (Local Ollama: qwen3:1.7b)
%APPDATA%\solodesk\solodesk.db                                         127.0.0.1:11434
```

- **Frontend**: Flutter Windows Desktop (`app/`)
- **Backend Service**: Local loopback Node.js service using Mastra orchestrating deterministic workflows (`service/`)
- **Inference**: Local Ollama runtime (`127.0.0.1:11434`) running open-weight `qwen3:1.7b`
- **Data Storage**: Local SQLite database outside the repository with immutability triggers

---

## Prerequisites

- **OS**: Windows 10/11 (64-bit)
- **Visual Studio Build Tools 2022+** with Desktop development with C++
- **Flutter SDK**: 3.44+ (Dart 3.12+)
- **Node.js**: LTS (v24+)
- **Ollama for Windows**: Local-only loopback configuration with `qwen3:1.7b` pulled (`ollama pull qwen3:1.7b`)

---

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
npm test                    # Fast unit tests (<3s)
npm run test:integration    # Full integration suite with live Ollama
npm run eval:12cases        # 12-case BriefCheck & ScopeShield evaluation harness
npm run build
npm start
```

### 3. Windows E2E & Offline Verification
```powershell
# Windows Desktop end-to-end loopback verification
powershell -ExecutionPolicy Bypass -File tools/run-windows-e2e.ps1

# Offline isolation and zero-cloud verification
powershell -ExecutionPolicy Bypass -File tools/test-offline.ps1
```

---

## Changes after submission

*(No changes after submission yet. Post-deadline changes, if any, will be documented here chronologically).*

---

## License

[MIT License](LICENSE) © 2026 ladydiamond
