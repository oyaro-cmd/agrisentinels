from pathlib import Path
import argparse
import csv
import math

import numpy as np
from PIL import Image
import tensorflow as tf


EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".gif", ".tif", ".tiff"}


def canonical(name: str) -> str:
    return " ".join(name.lower().replace("_", " ").replace("-", " ").split())


def title_label(label: str) -> str:
    parts = canonical(label).split(" ")
    return " ".join(p.capitalize() for p in parts if p)


def tensor_type_name(tensor_type) -> str:
    try:
        return np.dtype(tensor_type).name.lower()
    except Exception:
        return str(tensor_type).lower()


def load_labels(path: Path) -> list[str]:
    labels = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        tokens = line.split(maxsplit=1)
        label = tokens[1] if len(tokens) > 1 and tokens[0].isdigit() else line
        labels.append(title_label(label))
    if not labels:
        raise RuntimeError("No labels found")
    return labels


def softmax(values: list[float]) -> list[float]:
    m = max(values)
    exps = [math.exp(v - m) for v in values]
    s = sum(exps)
    return [v / s for v in exps]


def ensure_probabilities(values: list[float]) -> list[float]:
    in_range = all(0.0 <= v <= 1.0 for v in values)
    s = sum(values)
    if in_range and abs(s - 1.0) <= 0.05:
        return values
    return softmax(values)


def quantize(value: float, scale: float, zero_point: int, lo: int, hi: int) -> int:
    if scale == 0:
        return max(lo, min(hi, int(round(value))))
    q = int(round(value / scale + zero_point))
    return max(lo, min(hi, q))


def preprocess_image(
    image_path: Path,
    width: int,
    height: int,
    input_type,
    input_scale: float,
    input_zero: int,
):
    image = Image.open(image_path).convert("RGB").resize((width, height), Image.BILINEAR)
    arr = np.asarray(image, dtype=np.uint8)
    rgb = arr.reshape(-1, 3)

    dtype_name = tensor_type_name(input_type)

    if dtype_name == "float32":
        x = (rgb.astype(np.float32) / 127.5) - 1.0
        return x.reshape(1, height, width, 3).astype(np.float32)

    if dtype_name == "uint8":
        q = np.zeros_like(rgb, dtype=np.uint8)
        for i in range(rgb.shape[0]):
            r = (float(rgb[i, 0]) / 127.5) - 1.0
            g = (float(rgb[i, 1]) / 127.5) - 1.0
            b = (float(rgb[i, 2]) / 127.5) - 1.0
            q[i, 0] = quantize(r, input_scale, input_zero, 0, 255)
            q[i, 1] = quantize(g, input_scale, input_zero, 0, 255)
            q[i, 2] = quantize(b, input_scale, input_zero, 0, 255)
        return q.reshape(1, height, width, 3).astype(np.uint8)

    if dtype_name == "int8":
        q = np.zeros_like(rgb, dtype=np.int8)
        for i in range(rgb.shape[0]):
            r = (float(rgb[i, 0]) / 127.5) - 1.0
            g = (float(rgb[i, 1]) / 127.5) - 1.0
            b = (float(rgb[i, 2]) / 127.5) - 1.0
            q[i, 0] = quantize(r, input_scale, input_zero, -128, 127)
            q[i, 1] = quantize(g, input_scale, input_zero, -128, 127)
            q[i, 2] = quantize(b, input_scale, input_zero, -128, 127)
        return q.reshape(1, height, width, 3).astype(np.int8)

    raise RuntimeError(f"Unsupported input tensor type: {input_type}")


def output_scores(raw, output_type, output_scale: float, output_zero: int) -> list[float]:
    dtype_name = tensor_type_name(output_type)

    if dtype_name == "float32":
        values = np.asarray(raw, dtype=np.float32).flatten().tolist()
        return ensure_probabilities(values)

    if dtype_name in {"uint8", "int8"}:
        quantized = np.asarray(raw).flatten().tolist()
        if output_scale == 0:
            values = [float(v) for v in quantized]
        else:
            values = [(float(v) - output_zero) * output_scale for v in quantized]
        return ensure_probabilities(values)

    raise RuntimeError(f"Unsupported output tensor type: {output_type}")


def gather_samples(root: Path) -> list[tuple[Path, str]]:
    samples = []
    for class_dir in root.iterdir():
        if not class_dir.is_dir():
            continue
        class_name = canonical(class_dir.name)
        for p in class_dir.rglob("*"):
            if p.is_file() and p.suffix.lower() in EXTS:
                samples.append((p, class_name))
    return samples


def main() -> None:
    parser = argparse.ArgumentParser(description="Evaluate a TFLite model with confusion matrix")
    parser.add_argument("--model", default="assets/model.tflite")
    parser.add_argument("--labels", default="assets/labels.txt")
    parser.add_argument("--data", default="dataset_split/test")
    parser.add_argument("--out-misclassified", default="model_artifacts/misclassified.csv")
    args = parser.parse_args()

    model_path = Path(args.model)
    labels_path = Path(args.labels)
    data_path = Path(args.data)
    out_csv = Path(args.out_misclassified)
    out_csv.parent.mkdir(parents=True, exist_ok=True)

    labels = load_labels(labels_path)
    label_canon = [canonical(l) for l in labels]
    label_to_idx = {name: i for i, name in enumerate(label_canon)}

    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()
    input_info = interpreter.get_input_details()[0]
    output_info = interpreter.get_output_details()[0]

    input_shape = input_info["shape"]
    height, width = int(input_shape[1]), int(input_shape[2])
    input_type = input_info["dtype"]
    input_scale, input_zero = input_info["quantization"]
    output_type = output_info["dtype"]
    output_scale, output_zero = output_info["quantization"]

    samples = gather_samples(data_path)
    if not samples:
        raise RuntimeError(f"No samples found in {data_path}")

    n = len(labels)
    confusion = [[0 for _ in range(n)] for _ in range(n)]
    misclassified_rows = []
    correct = 0
    used = 0

    for image_path, gt_name in samples:
        if gt_name not in label_to_idx:
            continue
        gt_idx = label_to_idx[gt_name]
        x = preprocess_image(
            image_path,
            width,
            height,
            input_type,
            float(input_scale),
            int(input_zero),
        )

        output_dtype_name = tensor_type_name(output_type)
        if output_dtype_name == "float32":
            out = np.zeros((1, n), dtype=np.float32)
        elif output_dtype_name == "uint8":
            out = np.zeros((1, n), dtype=np.uint8)
        else:
            out = np.zeros((1, n), dtype=np.int8)

        interpreter.set_tensor(input_info["index"], x)
        interpreter.invoke()
        out = interpreter.get_tensor(output_info["index"])
        probs = output_scores(out, output_type, float(output_scale), int(output_zero))

        pred_idx = int(np.argmax(probs))
        pred_conf = probs[pred_idx] * 100.0
        confusion[gt_idx][pred_idx] += 1
        used += 1
        if pred_idx == gt_idx:
            correct += 1
        else:
            misclassified_rows.append(
                [
                    str(image_path),
                    labels[gt_idx],
                    labels[pred_idx],
                    f"{pred_conf:.2f}",
                ]
            )

    accuracy = (correct / used) if used else 0.0
    print(f"Samples evaluated: {used}")
    print(f"Accuracy: {accuracy:.4f}")
    print("Labels order:", labels)
    print("Confusion matrix (rows=actual, cols=predicted):")
    for row in confusion:
        print(" ".join(f"{v:5d}" for v in row))

    print("Per-class metrics:")
    for i, label in enumerate(labels):
        tp = confusion[i][i]
        fn = sum(confusion[i]) - tp
        fp = sum(confusion[r][i] for r in range(n)) - tp
        precision = tp / (tp + fp) if (tp + fp) else 0.0
        recall = tp / (tp + fn) if (tp + fn) else 0.0
        print(f"- {label}: precision={precision:.4f}, recall={recall:.4f}")

    with out_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["path", "actual", "predicted", "pred_confidence"])
        writer.writerows(misclassified_rows)
    print(f"Misclassified rows written to: {out_csv}")


if __name__ == "__main__":
    main()
