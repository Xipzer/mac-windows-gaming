#!/usr/bin/env python3
import sys
from PIL import Image
im=Image.open(sys.argv[1]).convert('RGB'); W,H=im.size; sc=W/1000.0
items=[l.split(' ',2) for l in open(__import__('os').path.join(__import__('os').path.dirname(__file__),'state.txt')).read().splitlines() if len(l.split(' ',2))==3]
best=None
for x,y,t in items:
    x,y=int(x),int(y)
    if x>400 or y<150 or y>420 or len(t)<4: continue
    v=0
    for xx in range(int(52*sc),int(70*sc)):
        r,g,b=im.getpixel((xx,int(y*sc)))
        v+=max(0,b-r)
    if best is None or v>best[0]: best=(v,t)
print(best[1] if best else "")
