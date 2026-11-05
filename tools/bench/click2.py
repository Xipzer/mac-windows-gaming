#!/usr/bin/env python3
import sys,time,Quartz
SC=Quartz.CGDisplayBounds(Quartz.CGMainDisplayID()).size.width/1000.0
x,y=float(sys.argv[1])*SC,float(sys.argv[2])*SC
def ev(t): Quartz.CGEventPost(Quartz.kCGHIDEventTap,Quartz.CGEventCreateMouseEvent(None,t,(x,y),0))
ev(Quartz.kCGEventMouseMoved); time.sleep(0.5)
ev(Quartz.kCGEventLeftMouseDown); time.sleep(0.25); ev(Quartz.kCGEventLeftMouseUp)
