# Human-in-the-Loop Feedback Design

## Objective
Capture user corrections and expert review so the model improves with real usage.

## In-App Feedback Actions
After each prediction:
1. `Correct`
2. `Wrong Label`
3. `Not Sure`

If `Wrong Label`, user selects corrected class.

## Minimum Feedback Record
```json
{
  "image_id": "uuid",
  "timestamp": "2026-02-23T10:00:00Z",
  "model_version": "v0.3.2",
  "predicted_label": "armyworm",
  "predicted_confidence": 72.4,
  "top3": [
    {"label": "armyworm", "score": 72.4},
    {"label": "leaf blight", "score": 18.2},
    {"label": "healthy", "score": 9.4}
  ],
  "user_feedback": "wrong_label",
  "corrected_label": "leaf blight",
  "farm_id": "FARM-021",
  "device_id": "CPH2121",
  "location": {"lat": -1.2864, "lng": 36.8172}
}
```

## Review Queue
1. Auto-accept `Correct` entries with high confidence for monitoring only.
2. Route `Wrong Label` and `Not Sure` to expert review queue.
3. Expert marks `approved_label` or `discard`.

## Retraining Cadence
1. Weekly batch export of approved feedback samples.
2. Merge with base dataset.
3. Retrain and evaluate on fixed holdout test set.
4. Deploy only if metrics improve and no class regression appears.

## Governance
1. Keep immutable logs of model version and feedback decisions.
2. Track correction rate by class to identify weak classes early.
3. Use feedback data only with consent and defined retention policy.
