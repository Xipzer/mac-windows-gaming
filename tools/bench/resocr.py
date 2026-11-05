#!/usr/bin/env python3
import sys,re,subprocess,tempfile
from PIL import Image
im=Image.open(sys.argv[1]); w=im.width
c=im.crop((int(60*w/1000),int(85*w/1000),int(320*w/1000),int(148*w/1000))).resize((1040,252))
t=tempfile.mktemp(suffix='.png'); c.save(t)
out=subprocess.run(['python3',__import__('os').path.join(__import__('os').path.dirname(__file__),'ocr.py'),t],capture_output=True,text=True).stdout.splitlines()
L=[(int(x),int(y),s.strip()) for x,y,s in (l.split(' ',2) for l in out if len(l.split(' ',2))==3)]
r=[]
for k in('Minimum','Maximum','Average'):
    ys=[y for x,y,s in L if s==k]
    v=[s for x,y,s in L if ys and abs(y-ys[0])<=40 and re.fullmatch(r'\d+',s)]
    r.append(v[0] if v else '?')
print('/'.join(r))
