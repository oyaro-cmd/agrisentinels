from pathlib import Path
import csv

root = Path('dataset')
cls_dir = root / 'armyworm'
out_dir = root / '_review'
out_dir.mkdir(parents=True, exist_ok=True)
out_csv = out_dir / 'armyworm_review.csv'

exts = {'.jpg', '.jpeg', '.png', '.bmp', '.gif', '.tif', '.tiff'}

rows = []
for p in cls_dir.rglob('*'):
    if p.is_file() and p.suffix.lower() in exts:
        rows.append([str(p), ''])

with out_csv.open('w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f)
    writer.writerow(['path', 'keep (1=keep, 0=remove)'])
    writer.writerows(rows)

print(f'Wrote {len(rows)} rows to {out_csv}')
