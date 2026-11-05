#!/usr/bin/env python3
import sys,time,Quartz
K={'w':13,'a':0,'s':1,'d':2,'space':49,'shift':56,'return':36,'escape':53,'left':123,'right':124,'up':126,'down':125,'tab':48,'q':12,'e':14,'r':15,'f':3,'pageup':116,'pagedown':121,'backspace':51,'escape':53}
keys=[k for k in sys.argv[1:] if not k.replace('.','').isdigit()]; secs=float([k for k in sys.argv[1:] if k.replace('.','').isdigit()][0])
for k in keys: Quartz.CGEventPost(Quartz.kCGHIDEventTap,Quartz.CGEventCreateKeyboardEvent(None,K[k],True))
end=time.time()+secs
while time.time()<end:
    for k in keys:
        e=Quartz.CGEventCreateKeyboardEvent(None,K[k],True); Quartz.CGEventSetIntegerValueField(e,Quartz.kCGKeyboardEventAutorepeat,1); Quartz.CGEventPost(Quartz.kCGHIDEventTap,e)
    time.sleep(0.05)
for k in keys: Quartz.CGEventPost(Quartz.kCGHIDEventTap,Quartz.CGEventCreateKeyboardEvent(None,K[k],False))
