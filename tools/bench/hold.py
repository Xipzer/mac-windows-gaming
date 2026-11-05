#!/usr/bin/env python3
import sys, time, Quartz
K={'return':36,'enter':36,'escape':53,'esc':53,'space':49,'up':126,'down':125,'left':123,'right':124,'tab':48,'q':12,'e':14,'w':13,'a':0,'s':1,'d':2,'r':15,'f':3,'1':18,'2':19,'3':20,'pageup':116,'pagedown':121,'backspace':51,'z':6,'x':7,'c':8,'v':9,'1':18,'2':19,'3':20}
k=K[sys.argv[1]]; n=int(sys.argv[2]) if len(sys.argv)>2 else 1
for _ in range(n):
    for down in (True, False):
        e=Quartz.CGEventCreateKeyboardEvent(None,k,down)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap,e)
        time.sleep(0.12)
    time.sleep(0.5)
