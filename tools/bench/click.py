#!/usr/bin/env python3
import sys,time,Quartz
SC=Quartz.CGDisplayBounds(Quartz.CGMainDisplayID()).size.width/1000.0
x,y=float(sys.argv[1])*SC,float(sys.argv[2])*SC
def ev(t,p): Quartz.CGEventPost(Quartz.kCGHIDEventTap,Quartz.CGEventCreateMouseEvent(None,t,p,0))
for dx in range(0,40,4):
    ev(Quartz.kCGEventMouseMoved,(x-20+dx,y)); time.sleep(0.05)
time.sleep(1.0)
ev(Quartz.kCGEventLeftMouseDown,(x,y)); time.sleep(0.3); ev(Quartz.kCGEventLeftMouseUp,(x,y))
