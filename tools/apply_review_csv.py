from pathlib import Path
import argparse
import csv
import shutil


def safe_destination(path: Path) -> Path:
    if not path.exists():
        return path
    stem = path.stem
    suffix = path.suffix
    parent = path.parent
    i = 1
    while True:
        candidate = parent / f"{stem}_{i}{suffix}"
        if not candidate.exists():
            return candidate
        i += 1


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Apply manual review CSV and quarantine rows marked keep=0."
    )
    parser.add_argument(
        "--csv",
        required=True,
        help="Path to review CSV created by create_review_csv.py",
    )
    parser.add_argument(
        "--root",
        default="dataset",
        help="Dataset root (used for relative path checks and quarantine)",
    )
    parser.add_argument(
        "--quarantine-subdir",
        default="manual",
        help="Subfolder under dataset/_quarantine",
    )
    args = parser.parse_args()

    csv_path = Path(args.csv)
    root = Path(args.root).resolve()
    if not csv_path.exists():
        raise SystemExit(f"CSV not found: {csv_path}")

    quarantine_base = root / "_quarantine" / args.quarantine_subdir
    quarantine_base.mkdir(parents=True, exist_ok=True)

    moved = 0
    kept = 0
    missing = 0
    skipped = 0

    with csv_path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw_path = (row.get("path") or "").strip()
            keep_flag = (row.get("keep (1=keep, 0=remove)") or "").strip()
            if not raw_path:
                skipped += 1
                continue

            src = Path(raw_path)
            if not src.exists():
                missing += 1
                continue

            if keep_flag == "1":
                kept += 1
                continue

            if keep_flag != "0":
                skipped += 1
                continue

            try:
                rel = src.resolve().relative_to(root)
                class_name = rel.parts[0] if rel.parts else "unknown"
            except ValueError:
                class_name = "external"

            dst_dir = quarantine_base / class_name
            dst_dir.mkdir(parents=True, exist_ok=True)
            dst = safe_destination(dst_dir / src.name)
            shutil.move(str(src), str(dst))
            moved += 1

    print(f"Moved: {moved}")
    print(f"Kept: {kept}")
    print(f"Missing: {missing}")
    print(f"Skipped: {skipped}")
    print(f"Quarantine: {quarantine_base}")


if __name__ == "__main__":
    main()
