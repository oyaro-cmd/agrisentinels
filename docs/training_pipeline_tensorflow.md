# TensorFlow Training Pipeline

## Prerequisites
- Python `3.10+`
- `pip install tensorflow`
- Clean dataset in `dataset_clean/` with class subfolders:
- `dataset_clean/armyworm`
- `dataset_clean/healthy`
- `dataset_clean/leaf blight`

## Run
```bash
python tools/train_tflite.py
```

## Outputs
Written to `model_artifacts/`:
- `model.keras`
- `model.tflite` (float)
- `model_quant.tflite` (dynamic range quantized)
- `labels.txt`

## Deploy to Flutter App
1. Copy `model_artifacts/model.tflite` to `assets/model.tflite`.
2. Copy `model_artifacts/labels.txt` to `assets/labels.txt`.
3. Ensure app label list order exactly matches `labels.txt`.
4. Rebuild app:
```bash
flutter clean
flutter pub get
flutter run -d <device_id>
```

## Validation Baseline
Record at minimum:
- validation accuracy
- per-class precision/recall (external evaluation script)
- confusion matrix on holdout set

Do not promote a new model unless it outperforms the previous model on the same fixed holdout set.
