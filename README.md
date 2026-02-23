# AgriSentinels

AgriSentinels is an AI-powered early warning system designed to help farmers detect crop disease and pest risk early.

## Features
- Mobile image capture and upload
- On-device TFLite image classification
- Severity guidance and action recommendations
- GPS-tagged scan history
- Top-3 prediction transparency with confidence thresholding

## Tech Stack
- Frontend: Flutter
- Inference: TensorFlow Lite
- Backend: Node.js (project workspace includes backend service)

## Operational Guides
- Dataset collection workflow: `docs/dataset_collection_strategy.md`
- TensorFlow training pipeline: `docs/training_pipeline_tensorflow.md`
- Demo confidence design: `docs/demo_confidence_logic.md`
- Pitch limitations script: `docs/pitch_model_limitations.md`
- Human-in-the-loop process: `docs/human_in_the_loop_feedback.md`
- Training script: `tools/train_tflite.py`

## Model Assets
- Active model: `assets/model.tflite`
- Active labels: `assets/labels.txt`

Keep the app label order aligned with `assets/labels.txt` after every model export.
