# AgriSentinels

AgriSentinels is an AI-powered early warning app for maize crop health. It performs on-device image inference and surfaces confidence-aware guidance for faster field decisions.

## What is implemented
- Flutter mobile app for image capture and upload (`SCAN`, `UPLOAD`)
- On-device TensorFlow Lite inference (`assets/model.tflite`)
- Confidence thresholding with safe fallback to `Unknown` for low-certainty predictions
- Top-3 prediction transparency and severity/advice mapping
- GPS-tagged scan context and local scan history persistence
- Reproducible model training and evaluation utilities in `tools/`

## System architecture
See full architecture and data flow in [docs/architecture_and_data_flow.md](docs/architecture_and_data_flow.md).

High-level flow:
1. User captures or uploads a maize image in the Flutter app.
2. Image is preprocessed to match model input tensor type/shape.
3. TFLite model returns class scores; app normalizes and validates probabilities.
4. App applies confidence threshold (`<60% => Unknown`) and shows top-3 scores.
5. Result + severity + location + timestamp are stored in local history.

## Repo structure
```text
lib/                     Flutter app (UI + inference + scan history)
assets/                  Deployed model + labels
tools/                   Training, split, review, and evaluation scripts
docs/                    Collection, ML workflow, confidence, and governance docs
test/                    Unit/widget tests
```

## Quick start (app)
Prerequisites:
- Flutter SDK (3.x)
- Android/iOS emulator or physical device

Run:
```bash
flutter pub get
flutter run
```

## ML workflow (reproducible commands)
1. Build review CSVs:
```bash
python tools/create_review_csv.py --class-name "armyworm"
python tools/create_review_csv.py --class-name "leaf blight"
python tools/create_review_csv.py --class-name "healthy"
```
2. Apply review decisions:
```bash
python tools/apply_review_csv.py --csv dataset/_review/armyworm_review.csv
python tools/apply_review_csv.py --csv dataset/_review/leaf_blight_review.csv
python tools/apply_review_csv.py --csv dataset/_review/healthy_review.csv
```
3. Build balanced split:
```bash
python tools/build_dataset_split.py --root dataset --out dataset_split --max-ratio 2.0
```
4. Train model:
```bash
python tools/train_tflite.py
```
5. Evaluate model on holdout test split:
```bash
python tools/eval_tflite.py --model model_artifacts/model.tflite --labels model_artifacts/labels.txt --data dataset_split/test
```

## Engineering evidence
Recent implementation progress is documented in git history, including:
- confidence thresholding and review tooling
- confidence calibration and ML playbooks
- inference contract hardening and scan history persistence
- evaluation pipeline dtype fixes

## Documentation index
- Dataset collection protocol: `docs/dataset_collection_strategy.md`
- Training pipeline: `docs/training_pipeline_tensorflow.md`
- Label review + deployment workflow: `docs/label_and_model_workflow.md`
- Confidence logic: `docs/demo_confidence_logic.md`
- Human-in-the-loop feedback loop: `docs/human_in_the_loop_feedback.md`
- Model limitations narrative: `docs/pitch_model_limitations.md`
- Architecture and data flow: `docs/architecture_and_data_flow.md`

## Model assets
- Active model: `assets/model.tflite`
- Active labels: `assets/labels.txt`

Keep label order synchronized between model output and `assets/labels.txt` after each export.
