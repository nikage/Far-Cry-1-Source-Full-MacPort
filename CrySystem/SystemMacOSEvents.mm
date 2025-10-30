#if defined(__APPLE__) && defined(__MACH__)

#ifdef BOOL
#undef BOOL
#endif

#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <assert.h>

static bool s_firstCall = true;

extern "C" void ProcessMacOSEvents() {
    assert(NSApp != nil && "NSApplication must be initialized before processing events");
    
    @autoreleasepool {
        if (s_firstCall) {
            NSLog(@"ProcessMacOSEvents: First call - event loop is running");
            s_firstCall = false;
        }
        
        NSEvent *event;
        int eventCount = 0;
        while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                           untilDate:[NSDate distantPast]
                                              inMode:NSDefaultRunLoopMode
                                             dequeue:YES]))
        {
            [NSApp sendEvent:event];
            // Don't call updateWindows - we handle rendering manually in BeginFrame/EndFrame
            eventCount++;
        }
        
        static int callCount = 0;
        if (++callCount % 100 == 0) {
            NSLog(@"ProcessMacOSEvents: Called %d times (processed %d events this frame)", callCount, eventCount);
        }
    }
}

#endif

