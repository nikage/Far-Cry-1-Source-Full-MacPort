#if defined(__APPLE__) && defined(__MACH__)

#ifdef BOOL
#undef BOOL
#endif

#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <assert.h>

static bool s_firstCall = true;

extern "C" void ProcessMacOSEvents() {
//     NSLog(@"ProcessMacOSEvents: ENTRY");
    
    if (!NSApp) {
        // NSLog(@"ProcessMacOSEvents: NSApp is nil, returning");
        return;
    }
    
    // NSLog(@"ProcessMacOSEvents: NSApp is valid");
    
    @autoreleasepool {
        if (s_firstCall) {
            // NSLog(@"ProcessMacOSEvents: First call - event loop is running");
            s_firstCall = false;
        }
        
        // NSLog(@"ProcessMacOSEvents: About to start event loop");
        
        NSEvent *event;
        int eventCount = 0;
        const int MAX_EVENTS_PER_FRAME = 100;
        
        // NSLog(@"ProcessMacOSEvents: About to call nextEventMatchingMask");
        
        while (eventCount < MAX_EVENTS_PER_FRAME && 
               (event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                           untilDate:nil
                                              inMode:NSDefaultRunLoopMode
                                             dequeue:YES]))
        {
            // NSLog(@"ProcessMacOSEvents: Got event #%d", eventCount);
            @try {
                [NSApp sendEvent:event];
                // NSLog(@"ProcessMacOSEvents: sendEvent completed for event #%d", eventCount);
                [NSApp updateWindows];
                // NSLog(@"ProcessMacOSEvents: updateWindows completed for event #%d", eventCount);
                eventCount++;
            }
            @catch (NSException *exception) {
                NSLog(@"ProcessMacOSEvents: Exception processing event: %@", exception);
                break;
            }
        }
        
        // NSLog(@"ProcessMacOSEvents: Event loop completed, processed %d events", eventCount);
        
        static int callCount = 0;
        static int totalEvents = 0;
        totalEvents += eventCount;
        ++callCount;
    }
    
    // NSLog(@"ProcessMacOSEvents: EXIT");
}

#endif

