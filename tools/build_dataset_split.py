from pathlib import Path
import argparse
import random
import shutil


EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".gif", ".tif", ".tiff"}


def gather_images(root: Path, class_name: str) -> list[Path]:
    class_dir = root / class_name
    if not class_dir.exists():
        return []
    return [p for p in class_dir.rglob("*") if p.is_file() and p.suffix.lower() in EXTS]


def ensure_clean_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def copy_images(paths: list[Path], out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for src in paths:
        dst = out_dir / src.name
        if dst.exists():
            stem = dst.stem
            suffix = dst.suffix
            i = 1
            while True:
                candidate = out_dir / f"{stem}_{i}{suffix}"
                if not candidate.exists():
                    dst = candidate
                    break
                i += 1
        shutil.copy2(src, dst)


def split_counts(total: int, train_ratio: float, val_ratio: float) -> tuple[int, int, int]:
    n_train = int(total * train_ratio)
    n_val = int(total * val_ratio)
    n_test = total - n_train - n_val
    return n_train, n_val, n_test


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build balanced train/val/test image splits from dataset folders."
    )
    parser.add_argument("--root", default="dataset", help="Source dataset root")
    parser.add_argument("--out", default="dataset_split", help="Output split root")
    parser.add_argument(
        "--classes",
        nargs="+",
        default=["armyworm", "healthy", "leaf blight"],
        help="Class names to include",
    )
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--train", type=float, default=0.7)
    parser.add_argument("--val", type=float, default=0.2)
    parser.add_argument(
        "--max-ratio",
        type=float,
        default=2.0,
        help="Cap largest class to minority*max_ratio before split",
    )
    args = parser.parse_args()

    if args.train + args.val >= 1.0:
        raise SystemExit("train + val must be < 1.0")

    rng = random.Random(args.seed)
    root = Path(args.root)
    out = Path(args.out)

    class_images: dict[str, list[Path]] = {}
    for class_name in args.classes:
        images = gather_images(root, class_name)
        rng.shuffle(images)
        class_images[class_name] = images

    if not class_images:
        raise SystemExit("No classes found")

    min_count = min(len(v) for v in class_images.values() if len(v) > 0)
    cap = int(min_count * args.max_ratio)

    for class_name, images in class_images.items():
        if len(images) > cap:
            class_images[class_name] = images[:cap]

    ensure_clean_dir(out)
    for split in ["train", "val", "test"]:
        (out / split).mkdir(parents=True, exist_ok=True)

    for class_name, images in class_images.items():
        total = len(images)
        n_train, n_val, n_test = split_counts(total, args.train, args.val)
        train_set = images[:n_train]
        val_set = images[n_train : n_train + n_val]
        test_set = images[n_train + n_val : n_train + n_val + n_test]

        copy_images(train_set, out / "train" / class_name)
        copy_images(val_set, out / "val" / class_name)
        copy_images(test_set, out / "test" / class_name)

        print(
            f"{class_name}: total={total}, train={len(train_set)}, "
            f"val={len(val_set)}, test={len(test_set)}"
        )

    print(f"Split dataset written to: {out}")


if __name__ == "__main__":
    main()
