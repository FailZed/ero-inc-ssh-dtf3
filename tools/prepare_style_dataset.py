"""Materialize an explicitly curated dataset; never automatically approve candidates."""
from pathlib import Path
import argparse
import hashlib
import shutil
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import local_character_art as art


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--decisions',type=Path,required=True)
    args = parser.parse_args()
    root = art.ROOT/'training/ero-anime-v1'
    candidates = art.read_json(root/'candidates.json')
    decisions = art.read_json(args.decisions)
    known = {i['id']:i for i in candidates['items']}
    if set(decisions) - set(known):
        raise RuntimeError('Curation contains unknown candidates.')
    accepted=[]
    for name, decision in decisions.items():
        if decision['decision'] != 'accept':
            continue
        item = known[name]
        source = Path(item['source'])
        if sha(source) != item['sha256']:
            raise RuntimeError(f'Source changed: {source}')
        run = art.read_json(Path(item['run']))
        if run['profile']['adult_age'] < 25 or run['model']['sha256'].lower() != '44670e67c55f059116171ee8538875da3abf624fbdaace6d1a7ac2d9617f0211':
            raise RuntimeError('Unexpected age or checkpoint provenance.')
        folder=root/item['split']; folder.mkdir(parents=True,exist_ok=True)
        target=folder/(name+'.png')
        if target.exists() and sha(target) != item['sha256']:
            raise RuntimeError(f'Refusing to replace a different dataset image: {target}')
        shutil.copy2(source,target)
        actual_caption=decision.get('caption',item['caption'])
        if not actual_caption.startswith('eincanime,'):
            raise RuntimeError('Reviewed captions must retain the style trigger.')
        caption=target.with_suffix('.txt'); caption.write_text(actual_caption+'\n',encoding='utf-8')
        accepted.append({**item,'path':str(target),'caption_path':str(caption),
                         'caption':actual_caption,'caption_sha256':sha(caption),'review':decision['reason']})
    # Reject stale files rather than silently training a previous selection.
    expected={i['id']+'.png' for i in accepted if i['split']=='train'}
    actual={p.name for p in (root/'train').glob('*.png')}
    if actual != expected:
        raise RuntimeError('Training folder has stale/missing images; preserve it and version the dataset.')
    manifest={'schema':1,'status':'curated_for_experimental_style_training',
              'trigger':'eincanime','checkpoint_sha256':'44670e67c55f059116171ee8538875da3abf624fbdaace6d1a7ac2d9617f0211',
              'source_kind':'original adult synthetic characters; no official anime images',
              'decisions':str(args.decisions.resolve()),'items':accepted}
    art.write_json(root/'dataset.json',manifest)
    print(f"Curated {len(expected)} training images and {len(accepted)-len(expected)} holdout images.")


if __name__=='__main__':
    main()
