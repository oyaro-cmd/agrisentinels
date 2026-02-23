# Dataset Collection Strategy (Farmer Workflow)

## Goal
Collect reliable maize disease images that can be used to train a stable model for:
- `armyworm` (worm visible only)
- `healthy`
- `leaf blight`

## Class Definitions (Non-Negotiable)
- `armyworm`: larva visibly present on maize plant.
- `healthy`: no visible disease or pest damage.
- `leaf blight`: clear blight lesions/streaks consistent with blight.

If an image does not match one of these definitions, do not label it.

## Field Capture Protocol
1. Use natural daylight when possible.
2. Keep camera distance around `20-40 cm` from target leaf.
3. Capture two angles per sample:
- straight-on
- slight side angle
4. Keep one primary subject centered.
5. Avoid heavy blur, extreme shadows, and digital zoom.

## Daily Collection Checklist
1. Collect from at least `3` farms per day.
2. Record metadata:
- `farm_id`
- `collector_id`
- `county`
- `date`
- `crop_stage`
- `device_type`
3. Remove unusable images same day:
- non-maize images
- watermark/stock photos
- severe blur/overexposure

## Quality Control
1. Randomly re-check `20%` of new images by a second reviewer.
2. Flag disagreements for agronomist decision.
3. Keep a quarantine folder for rejected files; do not hard-delete immediately.

## Balance Targets
1. Keep class ratio within `2x`.
2. First milestone target: `600` images per class.
3. If one class lags, collect that class first before adding more to dominant classes.

## Split Strategy
Use farm-level split so photos from the same farm are not in both train and validation.
- `70%` train
- `20%` validation
- `10%` test

## Versioning
For every training cycle, save:
- dataset snapshot date
- class counts
- label definitions used
- model version generated
