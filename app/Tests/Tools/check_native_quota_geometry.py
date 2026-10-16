"""Quantify exported native Canvas pixels, independently of the Swift painters.
Run with bundled Python/Pillow: script EXPORT_DIRECTORY OUTPUT_JSON.
This reads isolated native images; it does not contact a device or any account.
"""
import json, math, re, sys
from pathlib import Path
import numpy as np
from PIL import Image

source, output = map(Path, sys.argv[1:])
images = {}
for test in json.loads((source / 'manifest.json').read_text()):
    for a in test['attachments']:
        name = re.sub(r'_0_[0-9A-Fa-f-]{36}', '', a['suggestedHumanReadableName'])
        m = re.fullmatch(r'G(\d+)-(light|dark)-(app|widget)-(week|five)-([\d.]+)-phase([\d.]+)', name)
        if m:
            task, theme, density, window, value, phase = m.groups()
            key = (int(task), theme, density, window, float(value), float(phase))
            images[key] = np.array(Image.open(source / a['exportedFileName']).convert('RGB')).astype(np.int16)
assert len(images) == 594, f'Expected 594 actual native graphs; got {len(images)}'
checks = []
for key, actual in images.items():
    task, theme, density, window, value, phase = key
    base = images[(task, theme, density, window, 0.0, 0.0)]
    full = images[(task, theme, density, window, 100.0, 0.0)]
    h, w, _ = actual.shape
    boundary = value / 100 * w
    result = dict(task=f'T{task}', theme=theme, density=density, window=window, remaining=value, phase=phase)
    if task == 69:
        # Probe the centre of the 270-degree measuring arc; exclude the needle's
        # finite stroke and terminal antialiasing, not the measured arc itself.
        r = w * 90 / 240
        cx, cy = w / 2, w * 116 / 240
        errors, probes = 0, 0
        for percent in np.arange(.05, 100, .25):
            if min(percent, abs(percent-value), abs(percent-100)) < 1.2:
                continue
            a = math.radians(135 + percent * 2.7)
            x, y = int(round(cx+r*math.cos(a))), int(round(cy+r*math.sin(a)))
            reference = full[y, x] if percent < value else base[y, x]
            errors += int(np.max(np.abs(actual[y,x] - reference)) > 12)
            probes += 1
        result.update(check='continuous arc', probes=probes, mismatched=errors, passed=errors == 0)
    elif task == 72:
        # The inner vessel is 200 x 62 in a 240 x 110 SVG, excluding the shell.
        x0, x1 = int(round(w*20/240)), int(round(w*220/240))
        y0, y1 = int(round(w*24/240)), int(round(w*86/240))
        region = actual[y0:y1,x0:x1]
        # Green fluid and its white bubbles have G distinctly above B. This also
        # excludes neutral used pixels in both approved palettes.
        mask = (region[:,:,1] - region[:,:,2] > 12) & (region[:,:,1] - region[:,:,0] > 12)
        fraction = float(mask.mean())
        error = abs(fraction - value/100)
        result.update(check='average fluid area', measuredPercent=round(fraction*100,6), errorPercentagePoints=round(error*100,6), passed=error <= .006)
    elif task in (67,77):
        # Capsule round ends affect area, so use the central measuring axis.
        y = h//2
        changed = np.max(np.abs(actual[y] - base[y]),axis=1) > 6
        xs = np.where(changed)[0]
        end = float(xs[-1]+.5) if len(xs) else 0
        if value == 100:
            # Full capsule's outer cap ends at width with raster antialiasing.
            end = float(xs[-1]+.5)
        error = abs(end-boundary)
        result.update(check='capsule centre axis', lastActivePixel=end, targetPixel=boundary, errorPixels=round(error,6), passed=error <= 1.6)
    else:
        # Compare actual fill against separately rendered 0/100 references.
        # A clip at an exact x produces 100-reference pixels to its left and
        # 0-reference pixels to its right. Skip only its narrow AA edge (glass
        # additionally has a 16/1000-wide moving end cap).
        band = 15 if task == 75 else 2
        left = max(0,int(math.floor(boundary-band)))
        right = min(w,int(math.ceil(boundary+band)))
        errors_left = int(np.sum(np.max(np.abs(actual[:,:left]-full[:,:left]),axis=2) > 12)) if left else 0
        errors_right = int(np.sum(np.max(np.abs(actual[:,right:]-base[:,right:]),axis=2) > 12)) if right<w else 0
        result.update(check='continuous prefix', leftMismatchedPixels=errors_left, rightMismatchedPixels=errors_right, passed=errors_left == 0 and errors_right == 0)
    checks.append(result)
failures=[x for x in checks if not x['passed']]
output.write_text(json.dumps(dict(environment='iPhone 11/iOS26.5 native Canvas, no desktop host', actualImageCount=len(images), checks=checks, failed=failures),ensure_ascii=False,indent=2)+'\n')
print(json.dumps(dict(actualImageCount=len(images), passed=len(checks)-len(failures), failed=len(failures), examples=failures[:6]),ensure_ascii=False))
if failures: sys.exit(1)
