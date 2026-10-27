"""Trace the painted torso boundary to separate it from occluding arm art.

Operates on owned full-figure references. Outputs registered replacement layers;
the caller must inspect complete reconstructions, not isolated anatomy crops.
"""
import numpy as np
from PIL import Image
from scipy.interpolate import PchipInterpolator
from scipy.ndimage import gaussian_filter1d

def trace(im,side,size,shape='round'):
    rgb=np.asarray(im);y0,y1=343,576;h=y1-y0
    shrink={'xs':20,'s':12,'m':6,'l':0,'xl':-8}[size]
    ys=[343,375,410,430,470,500,530,550,575]
    if side=='left':
        ps=[350,352,349,350+shrink*.15,350+shrink,365+shrink*.4,377,385,382];x0,x1=325,412
    else:
        ps=[526,528,530-shrink*.2,530-shrink*.25,547-shrink,539-shrink*.7,525,526,538];x0,x1=500,573
    if shape=='compact':ps[4]+=5 if side=='left' else -7;ps[5]+=5 if side=='left' else -9
    elif shape=='wide':ps[4]+=-7 if side=='left' else 7;ps[5]+=-3 if side=='left' else 3
    elif shape in ['lower_full','teardrop']:ps[5]+=-3 if side=='left' else 3
    elif shape=='asymmetric':ps[4]+=3;ps[5]+=1
    prior=PchipInterpolator(ys,ps)(np.arange(y0,y1));xs=np.arange(x0,x1);red=rgb[y0:y1,x0:x1,0].astype(float)
    ink=np.clip(210-red,0,35);cost=-4*ink+.35*(xs[None,:]-prior[:,None])**2
    cost[np.abs(xs[None,:]-prior[:,None])>18]=1e5
    cost[rgb[y0:y1,x0:x1,3]<8]+=1000
    n=len(xs);best=np.full((h,n),np.inf);back=np.zeros((h,n),np.int16);best[0]=cost[0]+20*(xs-prior[0])**2
    for y in range(1,h):
        for k in range(n):
            lo=max(0,k-3);hi=min(n,k+4);prev=best[y-1,lo:hi]+np.abs(np.arange(lo,hi)-k)*.8;j=lo+int(prev.argmin());back[y,k]=j;best[y,k]=cost[y,k]+prev.min()
    k=int(np.argmin(best[-1]+20*(xs-prior[-1])**2));path=[]
    for y in range(h-1,-1,-1):path.append(int(xs[k]));k=int(back[y,k])
    smooth=gaussian_filter1d(np.array(path[::-1],float),4)
    return np.rint(np.clip(smooth,prior-4,prior+4)).astype(int)

def chest_core(im,size,shape='round'):
    a=np.array(im.convert('RGBA'));left=trace(im,'left',size,shape);right=trace(im,'right',size,shape);mask=np.zeros(a.shape[:2],np.uint8)
    for j,(l,r) in enumerate(zip(left,right)):
        y=343+j;mask[y,max(0,l-1):min(832,r+2)]=255
    good=(a[:,:,3]>240)&(a[:,:,0]>220)&(a[:,:,1]>190)&(a[:,:,2]>150);colors,counts=np.unique(a[:,:,:3][good],axis=0,return_counts=True);skin=colors[counts.argmax()] if len(colors) else np.array([255,235,216])
    missing=(a[:,:,3]<32)&(mask>0);a[missing,:3]=skin;a[:,:,3]=mask
    for j,(l,r) in enumerate(zip(left,right)):
        y=343+j
        for x in range(max(0,l-1),min(832,r+2)):
            d=min(x-(l-1),(r+1)-x)
            if d==0:a[y,x,:3]=[149,121,104];a[y,x,3]=180
            elif d==1:a[y,x,:3]=[149,121,104]
            elif d<5:a[y,x,:3]=np.rint(a[y,x,:3]*(d-1)/4+skin*(5-d)/4).astype('uint8')
    a[a[:,:,3]==0,:3]=0
    return Image.fromarray(a),{'method':'Bounded smooth torso contour, original hidden-skin fill and thin brown finishing edge; arms excluded; full-figure reconstruction required','rows':[343,575],'left':left.tolist(),'right':right.tolist()}
