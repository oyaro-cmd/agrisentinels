from pathlib import Path
import csv
import shutil

root = Path('dataset')
review_csv = root / '_review' / 'armyworm_review.csv'
quarantine = root / '_quarantine' / 'armyworm_no_worm'
quarantine.mkdir(parents=True, exist_ok=True)

if not review_csv.exists():
    raise SystemExit(f'Missing {review_csv}')

moved = 0
kept = 0

with review_csv.open('r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        path = Path(row['path'])
        keep = row['keep (1=keep, 0=remove)'].strip()
        if not path.exists():
            continue
        if keep == '0':
            dst = quarantine / path.name
            shutil.move(str(path), str(dst))
            moved += 1
        elif keep == '1':
            kept += 1

print(f'Moved {moved} files to {quarantine}')
print(f'Kept {kept} files')
