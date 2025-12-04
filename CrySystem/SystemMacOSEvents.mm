#if defined(__APPLE__) && defined(__MACH__)

#ifdef BOOL
#undef BOOL
#endif

#import <Cocoa/Cocoa.h>
#include <Carbon/Carbon.h>
#include <stdio.h>
#include <assert.h>
#include <stdarg.h>

static bool s_firstCall = true;

static bool ShouldTraceMacEvents()
{
    static bool s_trace = []() {
        const char* env = getenv("CRY_TRACE_MAC_EVENTS");
        return env && env[0] && env[0] != '0';
    }();
    return s_trace;
}

static void TraceMacEvent(const char* fmt, ...)
{
    if (!ShouldTraceMacEvents())
        return;
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    fputc('\n', stderr);
    fflush(stderr);
    va_end(args);
}

static OSErr LogAppleEventHandler(const AppleEvent* event, AppleEvent* reply, SRefCon refcon)
{
    if (!ShouldTraceMacEvents() || !event)
        return eventNotHandledErr;

    DescType eventClass = typeNull;
    AEGetAttributePtr(event, keyEventClassAttr, typeType, nullptr, &eventClass, sizeof(eventClass), nullptr);
    DescType eventID = typeNull;
    AEGetAttributePtr(event, keyEventIDAttr, typeType, nullptr, &eventID, sizeof(eventID), nullptr);

    char classStr[5] = {0};
    char idStr[5] = {0};
    memcpy(classStr, &eventClass, 4);
    memcpy(idStr, &eventID, 4);
    TraceMacEvent("AppleEvent: class='%s' id='%s'", classStr, idStr);

    return noErr;
}

static void InstallAppleEventLogger()
{
    static bool s_installed = false;
    if (s_installed)
        return;
    s_installed = true;
    AEInstallEventHandler(kCoreEventClass, kAEReopenApplication, LogAppleEventHandler, 0, false);
    AEInstallEventHandler(kCoreEventClass, kAEOpenApplication, LogAppleEventHandler, 0, false);
    AEInstallEventHandler(kCoreEventClass, kAEOpenDocuments, LogAppleEventHandler, 0, false);
    TraceMacEvent("AppleEvent logger installed");
}

extern "C" void ProcessMacOSEvents() {
//     NSLog(@"ProcessMacOSEvents: ENTRY");
    
    if (!NSApp) {
        // NSLog(@"ProcessMacOSEvents: NSApp is nil, returning");
        return;
    }
    
    InstallAppleEventLogger();
    
    // NSLog(@"ProcessMacOSEvents: NSApp is valid");
    
    @autoreleasepool {
    if (ShouldTraceMacEvents())
        TraceMacEvent("ProcessMacOSEvents: entry (firstCall=%d)", s_firstCall ? 1 : 0);
        if (s_firstCall) {
            // NSLog(@"ProcessMacOSEvents: First call - event loop is running");
            s_firstCall = false;
        }
        
        // NSLog(@"ProcessMacOSEvents: About to start event loop");
        
        NSEvent *event;
        int eventCount = 0;
        const int MAX_EVENTS_PER_FRAME = 100;
        
        // NSLog(@"ProcessMacOSEvents: About to call nextEventMatchingMask");
        
        while (eventCount < MAX_EVENTS_PER_FRAME)
        {
            if (ShouldTraceMacEvents())
                TraceMacEvent("ProcessMacOSEvents: waiting for event #%d", eventCount);
            event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                      untilDate:nil
                                         inMode:NSDefaultRunLoopMode
                                        dequeue:YES];
            if (!event)
                break;

            @try {
                if (ShouldTraceMacEvents())
                    TraceMacEvent("ProcessMacOSEvents: send event #%d type=%lu windowNumber=%ld timestamp=%f event=%p",
                                  eventCount,
                                  (unsigned long)[event type],
                                  (long)[event windowNumber],
                                  [event timestamp],
                                  event);
                [NSApp sendEvent:event];
                if (ShouldTraceMacEvents())
                    TraceMacEvent("ProcessMacOSEvents: updateWindows before event #%d", eventCount);
                [NSApp updateWindows];
                if (ShouldTraceMacEvents())
                    TraceMacEvent("ProcessMacOSEvents: finished event #%d", eventCount);
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
        if (ShouldTraceMacEvents())
            TraceMacEvent("ProcessMacOSEvents: exit iteration call=%d processed=%d total=%d", callCount, eventCount, totalEvents);
    }
    
    // NSLog(@"ProcessMacOSEvents: EXIT");
}

#endif

