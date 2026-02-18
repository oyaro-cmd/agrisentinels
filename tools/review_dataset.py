import argparse
import random
from pathlib import Path
from PIL import Image

EXTS = {'.jpg', '.jpeg', '.png', '.bmp', '.gif', '.tif', '.tiff'}


def iter_images(root, classes):
    for cls in classes:
        cls_dir = root / cls
        if not cls_dir.exists():
            continue
        for p in cls_dir.rglob('*'):
            if p.is_file() and p.suffix.lower() in EXTS:
                yield cls, p


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', default='dataset')
    parser.add_argument('--class', dest='cls', default=None)
    parser.add_argument('--shuffle', action='store_true')
    parser.add_argument('--limit', type=int, default=0)
    args = parser.parse_args()

    root = Path(args.root)
    classes = ['healthy', 'armyworm', 'leaf blight']
    if args.cls:
        classes = [args.cls]

    items = list(iter_images(root, classes))
    if args.shuffle:
        random.shuffle(items)

    total = len(items) if args.limit <= 0 else min(args.limit, len(items))
    print(f'Reviewing {total} images from {root}')
    print('Controls:')
    print('  Enter = next | d = mark delete | q = quit')

    to_quarantine = []
    for i, (cls, path) in enumerate(items[:total], 1):
        img = Image.open(path).convert('RGB')
        img.show()
        resp = input(f'[{i}/{total}] {cls} :: {path} > ').strip().lower()
        if resp == 'q':
            break
        if resp == 'd':
            to_quarantine.append((cls, path))

    if not to_quarantine:
        print('No files marked for quarantine.')
        return

    quarantine = root / '_quarantine' / 'manual'
    for cls, path in to_quarantine:
        dst = quarantine / cls
        dst.mkdir(parents=True, exist_ok=True)
        path.rename(dst / path.name)

    print(f'Moved {len(to_quarantine)} files to {quarantine}')


if __name__ == '__main__':
    main()
