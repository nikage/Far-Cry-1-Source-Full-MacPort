#if defined(__APPLE__) && defined(__MACH__)

#ifdef BOOL
#undef BOOL
#endif

#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <assert.h>

static bool s_firstCall = true;

static bool ShouldTraceMacEvents()
{
    static bool s_trace = []() {
        const char* env = getenv("CRY_TRACE_MAC_EVENTS");
        return env && env[0] && env[0] != '0';
    }();
    return s_trace;
}

extern "C" void ProcessMacOSEvents() {
//     NSLog(@"ProcessMacOSEvents: ENTRY");
    
    if (!NSApp) {
        // NSLog(@"ProcessMacOSEvents: NSApp is nil, returning");
        return;
    }
    
    // NSLog(@"ProcessMacOSEvents: NSApp is valid");
    
    @autoreleasepool {
        if (ShouldTraceMacEvents()) {
            NSLog(@"ProcessMacOSEvents: entry (firstCall=%d)", s_firstCall ? 1 : 0);
        }
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
                if (ShouldTraceMacEvents()) {
                    NSLog(@"ProcessMacOSEvents: send event #%d type=%ld windowNumber=%ld timestamp=%f",
                          eventCount,
                          (long)[event type],
                          (long)[event windowNumber],
                          [event timestamp]);
                }
                [NSApp sendEvent:event];
                // NSLog(@"ProcessMacOSEvents: sendEvent completed for event #%d", eventCount);
                if (ShouldTraceMacEvents()) {
                    NSLog(@"ProcessMacOSEvents: updateWindows before event #%d", eventCount);
                }
                [NSApp updateWindows];
                // NSLog(@"ProcessMacOSEvents: updateWindows completed for event #%d", eventCount);
                if (ShouldTraceMacEvents()) {
                    NSLog(@"ProcessMacOSEvents: finished event #%d", eventCount);
                }
                eventCount++;
            }
            @catch (NSException *exception) {
                NSLog(@"ProcessMacOSEvents: Exception processing event: %@", exception);
                break;
            }
            @catch (...) {
                NSLog(@"ProcessMacOSEvents: Unknown exception processing event");
                break;
            }
        }
        
        // NSLog(@"ProcessMacOSEvents: Event loop completed, processed %d events", eventCount);
        
        static int callCount = 0;
        static int totalEvents = 0;
        totalEvents += eventCount;
        ++callCount;
        if (ShouldTraceMacEvents()) {
            NSLog(@"ProcessMacOSEvents: exit iteration call=%d processed=%d total=%d", callCount, eventCount, totalEvents);
        }
    }
    
    // NSLog(@"ProcessMacOSEvents: EXIT");
}

#endif

