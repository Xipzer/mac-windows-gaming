#!/usr/bin/env python3
import sys,re,subprocess
out=subprocess.run(['python3',__import__('os').path.join(__import__('os').path.dirname(__file__),'ocr.py'),sys.argv[1]],capture_output=True,text=True).stdout.splitlines()
L=[(int(x),int(y),t.strip()) for x,y,t in (l.split(' ',2) for l in out if len(l.split(' ',2))==3)]
def val(label):
    ys=[(x,y) for x,y,t in L if t==label]
    if not ys: return '?'
    lx,ly=ys[0]
    c=[(abs(y-ly),t) for x,y,t in L if x>lx+100 and abs(y-ly)<=6 and re.fullmatch(r'[\d. ]+(ms)?',t)]
    return sorted(c)[0][1].replace(' ','') if c else '?'
print(val('FPS'),val('GPU'))
