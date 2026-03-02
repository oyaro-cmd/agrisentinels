# Architecture and Data Flow

## 1. Purpose and Scope
AgriSentinels is a decision-support platform for maize health monitoring with two operational tracks:
- mobile-first, on-device disease screening in the Flutter app
- backend API and data services for authenticated users and crop telemetry records

The architecture is intentionally local-first for field reliability, with a clear path to cloud-backed synchronization and model lifecycle governance.

## 2. System Architecture
```text
[Farmer / Agronomist]
      |
      v
[Flutter Mobile App]
  - camera/gallery input
  - TFLite inference engine
  - confidence gating + advice mapping
  - local scan history (SharedPreferences)
      |
      | optional/next: sync channel
      v
[Express API Layer]
  - /api/auth (register/login)
  - /api/crops (secured crop records)
  - JWT auth middleware
      |
      v
[MongoDB]
  - users
  - crop_data

[ML Tooling Pipeline (Python)]
  - dataset review + quarantine
  - balanced split generation
  - model training + TFLite export
  - evaluation metrics + misclassification analysis
      |
      v
[Versioned model assets]
  - assets/model.tflite
  - assets/labels.txt
```

## 3. Component Responsibilities
- Flutter App (`lib/main.dart`): UI, image acquisition, tensor preprocessing, on-device inference, confidence thresholding, and local persistence of recent scans.
- Model Assets (`assets/model.tflite`, `assets/labels.txt`): immutable inference contract for app runtime.
- API Server (`backend/server.js`, `backend/src/routes/*`): authentication, protected data routes, and request orchestration.
- Persistence Layer (`backend/src/models/*`, MongoDB): schema validation and durable storage for users and crop records.
- ML Tooling (`tools/*.py`): reproducible data curation, training, evaluation, and model promotion workflow.

## 4. Runtime Data Flow

### 4.1 On-Device Diagnosis Flow (Implemented)
1. User captures or uploads a maize image.
2. App decodes image and adapts it to the model input tensor metadata (shape, dtype, quantization).
3. TFLite inference runs entirely on device.
4. Output scores are normalized and ranked.
5. If top confidence is below threshold (60%), the app returns `Unknown`.
6. UI renders diagnosis, confidence, top-3 classes, severity, and action guidance.
7. Scan metadata (timestamp, location, label, confidence, image path) is stored locally.

### 4.2 Auth and Crop Telemetry Flow (Implemented in Backend)
1. Client registers/logs in via `/api/auth/register` or `/api/auth/login`.
2. API validates credentials and returns JWT.
3. Client calls protected crop routes with `Authorization: Bearer <token>`.
4. Middleware verifies JWT and resolves user identity.
5. Crop records are stored/retrieved from MongoDB via Mongoose models.

### 4.3 Model Lifecycle Flow (Implemented)
1. Generate review sheets by class.
2. Apply human review decisions and quarantine noisy samples.
3. Build balanced train/val/test split.
4. Train TensorFlow model and export TFLite artifacts.
5. Evaluate holdout performance and inspect per-class metrics/confusion matrix.
6. Promote validated model and labels into app assets.

## 5. Implementation Decisions for Maintainability and Scalability

### 5.1 Current Decisions
- On-device inference first: reduces latency, supports offline field usage, and lowers backend inference cost.
- Confidence-aware gating (`Unknown` fallback): avoids overconfident wrong classifications in ambiguous conditions.
- Explicit tensor/label contract checks: prevents silent model-app mismatch regressions.
- Local-first scan history: preserves usability in unstable connectivity zones.
- Stateless JWT-based API: simplifies horizontal scaling of API instances.
- Mongoose schema constraints: enforces baseline data validity at write time.
- Scripted ML pipeline: keeps training/evaluation repeatable and auditable.

### 5.2 Required Next Decisions (for growth)
- Introduce API versioning (`/api/v1`) before adding breaking contract changes.
- Define sync architecture for scan history (offline queue, idempotent writes, conflict rules).
- Add database indexes for expected query paths (crop name, userId, recordedAt).
- Move long-running retraining/evaluation tasks to async jobs/workers.
- Add model registry metadata (model version, dataset hash, metrics) and expose in app/API.
- Standardize structured logging, request tracing, and error taxonomies.
- Establish SLO-driven alerting for API latency, auth failures, and data write errors.

## 6. Maintainability Standards
- Modular boundaries: keep UI, inference, domain logic, and persistence separated.
- Backward-compatible contracts: treat model I/O schema and API payloads as versioned interfaces.
- Test pyramid:
  - unit tests for preprocessing, confidence gating, auth middleware, and schema validation
  - integration tests for auth + protected crop routes
  - regression tests for model output mapping to labels
- Environment isolation: strict `.env` usage for secrets and environment-specific configuration.
- Documentation discipline: each architecture change updates this file and related workflow docs.

## 7. Scalability Roadmap
1. Phase 1: stabilize contracts, add tests, add indexes, introduce API versioning.
2. Phase 2: implement offline-to-cloud sync and conflict-safe write model.
3. Phase 3: add asynchronous ML operations, model registry, and deployment gates.
4. Phase 4: production observability, autoscaling policy, and multi-region readiness if needed.

## 8. Architecture Outcome
This design keeps the core diagnosis loop resilient in the field while enabling incremental migration to a cloud-synced, observable, and horizontally scalable platform without rewriting the mobile inference core.
