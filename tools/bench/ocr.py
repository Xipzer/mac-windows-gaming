#!/usr/bin/env python3
import sys, Vision, Quartz
from Foundation import NSURL
url=NSURL.fileURLWithPath_(sys.argv[1])
src=Quartz.CGImageSourceCreateWithURL(url,None); img=Quartz.CGImageSourceCreateImageAtIndex(src,0,None)
W=Quartz.CGImageGetWidth(img); H=Quartz.CGImageGetHeight(img)
req=Vision.VNRecognizeTextRequest.alloc().init(); req.setRecognitionLevel_(0)
h=Vision.VNImageRequestHandler.alloc().initWithCGImage_options_(img,None); h.performRequests_error_([req],None)
sc=1000.0/W
for o in req.results():
    t=o.topCandidates_(1)[0].string(); b=o.boundingBox()
    cx=(b.origin.x+b.size.width/2)*W*sc; cy=(1-(b.origin.y+b.size.height/2))*H*sc
    print(f"{int(cx)} {int(cy)} {t}")
