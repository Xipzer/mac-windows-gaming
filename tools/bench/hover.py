#!/usr/bin/env python3
import sys,time,Quartz
SC=Quartz.CGDisplayBounds(Quartz.CGMainDisplayID()).size.width/1000.0
x,y=float(sys.argv[1])*SC,float(sys.argv[2])*SC
for dx in range(0,40,4):
    Quartz.CGEventPost(Quartz.kCGHIDEventTap,Quartz.CGEventCreateMouseEvent(None,Quartz.kCGEventMouseMoved,(x-20+dx,y),0)); time.sleep(0.05)
