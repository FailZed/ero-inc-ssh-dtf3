"""Create original technical OpenPose body guides, never donor character pixels.

No facial mesh: only the standard five head landmarks, shoulders and limbs.
Guides are constraints, not finished game art.
"""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image, ImageDraw

SIZES = {
    'female': {'slim': (156, 138), 'average': (176, 156), 'toned': (174, 148),
               'athletic': (194, 166), 'strong': (204, 164), 'curvy': (176, 184),
               'soft': (184, 182), 'pear': (158, 196)},
    'male': {'slim': (174, 140), 'average': (198, 164), 'toned': (212, 156),
             'athletic': (232, 164), 'muscular': (264, 180), 'broad': (260, 198),
             'soft': (224, 194), 'solid': (256, 210)},
}
COLORS = [(255, 0, 0), (255, 85, 0), (255, 170, 0), (255, 255, 0),
          (170, 255, 0), (85, 255, 0), (0, 255, 0), (0, 255, 85),
          (0, 255, 170), (0, 255, 255), (0, 170, 255), (0, 85, 255),
          (0, 0, 255), (85, 0, 255), (170, 0, 255), (255, 0, 255),
          (255, 0, 170), (255, 0, 85)]
EDGES = [(1, 2), (1, 5), (2, 3), (3, 4), (5, 6), (6, 7),
         (1, 8), (8, 9), (9, 10), (1, 11), (11, 12), (12, 13),
         (1, 0), (0, 14), (14, 16), (0, 15), (15, 17)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('target', type=Path)
    args = parser.parse_args()
    args.target.mkdir(parents=True, exist_ok=False)
    records = []
    for gender, builds in SIZES.items():
        for build, (shoulder, hip) in builds.items():
            cx = 384
            points = [(cx, 156), (cx, 276),
                      (cx-shoulder/2, 288), (cx-shoulder/2-30, 520), (cx-shoulder/2-44, 744),
                      (cx+shoulder/2, 288), (cx+shoulder/2+30, 520), (cx+shoulder/2+44, 744),
                      (cx-hip/2, 724), (cx-hip*0.48, 990), (cx-hip/2, 1220),
                      (cx+hip/2, 724), (cx+hip*0.48, 990), (cx+hip/2, 1220),
                      (cx-20, 146), (cx+20, 146), (cx-44, 158), (cx+44, 158)]
            canvas = Image.new('RGB', (768, 1344))
            draw = ImageDraw.Draw(canvas)
            for index, (a, b) in enumerate(EDGES):
                color = tuple(round(v*0.6) for v in COLORS[index])
                draw.line([points[a], points[b]], fill=color, width=8)
            for point, color in zip(points, COLORS):
                x, y = point
                draw.ellipse((x-5, y-5, x+5, y+5), fill=color)
            name = gender + '_' + build
            target = args.target / (name + '.png')
            canvas.save(target)
            records.append(dict(id=name, shoulder_joint_span=shoulder, hip_joint_span=hip,
                                points=points, sha256=hashlib.sha256(target.read_bytes()).hexdigest()))
    (args.target / 'guides.json').write_text(json.dumps(dict(
        provenance='Original technical rig coordinates; standard OpenPose encoding; no donor imagery',
        purpose='Neutral frontal adult body constraints, not finished character art',
        canvas=[768, 1344], records=records), indent=2) + '\n', encoding='utf-8')
    print(f'Prepared {len(records)} original pose guides at {args.target}')


if __name__ == '__main__':
    main()
