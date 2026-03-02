from pathlib import Path
import argparse
import csv


EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".gif", ".tif", ".tiff"}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create a manual review CSV for one dataset class."
    )
    parser.add_argument("--root", default="dataset", help="Dataset root directory")
    parser.add_argument(
        "--class-name",
        required=True,
        help='Class folder name, e.g. "armyworm" or "leaf blight"',
    )
    parser.add_argument(
        "--out",
        default=None,
        help="Output CSV path. Default: dataset/_review/<class>_review.csv",
    )
    args = parser.parse_args()

    root = Path(args.root)
    class_dir = root / args.class_name
    if not class_dir.exists():
        raise SystemExit(f"Class directory not found: {class_dir}")

    review_dir = root / "_review"
    review_dir.mkdir(parents=True, exist_ok=True)
    default_name = args.class_name.replace(" ", "_").lower() + "_review.csv"
    out_csv = Path(args.out) if args.out else review_dir / default_name

    rows = []
    for path in class_dir.rglob("*"):
        if path.is_file() and path.suffix.lower() in EXTS:
            rows.append([str(path), "", ""])

    with out_csv.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["path", "keep (1=keep, 0=remove)", "notes"])
        writer.writerows(rows)

    print(f"Wrote {len(rows)} rows to {out_csv}")


if __name__ == "__main__":
    main()
