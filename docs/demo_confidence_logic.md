# Demo Confidence Logic

## Purpose
For demo mode, confidence should look realistic and reflect uncertainty, not a fixed high random range.

## Implemented Logic
In `lib/main.dart`, demo confidence is calculated from:
1. top-1 probability
2. margin between top-1 and top-2
3. image quality proxy (simulated)

Formula:
```text
confidence = 0.55 * top1 + 0.35 * margin + 0.10 * quality
```

Where:
- `top1 = highest probability`
- `margin = top1 - top2`
- `quality in [0.85, 1.00]` for demo simulation

Final confidence is clamped to `0-100%`.

## Safety Threshold
- If confidence `< 60%`, predicted class is replaced with `Unknown`.

## Why This Is Better
- Produces low confidence when class probabilities are close.
- Avoids unrealistic `85-99%` confidence for every simulated case.
- Mirrors how uncertainty should appear in production-like UX.
