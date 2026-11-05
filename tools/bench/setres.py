#!/usr/bin/env python3
import sys, re, os
W,H=sys.argv[1],sys.argv[2]
x=os.path.expanduser("~/Documents/WB Games/Batman Arkham Knight/GFXSettings.BatmanArkhamKnight.xml")
raw=open(x,'rb').read()
enc='utf-16-be' if raw[0]==0 else 'utf-16-le'
s=raw.decode(enc)
s=re.sub(r'(Name="ResolutionX"[^>]*Value=")\d+"', r'\g<1>%s"'%W, s)
s=re.sub(r'(Name="ResolutionY"[^>]*Value=")\d+"', r'\g<1>%s"'%H, s)
open(x,'wb').write(s.encode(enc))
i=os.path.expanduser("~/Library/Application Support/Steam/steamapps/common/Batman Arkham Knight/BMGame/Config/BmSystemSettings.ini")
t=open(i,'rb').read().decode('latin-1')
t=re.sub(r'(?m)^ResX=\d+',f'ResX={W}',t); t=re.sub(r'(?m)^ResY=\d+',f'ResY={H}',t)
open(i,'wb').write(t.encode('latin-1'))
print(enc, re.findall(r'Name="Resolution[XY]"[^>]*Value="(\d+)"',s))
