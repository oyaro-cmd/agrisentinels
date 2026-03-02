# Label and Model Workflow

This workflow is for improving model quality before each retraining cycle.

## 1) Create review sheets per class
Generate review CSV:

```bash
python tools/create_review_csv.py --class-name "armyworm"
python tools/create_review_csv.py --class-name "leaf blight"
python tools/create_review_csv.py --class-name "healthy"
```

Each CSV is created in `dataset/_review/`.

## 2) Manually review labels
In each CSV:
- set `keep (1=keep, 0=remove)` to `1` for correct images
- set to `0` for wrong/noisy images
- optional notes in `notes`

## 3) Apply review decisions
Move rejected samples to quarantine:

```bash
python tools/apply_review_csv.py --csv dataset/_review/armyworm_review.csv
python tools/apply_review_csv.py --csv dataset/_review/leaf_blight_review.csv
python tools/apply_review_csv.py --csv dataset/_review/healthy_review.csv
```

Rejected files are moved to `dataset/_quarantine/manual/`.

## 4) Build balanced split
Create train/val/test with max class ratio 2x:

```bash
python tools/build_dataset_split.py --root dataset --out dataset_split --max-ratio 2.0
```

Output folders:
- `dataset_split/train/<class>`
- `dataset_split/val/<class>`
- `dataset_split/test/<class>`

## 5) Train model
Use:

```bash
python tools/train_tflite.py
```

Training output in `model_artifacts/`.

## 6) Evaluate model before deployment
Run TFLite evaluation with confusion matrix:

```bash
python tools/eval_tflite.py --model model_artifacts/model.tflite --labels model_artifacts/labels.txt --data dataset_split/test
```

Inspect:
- overall accuracy
- per-class precision/recall
- `model_artifacts/misclassified.csv`

Do not deploy if one class regresses significantly.

## 7) Deploy model to app
Copy:
- `model_artifacts/model.tflite` -> `assets/model.tflite`
- `model_artifacts/labels.txt` -> `assets/labels.txt`

Then rebuild app:

```bash
flutter clean
flutter pub get
flutter run -d <device_id>
```
