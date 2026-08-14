from pathlib import Path
import shutil, subprocess
from PIL import Image

FFMPEG=Path(r"C:\Users\26987\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe")
ROOT=Path(r"D:\LongTeng\xiaoguang\doubao_video_package")
OUT=Path(r"D:\LongTeng\xiaoguang\animation_work\animations")

jobs={
 "idle":(ROOT/"01_idle_breath",0.25,2.0,6),
 "walk":(ROOT/"02_walk_loop",0.25,2.0,4),
 "run":(ROOT/"03_run_loop",0.20,1.8,4),
 "jump":(ROOT/"04_jump",0.45,2.7,4),
 "attack":(ROOT/"05_attack",0.45,2.7,4),
 "dash":(ROOT/"06_dash",0.45,2.7,4),
}

def subject_bbox(image):
    alpha=image.getchannel("A"); w,h=image.size; pix=alpha.load(); seen=bytearray(w*h); best=None
    for y in range(h):
        for x in range(w):
            idx=y*w+x
            if seen[idx] or pix[x,y] <= 48: continue
            stack=[(x,y)]; seen[idx]=1; count=0; left=right=x; top=bottom=y
            while stack:
                cx,cy=stack.pop(); count+=1; left=min(left,cx); right=max(right,cx); top=min(top,cy); bottom=max(bottom,cy)
                for nx,ny in ((cx-1,cy),(cx+1,cy),(cx,cy-1),(cx,cy+1)):
                    ni=ny*w+nx if 0<=nx<w and 0<=ny<h else -1
                    if ni>=0 and not seen[ni] and pix[nx,ny]>48: seen[ni]=1; stack.append((nx,ny))
            if best is None or count>best[0]: best=(count,(left,top,right+1,bottom+1))
    return best[1] if best else None

def keep_subject(image):
    """Keep the character's connected silhouette and discard watermark/effects."""
    alpha=image.getchannel("A"); w,h=image.size; pix=alpha.load(); seen=bytearray(w*h); best=[]
    for y in range(h):
        for x in range(w):
            idx=y*w+x
            if seen[idx] or pix[x,y] <= 48: continue
            stack=[(x,y)]; seen[idx]=1; component=[]
            while stack:
                cx,cy=stack.pop(); component.append((cx,cy))
                for nx,ny in ((cx-1,cy),(cx+1,cy),(cx,cy-1),(cx,cy+1)):
                    ni=ny*w+nx if 0<=nx<w and 0<=ny<h else -1
                    if ni>=0 and not seen[ni] and pix[nx,ny]>48:
                        seen[ni]=1; stack.append((nx,ny))
            if len(component)>len(best): best=component
    mask=Image.new("L",(w,h)); mp=mask.load()
    for x,y in best: mp[x,y]=pix[x,y]
    clean=Image.new("RGBA",(w,h)); clean.paste(image,(0,0),mask)
    return clean

for name,(folder,start,duration,step) in jobs.items():
    video=next(folder.glob("*.mp4")); cand=OUT/name/"candidates"; final=OUT/name/"normalized"
    if cand.exists(): shutil.rmtree(cand)
    if final.exists(): shutil.rmtree(final)
    cand.mkdir(parents=True); final.mkdir(parents=True)
    vf=f"select='not(mod(n,{step}))',chromakey=0x00ff00:0.28:0.10,despill=green"
    subprocess.run([str(FFMPEG),"-y","-ss",str(start),"-t",str(duration),"-i",str(video),"-vf",vf,"-vsync","0",str(cand/"frame_%03d.png")],check=True,capture_output=True)
    frames=[]
    for p in sorted(cand.glob("*.png")):
        im=keep_subject(Image.open(p).convert("RGBA")); bbox=subject_bbox(im)
        if bbox: frames.append((p,im,bbox))
    # One authored scale shared by every animation. Never derive a different
    # scale per animation or per frame, otherwise state changes visibly pop.
    scale=0.72
    for i,(p,im,b) in enumerate(frames):
        resized=im.resize((round(im.width*scale),round(im.height*scale)),Image.Resampling.NEAREST)
        rb=subject_bbox(resized)
        canvas=Image.new("RGBA",(512,512)); x=256-(rb[0]+rb[2])//2; y=470-rb[3]
        canvas.alpha_composite(resized,(x,y)); canvas.save(final/f"frame_{i:03d}.png")
    print(name,len(frames),"scale",round(scale,4))
