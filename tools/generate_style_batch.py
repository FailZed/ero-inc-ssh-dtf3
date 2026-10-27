"""Generate resumable style candidates. Curation is a separate explicit step."""
from pathlib import Path
import argparse
import datetime as dt
import hashlib
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
import local_character_art as art


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=art.PROJECT/'docs/art/characters-v2/dataset-profiles.json')
    parser.add_argument('--limit', type=int)
    parser.add_argument('--index',type=Path,help='Separate resumable candidate index for a production family')
    args = parser.parse_args()
    config = art.read_json(args.config)
    digest = hashlib.sha256(args.config.read_bytes()).hexdigest()
    index_path = args.index or art.ROOT/'training/ero-anime-v1/candidates.json'
    index = art.read_json(index_path) if index_path.exists() else {
        'schema':1, 'config_sha256':digest, 'status':'uncurated', 'items':[]}
    if index['config_sha256'] != digest:
        # Pending prompts may evolve, but every completed image must still match
        # its recorded graph exactly. Never silently reinterpret an existing run.
        for item in index['items']:
            recorded=art.read_json(Path(item['run']))
            if art.graph(config,art.selected(config,item['id'])) != recorded['prompt']:
                raise RuntimeError(f"Completed prompt changed: {item['id']}; start a new dataset version.")
        index.setdefault('previous_config_hashes',[]).append(index['config_sha256'])
        index['config_sha256']=digest
    completed = {i['id'] for i in index['items']}
    pending = [p for p in config['profiles'] if p['id'] not in completed]
    if args.limit is not None:
        pending = pending[:args.limit]
    for profile in pending:
        if index_path.with_name('PAUSE').exists():
            index['status']='paused_between_jobs'
            art.write_json(index_path,index)
            return
        try:
            run = art.generate(config, profile['id'], None, True)
        except art.ProductionWindowEnded:
            index['status']='deadline_reached';art.write_json(index_path,index);return
        output = run['history']['outputs']['9']['images'][0]
        source = art.ROOT/'output'/output['subfolder']/output['filename']
        index['items'].append({
            'id':profile['id'], 'split':profile['split'], 'source':str(source),
            'sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
            'caption':profile['caption'], 'run':str(art.ROOT/'runs'/f"{run['prompt_id']}.json"),
            'curation':'unreviewed', 'seed':profile['seed']})
        index['updated_utc'] = dt.datetime.now(dt.timezone.utc).isoformat()
        art.write_json(index_path, index)
        print(f"Recorded {len(index['items'])}/{len(config['profiles'])} candidates", flush=True)
    index['status']='completed_candidates_require_review' if len(index['items'])==len(config['profiles']) else 'partial_candidates_require_review'
    art.write_json(index_path,index)


if __name__ == '__main__':
    main()
