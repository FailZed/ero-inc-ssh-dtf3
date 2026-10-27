"""Read original sprite anatomy anchors locally with DWPose/ONNX CPU.

Landmarks are proposals for mask/export review, not automatic anatomy approval.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path('E:/Ai/ComfyUI-EroInc')
os.environ.setdefault('OMP_NUM_THREADS', '4')
os.environ.setdefault('TEMP', str(ROOT / 'temp'))
os.environ.setdefault('TMP', str(ROOT / 'temp'))

import numpy as np
import onnxruntime as ort
from PIL import Image, ImageDraw

NAMES = ['nose', 'left_eye', 'right_eye', 'left_ear', 'right_ear',
         'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow',
         'left_wrist', 'right_wrist', 'left_hip', 'right_hip',
         'left_knee', 'right_knee', 'left_ankle', 'right_ankle']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('target', type=Path)
    parser.add_argument('--overlay', type=Path)
    args = parser.parse_args()
    if args.target.exists():
        raise ValueError('Preserve previous anchors; choose a new output path.')
    source = Image.open(args.source).convert('RGBA')
    background = Image.new('RGBA', source.size, '#eeeeec')
    background.alpha_composite(source)
    rgb = np.asarray(background.convert('RGB'))
    model = ROOT / 'models/pose/dwpose/dw-ll_ucoco_384.onnx'
    implementation = ROOT / 'postprocess/vendor/DWPose/ControlNet-v1-1-nightly/annotator/dwpose/onnxpose.py'
    spec = importlib.util.spec_from_file_location('ero_dwpose_inference', implementation)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    options = ort.SessionOptions()
    options.intra_op_num_threads = 4
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(str(model), sess_options=options, providers=['CPUExecutionProvider'])
    bounds = source.getchannel('A').point(lambda x: 255 if x >= 16 else 0).getbbox()
    keypoints, scores = module.inference_pose(session, [list(bounds)], rgb[:, :, ::-1].copy())
    points, confidence = np.asarray(keypoints)[0], np.asarray(scores)[0]
    named = {name: dict(xy=[float(v) for v in points[i]], score=float(confidence[i])) for i, name in enumerate(NAMES)}
    shoulder = (points[5] + points[6]) / 2
    hip = (points[11] + points[12]) / 2
    ankle = (points[15] + points[16]) / 2
    height = float(hip[1] - shoulder[1])
    shoulder_span = float(abs(points[5, 0] - points[6, 0]))
    hip_span = float(abs(points[11, 0] - points[12, 0]))
    neck_y = round(float(shoulder[1]) - height * 0.055)
    hand_boxes = []
    for lo, hi in ((91, 112), (112, 133)):
        hand = points[lo:hi][confidence[lo:hi] >= 0.3]
        hand_boxes.append([float(x) for x in [hand[:, 0].min()-10, hand[:, 1].min()-10,
                                              hand[:, 0].max()+10, hand[:, 1].max()+10]] if len(hand) >= 5 else None)
    result = dict(schema=1, source=str(args.source.resolve()),
                  source_sha256=hashlib.sha256(args.source.read_bytes()).hexdigest(), canvas=list(source.size),
                  model=str(model), model_sha256=hashlib.sha256(model.read_bytes()).hexdigest(),
                  implementation_sha256=hashlib.sha256(implementation.read_bytes()).hexdigest(),
                  provider='CPUExecutionProvider', provenance='Official IDEA-Research DWPose ONNX inference, Apache-2.0',
                  landmarks=named, all_keypoints=points.tolist(), all_scores=confidence.tolist(),
                  proposed_neck_y=neck_y, shoulder_span=shoulder_span, hip_span=hip_span,
                  shoulder_y=float(shoulder[1]), hip_y=float(hip[1]), ankle_y=float(ankle[1]),
                  hands=hand_boxes, status='landmark_candidate_requires_overlay_review')
    args.target.parent.mkdir(parents=True, exist_ok=True)
    args.target.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    if args.overlay:
        overlay = background.convert('RGB')
        draw = ImageDraw.Draw(overlay)
        for i in range(17):
            if confidence[i] >= 0.3:
                x, y = points[i]
                draw.ellipse((x-4, y-4, x+4, y+4), fill='#f38940')
        draw.line([(0, neck_y), (source.width-1, neck_y)], fill='#36bce8', width=2)
        for hand in hand_boxes:
            if hand:
                draw.rectangle(hand, outline='#36bce8', width=2)
        args.overlay.parent.mkdir(parents=True, exist_ok=True)
        overlay.save(args.overlay)
    print(json.dumps({k: result[k] for k in ('canvas', 'proposed_neck_y', 'shoulder_span', 'hip_span', 'ankle_y')}))


if __name__ == '__main__':
    main()
