# SoloDesk

SoloDesk is a private, local desktop productivity workspace designed for independent freelancers. It assists with brief analysis (**BriefCheck**), scope verification (**ScopeShield**), polite payment tracking (**PolitePay**), client pipeline tracking (**LeadLoop**), and follow-up proposal drafting (**Repeat Work**) using local open-weight models (`qwen3:1.7b`) and inspectable Mastra agent workflows, without sending client data to third-party cloud inference services.

> [!NOTE]
> **Release Status**: `v0.1.0-challenge` · **Feature Freeze Active** (as of Sunday 2026-10-18T12:00 Africa/Lagos). All completed features and roadmap boundaries are locked for challenge submission.

---

## Submission Metadata & Challenge Traceability

| Attribute | Challenge Value |
| :--- | :--- |
| **Challenge** | Hacktoberfest 2026 / DEV Challenge (Week 2: Best Use of Mastra) |
| **Prize Category** | Best Use of Mastra (Orchestrating agents over local open models) |
| **Release Tag** | [`v0.1.0-challenge`](https://github.com/joyy-dev-organization/solodesk/releases/tag/v0.1.0-challenge) |
| **Baseline Submission Commit** | `dd47789` (and M9 release packaging commits) |
| **Repository URL** | [https://github.com/joyy-dev-organization/solodesk](https://github.com/joyy-dev-organization/solodesk) |
| **Public DEV Post URL** | *[Pending Publication]* |
| **Video Walkthrough Demo** | *[Pending Upload]* |
| **Official Submission Timestamp** | Sunday 2026-10-18T... Africa/Lagos (WAT) |

---

## Product Scope & Feature Boundaries

SoloDesk follows an honest, tripartite scope architecture visually inspectable in the app via the **Release Scope & Boundaries** screen (`RoadmapBoundariesScreen` accessible via the `Freeze Active` pill in the header and sidebar):

### 1. Implemented in v0.1.0-challenge (Milestones M0–M7)
- **Local Mastra Service**: Loopback Node.js service running strictly on `127.0.0.1:3141` orchestrating deterministic `@mastra/core` workflows over local Ollama models (`qwen3:1.7b`), secured with ephemeral `.runtime-token` Bearer authentication, single-concurrency inference locks, and 120s bounded timeouts.
- **Flutter Windows Application**: Native Flutter desktop UI structured according to SoloDesk's Information Architecture, with durable local SQLite persistence (Schema V4) under the current user's `%APPDATA%\solodesk\` directory.
- **My Services**: Service category selection, custom rates, business branding, and default currency configuration.
- **BriefCheck**: Vague brief ingestion, distinction between explicitly stated requirements, assumptions, and omissions, clarifying question drafting, and user-initiated approval creating immutable versioned scopes in SQLite.
- **ScopeShield**: Semantic comparison of client requests against approved SQLite scopes, producing item-level classifications (`included`, `out_of_scope`, `needs_clarification`) with cited textual evidence and editable response drafting.
- **PolitePay**: Multi-currency accounting with integer minor units and calendar-date rules; model-assisted polite payment reminders calibrated across `gentle`, `polite`, and `firm` tones adhering strictly to verified invoice facts.
- **LeadLoop**: Inbound lead capture, inquiry qualification, timeline estimation, and lead status tracking stored locally in SQLite.
- **Repeat Work**: Prior client relationship tracking, project milestone completion follow-ups, and model-assisted non-binding proposal draft generation.
- **SoloDesk Boundary Policy**: Clear policy enforcement stating that SoloDesk never processes payments, connects to payment gateways, or dispatches messages automatically. All invoice records and AI drafts are strictly for user review and editorial assistance.

### 2. Future Roadmap Candidates (Post-Hackathon)
- **Additional Niche Checklists**: Specialized domain heuristics beyond Design and Writing (e.g. Full-Stack Web Development, Mobile Development, Translation/Localization).
- **Proposal & Scope Export**: One-click export of approved scope documents and proposals to formatted PDF and Markdown.
- **Customizable Reminder Cadences**: User-defined automated reminder alert schedules (e.g., 3 days before due date, on due date, 7 days overdue).
- **Visual UI Themes**: Custom light/dark theme toggles and customizable branding accents.

### 3. Out of Scope & Non-Goals (What SoloDesk Is NOT — Handbook §01, Line 48)
- **No Client Portal**: Freelancers interact directly with clients via their own communication channels.
- **No Payment Gateway / Real Payment Processing**: "Marked as Paid" is an internal local ledger status; no Stripe, PayPal, or card gateways.
- **No External Dispatch**: Zero email, SMS, or WhatsApp sending. All drafts must be copied or exported by the user.
- **No Cloud Sync or Remote Storage**: Zero cloud databases or external telemetry.
- **No Multi-User / Team Accounts**: Strictly single-user local workstation design.
- **No Currency Conversion**: Fixed currency display per invoice; zero cross-currency summing.
- **No Legal Determinations**: SoloDesk produces editorial drafting suggestions, not legal advice, binding contracts, or statutory determinations.
- **No Automatic Pricing Algorithms**: Pricing is set manually by the freelancer based on their saved service rates.
- **No Model Fine-Tuning**: Uses off-the-shelf open-weight models (`qwen3:1.7b`).
- **No Mobile Release**: Windows desktop native target only.
- **No RAG or Vector Databases**: Uses structured SQL indexing and targeted prompt schemas.
- **No Always-On Autonomous Agents**: All AI actions are discrete, user-initiated loopback requests.

---

## Empirical Model Selection Rationale (`qwen3:1.7b` vs `qwen3:4b`)

SoloDesk was architected and evaluated on a standard developer workstation (Windows 11, 16 GB shared system RAM, integrated Intel UHD Graphics without dedicated GPU acceleration).

### Benchmarking Evidence (M1 Spike & M8 12-Case Evaluation)
During Milestone 1 and Milestone 8, both `qwen3:4b` and `qwen3:1.7b` were empirically benchmarked against structured Mastra workflows:

1. **`qwen3:4b` Evaluation (Rejected as Default)**:
   - **Isolated Inference**: Required 46–75 seconds for simple test prompts.
   - **Structured Workflows**: Timed out (>120 seconds) on multi-step BriefCheck and ScopeShield workflows due to unconstrained "thinking" token generation.
   - **System Impact**: Consumed >7 GB shared system memory, risking OS paging and UI freezing on 16GB laptops. Violated the Handbook's <60s warm response usability SLA.
2. **`qwen3:1.7b` Evaluation (Approved as Default — Decision D-6)**:
   - **Optimized Configuration**: Evaluated with `think: false`, `num_ctx: 4096`, and `num_predict: 384`.
   - **Cold Start Latency**: 17.4 seconds (well under the 90s cold SLA).
   - **Warm Inference Average**: **38.9 seconds** (ranging between 28.3s and 67.1s), reliably satisfying the <60s SLA.
   - **Peak Process RSS Memory**: **175.5 MB** for the Node/Mastra process; Ollama runtime remained stable under 3.2 GB.
   - **Schema Compliance**: **100% (12/12 cases passed Zod validation)** with an average human rubric score of **5.8 / 6.0**.
   - **Prompt Injection Resilience**: Successfully repelled adversarial scope override and prompt injection tests (`brief-6`, `scope-6`) without conceding ungrounded deliverables.

*Conclusion*: `qwen3:1.7b` provides the ideal balance of grounded reasoning, 100% schema compliance, and responsive local latency on standard non-GPU hardware. Users with dedicated NVIDIA/AMD GPUs can configure larger models via local Ollama tags if desired.

---

## System Limitations & Operational Constraints

1. **Advisory Editorial Output**: All classifications, scope recommendations, and reminder drafts generated by SoloDesk are editorial suggestions designed to assist freelancer communication. They do not constitute legal advice, binding contractual agreements, or formal debt collection. The freelancer retains sole editorial authority and must review all text before sending.
2. **Local Compute & Latency**: On shared CPU/integrated GPU hardware, inference workflows take ~25–45 seconds. Running multiple memory-intensive applications simultaneously during inference may increase processing duration.
3. **Single-Concurrency Inference Lock**: To prevent memory starvation on 16GB laptops, the local Mastra service uses an atomic mutex allowing only one inference request at a time. Concurrent requests receive HTTP 429 (`BUSY`).
4. **Small-Model Heuristics**: While `qwen3:1.7b` performs exceptionally well on factual extraction, highly subjective aesthetic requests (e.g. "make it pop") are classified as requiring clarification rather than making definitive scope decisions.
5. **Local Dependency**: SoloDesk requires a running local Ollama instance on `127.0.0.1:11434`. There is no cloud fallback by design.

---

## Data Privacy, Security & Storage Disclosure

- **Loopback Isolation**: The backend service binds strictly to `127.0.0.1:3141` and Ollama to `127.0.0.1:11434`. Web browser `Origin` headers are rejected with HTTP 403 to prevent DNS rebinding or cross-site scripting attacks.
- **Ephemeral Authentication**: Flutter and Mastra communicate using a cryptographically random Bearer token (`.runtime-token`) generated on service startup with restricted file permissions (`0600`) and deleted upon service termination.
- **Data at Rest**: SQLite database (`solodesk.db`) is stored in `%APPDATA%\solodesk\`. **Data at rest is unencrypted** and relies on Windows operating system file permissions and user profile access controls.
- **Threat Model Boundary (Handbook §02, Line 117)**: SoloDesk guarantees that client data is never transmitted to cloud providers. However, protection against unauthorized physical access or local administrative malware on the host machine is outside this threat model.
- **Zero Cloud Fallback**: All AI workflows execute entirely on local hardware via Ollama. Network isolation was empirically verified using `tools/test-offline.ps1` with zero outbound WAN connections.

---

## Setup, Start and Stop Instructions

### Option A: Running the Pre-Built Release Package (Judges & End Users)

#### Prerequisites
1. **Windows 10/11 64-bit**
2. **Node.js LTS (v20+)**: [Download Node.js](https://nodejs.org/)
3. **Ollama for Windows**: [Download Ollama](https://ollama.com/download/windows)
4. **Visual C++ Redistributable 2015–2022**: Included on most Windows systems; download from Microsoft if prompted.

#### Setup & Launch
1. Download and extract `solodesk-v0.1.0-windows-x64.zip`.
2. Open PowerShell and pull the local open-weight model:
   ```powershell
   ollama pull qwen3:1.7b
   ```
3. Run the automated launcher:
   ```powershell
   .\launch-solodesk.bat
   ```
   *(Alternatively: In one terminal run `cd service; npm start`, and then launch `app\solodesk.exe`).*

---

### Option B: Developer Source Build & Verification

#### Prerequisites
- Flutter SDK 3.44+ (Dart 3.12+)
- Visual Studio Build Tools 2022 with Desktop development with C++
- Node.js LTS (v20+)
- Ollama for Windows with `qwen3:1.7b` pulled

#### 1. Mastra Service Setup & Verification
```powershell
cd service
npm install
npm run typecheck
npm test                    # Fast unit tests (<3s)
npm run test:integration    # Live Ollama integration tests
npm run eval:12cases        # 12-case BriefCheck & ScopeShield evaluation harness
npm run build
npm start
```

#### 2. Flutter Desktop App Setup & Execution
```powershell
cd app
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

#### 3. Automated Windows E2E & Offline Verification
```powershell
# Windows Desktop end-to-end loopback verification
powershell -ExecutionPolicy Bypass -File tools/run-windows-e2e.ps1

# Offline isolation and zero-cloud verification
powershell -ExecutionPolicy Bypass -File tools/test-offline.ps1
```

---

### Stopping SoloDesk Gracefully

To cleanly shut down SoloDesk and release all system resources:
1. **Close the Application**: Close the `solodesk.exe` desktop window.
2. **Stop the Mastra Service**: Press `Ctrl + C` in the service terminal (or let the launcher clean it up automatically). The service catches `SIGINT`/`SIGTERM`, safely deletes the ephemeral `.runtime-token` file, and closes port 3141.
3. **Unload Ollama Model**:
   ```powershell
   ollama stop qwen3:1.7b
   ```
   This releases the model weights from system RAM/VRAM.

---

## Changes after submission

Per Hacktoberfest 2026 challenge rules and Build Handbook §04 (line 232) and §05 (lines 379–380), all modifications made after the official challenge deadline (<date start="2026-10-19" start-time="07:59" time-zone="Africa/Lagos" />) are logged chronologically below. No Git history or commit timestamps will ever be rewritten.

- **Baseline Challenge Submission Release**: `v0.1.0-challenge`
- **Baseline Challenge Commit**: `dd47789` (and M9 release packaging commits)
- **Submission Deadline**: Monday 2026-10-19 07:59 Africa/Lagos (Sunday 2026-10-18 23:59 PT)

| Timestamp (WAT / UTC) | Commit SHA | Description of Change | Files Changed | Rationale / Compliance Impact |
| :--- | :--- | :--- | :--- | :--- |
| *(None)* | — | Baseline challenge submission snapshot. | — | Feature freeze active. |

---

## Third-Party Notices & Attribution

SoloDesk is open-source software licensed under the **MIT License**. It integrates and relies upon the following open-source projects and open-weight models:

| Component / Library | Project Owner | License | Purpose in SoloDesk |
| :--- | :--- | :--- | :--- |
| **SoloDesk** | ladydiamond | MIT License | Core application and local service |
| **Flutter SDK & Dart** | Google LLC | BSD 3-Clause | Native Windows desktop user interface |
| **Mastra (`@mastra/core`)** | Mastra AI | Apache License 2.0 | Inspectable agent workflow orchestration |
| **Ollama** | Ollama Inc. | MIT License | Local loopback model inference server |
| **Qwen 2.5 / Qwen 3 (`qwen3:1.7b`)** | Alibaba Cloud / Qwen Team | Apache 2.0 / Qianwen License | Local open-weight language model |
| **SQLite** | D. Richard Hipp | Public Domain | Durable local relational database engine |
| **sqflite_common_ffi** | Alexandre Roux (tekartik) | BSD 2-Clause | Dart FFI bindings for desktop SQLite |
| **Zod** | Colin McDonnell | MIT License | Strict runtime schema validation for AI I/O |
| **ollama-ai-provider-v2** | Community | MIT License | AI SDK adapter for local Ollama provider |

---

## License

[MIT License](LICENSE) © 2026 ladydiamond
