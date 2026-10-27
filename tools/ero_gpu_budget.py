"""Process-local GPU duty budget. It limits scheduled work, not GPU power/clocks."""
from pathlib import Path
from functools import wraps
import ctypes
import json
import os
import threading
import time

ROOT=Path('E:/Ai/ComfyUI-EroInc')
CONFIG=ROOT/'gpu-budget.json'
_depth=threading.local()


def settings():
    value=json.loads(CONFIG.read_text(encoding='utf-8-sig'))
    duty=float(value['duty_percent'])/100.0
    if not 0.1<=duty<=1.0:
        raise ValueError('GPU duty_percent must be between 10 and 100.')
    return value,duty


def log(record):
    path=ROOT/'logs/gpu-budget.jsonl';path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('a',encoding='utf-8') as stream:
        stream.write(json.dumps({'unix_time':time.time(),'pid':os.getpid(),**record})+'\n')


def lower_priority():
    import psutil
    config,_=settings()
    cpu=config.get('cpu_priority','normal')
    gpu=config.get('gpu_priority','normal')
    if cpu not in ('normal','below_normal') or gpu not in ('normal','below_normal'):
        raise ValueError('Use normal or below_normal process priorities.')
    psutil.Process().nice(psutil.NORMAL_PRIORITY_CLASS if cpu=='normal' else psutil.BELOW_NORMAL_PRIORITY_CLASS)
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.GetCurrentProcess.restype=ctypes.c_void_p
    handle=kernel.GetCurrentProcess()
    gdi=ctypes.WinDLL('gdi32',use_last_error=True)
    setter=gdi.D3DKMTSetProcessSchedulingPriorityClass
    setter.argtypes=[ctypes.c_void_p,ctypes.c_int];setter.restype=ctypes.c_long
    result=setter(handle,2 if gpu=='normal' else 1)
    getter=gdi.D3DKMTGetProcessSchedulingPriorityClass
    getter.argtypes=[ctypes.c_void_p,ctypes.POINTER(ctypes.c_int)];getter.restype=ctypes.c_long
    priority=ctypes.c_int(-1);query=getter(handle,ctypes.byref(priority))
    report={'event':'priority','cpu':cpu,'gpu_set_status':int(result),
            'gpu_query_status':int(query),'gpu_priority_class':priority.value}
    log(report)
    return report


def budgeted(function,label):
    if getattr(function,'_ero_budgeted',False):
        return function
    @wraps(function)
    def limited(*args,**kwargs):
        import torch
        config,duty=settings()
        if duty==1.0 or not torch.cuda.is_available() or getattr(_depth,'active',False):
            return function(*args,**kwargs)
        _depth.active=True
        try:
            torch.cuda.synchronize()
            start=time.perf_counter()
            result=function(*args,**kwargs)
            torch.cuda.synchronize()
            active=time.perf_counter()-start
            requested_idle=active*(1.0/duty-1.0)
            idle_start=time.perf_counter()
            time.sleep(requested_idle)
            idle=time.perf_counter()-idle_start
            log({'event':'budget','scope':label,'target_percent':round(duty*100,2),
                 'work_seconds':active,'idle_seconds':idle,'scheduled_duty_percent':100*active/(active+idle)})
            return result
        finally:
            _depth.active=False
    limited._ero_budgeted=True
    return limited
