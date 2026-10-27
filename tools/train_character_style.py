"""Run the pinned local SDXL trainer on the curated EroInc style dataset."""
from pathlib import Path
import argparse
import datetime as dt
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
sys.path.insert(0,str(Path(__file__).resolve().parent))
import local_character_art as art


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--steps',type=int,default=400)
    parser.add_argument('--preflight',action='store_true',help='Two hardware steps, not a production adapter')
    parser.add_argument('--dataset-root',type=Path)
    parser.add_argument('--name',default='ero_inc_anime_v1')
    parser.add_argument('--rank',type=int,default=16)
    parser.add_argument('--alpha',type=int,default=8)
    parser.add_argument('--learning-rate',type=float,default=.00008)
    parser.add_argument('--masked-loss',action='store_true')
    parser.add_argument('--base-style-weight',type=float,default=0)
    args=parser.parse_args()
    art.check_production_window(minimum_remaining_seconds=max(900,args.steps*2))
    root=art.ROOT/'training'; dataset_root=args.dataset_root or root/'ero-anime-v1'
    if not dataset_root.resolve().is_relative_to(root.resolve()):raise ValueError('Training data and output must remain on E: inside training/')
    if not args.name.replace('_','').isalnum() or args.rank<1 or args.alpha<1 or not 0<=args.base_style_weight<=1:raise ValueError('Invalid adapter parameters')
    data=art.read_json(dataset_root/'dataset.json')
    train=[i for i in data['items'] if i['split']=='train']
    if len(train)<16 and not args.preflight:
        raise RuntimeError('At least 16 reviewed images are required for this experimental style run.')
    for item in data['items']:
        for key,hashkey in [('path','sha256'),('caption_path','caption_sha256')]:
            if hashlib.sha256(Path(item[key]).read_bytes()).hexdigest()!=item[hashkey]:
                raise RuntimeError(f"Dataset changed: {item[key]}")
    art.verify_model(art.read_json(art.PROJECT/'docs/art/characters-v2/dataset-profiles.json'))
    server_online=True
    try:
        queue=art.api('/queue')
        if queue['queue_running'] or queue['queue_pending']:
            raise RuntimeError('ComfyUI has work queued; finish it before training.')
    except urllib.error.URLError as error:
        if not isinstance(error.reason,ConnectionRefusedError):
            raise
        server_online=False
    name='hardware_probe' if args.preflight else args.name
    folder=dataset_root/name
    folder.mkdir(parents=True,exist_ok=True)
    if (folder/(name+'.safetensors')).exists():
        raise RuntimeError('Adapter already exists; preserve the run and choose a new version.')
    config={'general':{'caption_extension':'.txt','shuffle_caption':False},
            'datasets':[{'resolution':[768,1024],'batch_size':1,'enable_bucket':True,
                         'min_bucket_reso':512,'max_bucket_reso':1152,'bucket_reso_steps':64,
                         'subsets':[{'image_dir':str(dataset_root/'train'),'num_repeats':1,'alpha_mask':args.masked_loss}]}]}
    art.write_json(folder/'dataset-config.json',config)
    checkpoint=art.ROOT/'runtime/ComfyUI_windows_portable/ComfyUI/models/checkpoints/DasiwaIllustriousAnime_epitaphecstasy.safetensors'
    command=[str(root/'venv/Scripts/python.exe'),'-u',str(art.PROJECT/'tools/run_sdxl_budgeted.py'),
             '--pretrained_model_name_or_path',str(checkpoint),'--dataset_config',str(folder/'dataset-config.json'),
             '--output_dir',str(folder),'--output_name',name,'--save_model_as','safetensors',
             '--network_module','networks.lora','--network_dim',str(args.rank),'--network_alpha',str(args.alpha),'--network_train_unet_only',
             '--learning_rate',str(args.learning_rate),'--unet_lr',str(args.learning_rate),'--optimizer_type','AdamW',
             '--lr_scheduler','constant','--max_train_steps',str(2 if args.preflight else args.steps),
             '--mixed_precision','bf16','--save_precision','bf16','--gradient_checkpointing','--sdpa','--no_half_vae',
             '--cache_latents','--cache_latents_to_disk','--vae_batch_size','1',
             '--cache_text_encoder_outputs','--cache_text_encoder_outputs_to_disk',
             '--max_data_loader_n_workers','0','--seed','9812026',
             '--tokenizer_cache_dir',str(root/'tokenizers'),'--logging_dir',str(folder/'tensorboard'),
             '--log_with','tensorboard','--save_every_n_steps','100',
             '--metadata_title','EroInc original adult anime style calibration',
             '--training_comment','Synthetic adult EroInc style experiment; requires heldout visual validation.']
    if args.masked_loss:
        if not data.get('body_loss_masks'):raise ValueError('Masked training requires a recorded body-only loss-mask dataset')
        command.append('--masked_loss')
    if args.base_style_weight:
        adapter=art.ROOT/'runtime/ComfyUI_windows_portable/ComfyUI/models/loras/EroInc/candidate_400.safetensors'
        if hashlib.sha256(adapter.read_bytes()).hexdigest()!='2da68309cba8e4613d0fbf8c15fb64d60fafc5bea3b9b5a791cca8cd3f225cb9':raise ValueError('Frozen style adapter checksum mismatch')
        command+=['--base_weights',str(adapter),'--base_weights_multiplier',str(args.base_style_weight)]
    env=os.environ.copy()
    env.update({'PYTHONIOENCODING':'utf-8','OMP_NUM_THREADS':'4','MKL_NUM_THREADS':'4',
                'TEMP':str(art.ROOT/'temp'),'TMP':str(art.ROOT/'temp'),
                'HF_HOME':str(root/'cache/huggingface'),'TORCH_HOME':str(root/'cache/torch'),
                'XDG_CACHE_HOME':str(root/'cache'),'HF_HUB_OFFLINE':'1',
                'TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL':'1'})
    art.write_json(folder/'launch.json',{'command':command,'created_utc':dt.datetime.now(dt.timezone.utc).isoformat(),
                                       'dataset_sha256':hashlib.sha256((dataset_root/'dataset.json').read_bytes()).hexdigest(),
                                       'preflight_only':args.preflight})
    # Stop only our server after checking its PID, executable and main script.
    # This avoids changing the user's PowerShell execution policy.
    import psutil
    pid_file=art.ROOT/'comfyui.pid'
    if server_online and not pid_file.exists():
        raise RuntimeError('Cannot identify our ComfyUI process; stop it explicitly before training.')
    if server_online:
        server=psutil.Process(int(pid_file.read_text().strip()))
        portable=art.ROOT/'runtime/ComfyUI_windows_portable'
        if Path(server.exe()).resolve()!= (portable/'python_embeded/python.exe').resolve() or str(portable/'ComfyUI/main.py').replace('\\','/').lower() not in ' '.join(server.cmdline()).replace('\\','/').lower():
            raise RuntimeError('PID does not match our portable ComfyUI; refusing to stop it.')
        server.terminate(); server.wait(timeout=15); pid_file.unlink()
    with (folder/'stdout.log').open('ab',buffering=0) as out,(folder/'stderr.log').open('ab',buffering=0) as err:
        process=subprocess.Popen(command,cwd=root/'sd-scripts',env=env,stdin=subprocess.DEVNULL,stdout=out,stderr=err,
                                 creationflags=subprocess.DETACHED_PROCESS|subprocess.CREATE_NEW_PROCESS_GROUP|subprocess.CREATE_NO_WINDOW)
    (folder/'trainer.pid').write_text(str(process.pid),encoding='ascii')
    print(json.dumps({'pid':process.pid,'folder':str(folder),'preflight_only':args.preflight}))


if __name__=='__main__':
    main()
