# Model Limitations (Pitch Script)

Use the statements below during judging/pitch Q&A.

## Core Position
This is a decision-support model, not an autonomous diagnosis tool.

## Limitations to State Clearly
1. Accuracy depends on image conditions matching training data quality.
2. Some diseases have visually overlapping symptoms.
3. Confidence is a ranking certainty signal, not a guarantee of correctness.
4. Field variation (lighting, angle, crop stage) can reduce model confidence.
5. Low-confidence cases are intentionally routed to `Unknown`.

## Risk Control Narrative
1. We use thresholding and show confidence to avoid overconfident errors.
2. We log farmer feedback and retrain periodically.
3. We only promote new models when they improve on a fixed holdout set.

## One-Line Close
Our design prioritizes safe guidance and continuous model improvement over forced predictions.
