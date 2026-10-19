import json, sys, numpy as np
from pathlib import Path
from PIL import Image
P = Path(r"C:/Users/work/Desktop/FC_Simulation/godot_project")
base = P/"assets/maps/ulsan_metro_80km/road_revisions/16c07b67a4cf15ab/road_formation"
idx = json.loads((base/"index.json").read_text(encoding="utf-8"))
parts = [np.fromfile(base/e["file"], dtype="<f4").reshape(-1,9) for e in idx["tiles"].values()]
rows = np.concatenate(parts)
_, u = np.unique(rows[:,8], return_index=True)
rows = rows[u]
print("segments", len(rows))
half = rows[:,6]
for lo,hi in [(0,1.01),(1.01,2.01),(2.01,3.01),(3.01,4.01),(4.01,6.01),(6.01,100)]:
    print(f"half {lo}-{hi}: {((half>=lo)&(half<hi)).sum()}")
img = np.asarray(Image.open(P/"assets/generated/railway/graded_heightmap_16bit.png"), dtype=np.float64)
print("height img", img.shape)
lo_e, hi_e = -30.0, 1300.0
H = img/65535*(hi_e-lo_e)+lo_e
W = 80000.0
def mesh_h(x, z, res=128, chunks=11):
    n = H.shape[0]
    tile = n//chunks
    stride = tile//res
    step = W/chunks/res
    gx = (x+W/2)/step; gz = (z+W/2)/step
    ix = np.clip(np.floor(gx).astype(int),0,chunks*res-1); iz = np.clip(np.floor(gz).astype(int),0,chunks*res-1)
    fx = gx-ix; fz = gz-iz
    def g(a,b): return H[np.clip(b*stride,0,n-1), np.clip(a*stride,0,n-1)]
    a=g(ix,iz); b=g(ix+1,iz); c=g(ix,iz+1); d=g(ix+1,iz+1)
    return np.where(fx+fz<=1, a+fx*(b-a)+fz*(c-a), d+(1-fx)*(c-d)+(1-fz)*(b-d))
for res in (128,64):
    diff = rows[:,2]-mesh_h(rows[:,0], rows[:,1], res)
    ad = np.abs(diff)
    print(f"res {res}: |centre-mesh| p50 {np.percentile(ad,50):.2f} p90 {np.percentile(ad,90):.2f} p99 {np.percentile(ad,99):.2f} max {ad.max():.1f}; >3m {(ad>3).mean()*100:.1f}% >10m {(ad>10).mean()*100:.2f}%")
    for lo,hi in [(0,2.01),(2.01,100)]:
        m=(half>=lo)&(half<hi)
        print(f"   half {lo}-{hi}: p90 {np.percentile(ad[m],90):.2f} >5m {(ad[m]>5).mean()*100:.1f}%")
# grid density at LOD0 128
step = W/11/128
gx0 = np.floor((np.minimum(rows[:,0],rows[:,3])-rows[:,6]-rows[:,7]+W/2)/step).astype(int)
gx1 = np.floor((np.maximum(rows[:,0],rows[:,3])+rows[:,6]+rows[:,7]+W/2)/step).astype(int)
gz0 = np.floor((np.minimum(rows[:,1],rows[:,4])-rows[:,6]-rows[:,7]+W/2)/step).astype(int)
gz1 = np.floor((np.maximum(rows[:,1],rows[:,4])+rows[:,6]+rows[:,7]+W/2)/step).astype(int)
N = 11*128
for name, m in [("all", np.ones(len(rows),bool)), ("half>2", half>2.01), ("half>3", half>3.01)]:
    cnt = np.zeros((N+2,N+2), np.int32)
    for x0,x1,z0,z1 in zip(gx0[m],gx1[m],gz0[m],gz1[m]):
        cnt[max(z0,0):min(z1,N-1)+1, max(x0,0):min(x1,N-1)+1] += 1
    c = cnt[:N,:N]
    print(f"{name}: road cells {(c>0).sum()} / {N*N} ({(c>0).mean()*100:.1f}%), >12 {(c>12).sum()}, >40 {(c>40).sum()}, max {c.max()}")
    # center chunk (5,5)
    cc = c[5*128:6*128, 5*128:6*128]
    print(f"   centre chunk road cells {(cc>0).sum()}, >12 {(cc>12).sum()}")
