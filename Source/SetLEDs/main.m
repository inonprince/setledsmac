
/*  setleds for Mac
 https://github.com/damieng/setledsmac
 Copyright 2015-2017 Damien Guard. GPL 2 licenced.

 Monitor mode added by Raj Perera - https://github.com/rajiteh/setledsmac-monitor
 Keyboard event sniffer code is from https://github.com/objective-see/sniffMK
 */

#include "main.h"

Boolean verbose = false;
const char * nameMatch;
static CFMachPortRef eventTap = NULL;

IOHIDManagerRef manager;
CFDictionaryRef keyboard;
CFSetRef devices;

IOHIDDeviceRef tbDevice;
IOHIDDeviceRef kbDevice;

void current_timestamp() {
    struct timeval te;
    gettimeofday(&te, NULL); // get current time
    long long milliseconds = te.tv_sec*1000LL + te.tv_usec/1000; // calculate milliseconds
    printf("milliseconds: %lld\n", milliseconds);
}

int main(int argc, const char * argv[])
{
    printf("SetLEDs version 0.2 + Monitor - Based on https://github.com/damieng/setledsmac\n");
    parseOptions(argc, argv);
    printf("\n");
    return 0;
}

void parseOptions(int argc, const char * argv[])
{
    if (argc == 1) {
        LedState changes[] = { NoChange, NoChange, NoChange, NoChange };
        explainUsage();
        exit(1);
    }
    
    
    
    Boolean nextIsName = false;
    Boolean monitorMode = false;
    
    LedState changes[] = { NoChange, NoChange, NoChange, NoChange };
    
    for (int i = 1; i < argc; i++) {
        if (strcasecmp(argv[i], "monitor") == 0)
            monitorMode = true;
        else if (strcasecmp(argv[i], "-v") == 0)
            verbose = true;
        else if(strcasecmp(argv[i], "-name") == 0)
            nextIsName = true;
        
        // Numeric lock
        else if (strcasecmp(argv[i], "+num") == 0)
            changes[kHIDUsage_LED_NumLock] = On;
        else if (strcasecmp(argv[i], "-num") == 0)
            changes[kHIDUsage_LED_NumLock] = Off;
        else if (strcasecmp(argv[i], "^num") == 0)
            changes[kHIDUsage_LED_NumLock] = Toggle;
        
        // Caps lock
        else if (strcasecmp(argv[i], "+caps") == 0)
            changes[kHIDUsage_LED_CapsLock] = On;
        else if (strcasecmp(argv[i], "-caps") == 0)
            changes[kHIDUsage_LED_CapsLock] = Off;
        else if (strcasecmp(argv[i], "^caps") == 0)
            changes[kHIDUsage_LED_CapsLock] = Toggle;
        
        // Scroll lock
        else if (strcasecmp(argv[i], "+scroll") == 0)
            changes[kHIDUsage_LED_ScrollLock] = On;
        else if (strcasecmp(argv[i], "-scroll") == 0)
            changes[kHIDUsage_LED_ScrollLock] = Off;
        else if (strcasecmp(argv[i], "^scroll") == 0)
            changes[kHIDUsage_LED_ScrollLock] = Toggle;
        
        else {
            if (nextIsName) {
                nameMatch = argv[i];
                nextIsName = false;
            }
            else {
                fprintf(stderr, "Unknown option %s\n\n", argv[i]);
                explainUsage();
                exit(1);
            }
        }
    }
    
    if (!manager) manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (!manager) {
        fprintf(stderr, "ERROR: Failed to create IOHID manager.\n");
        return;
    }
    IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
    keyboard = getKeyboardDictionary();
    if (!keyboard) {
        fprintf(stderr, "ERROR: Failed to get dictionary usage page for kHIDUsage_GD_Keyboard.\n");
        return;
    }
    IOHIDManagerSetDeviceMatching(manager, keyboard);
    devices = IOHIDManagerCopyDevices(manager);
    getRefs();
    
    if (monitorMode)
        startMonitor();
    else
        setAllKeyboards(changes);
}


void startMonitor()
{
    CGEventMask eventMask = 0;
    CFRunLoopSourceRef runLoopSource = NULL;
    
    printf("Starting in monitor mode.\n");
    
    @autoreleasepool {
        //init event mask with mouse events
        // ->add 'CGEventMaskBit(kCGEventMouseMoved)' for mouse move events
        eventMask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) | CGEventMaskBit(kCGEventFlagsChanged);
    
//        eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, 0, eventMask, eventCallback, NULL);
        eventTap = CGEventTapCreate(kCGHIDEventTap,
                                    kCGTailAppendEventTap,
                                    kCGEventTapOptionListenOnly,
                                    eventMask, eventCallback, NULL);
        if(NULL == eventTap)
        {
            fprintf(stderr, "ERROR: failed to create event tap\n");
            goto bail;
        }
    
        printf("Ceated event tap.\n");
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
//        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, kCFRunLoopCommonModes);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CGEventTapEnable(eventTap, true);
        printf("Event tab enabled, starting monitor.\n");
    
        //go, go, go
        CFRunLoopRun();
    }
    
    
bail:
    
    //release event tap
    if(NULL != eventTap)
    {
        CFRelease(eventTap);
        eventTap = NULL;
    }
    
    if(NULL != runLoopSource)
    {
        CFRelease(runLoopSource);
        runLoopSource = NULL;
    }
    
}

//callback for mouse/keyboard events
CGEventRef eventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon)
{
    if(kCGEventTapDisabledByTimeout == type)
    {
        CGEventTapEnable(eventTap, true);
        fprintf(stderr, "Event tap timed out: restarting tap");
        return event;
    }
    CGKeyCode keyCode = 0;
    keyCode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    if(kCGEventKeyUp == type || (kCGEventFlagsChanged == type && keyCode == 0x39))
    {
        LedState changes[] = { NoChange, NoChange, NoChange, NoChange };
        switch (keyCode)
        {
            case 0x39:
                changes[kHIDUsage_LED_CapsLock] = Toggle;
                setKeyboard(tbDevice, keyboard, changes);
                break;
            case 0x47:
                changes[kHIDUsage_LED_NumLock] = Toggle;
                setKeyboard(tbDevice, keyboard, changes);
                break;
            case 0x6b:
                changes[kHIDUsage_LED_ScrollLock] = Toggle;
                setKeyboard(kbDevice, keyboard, changes);
                break;
            default:
                return event;
                
        }
//       setAllKeyboards(changes);
  
    }
    return event;
}

void explainUsage()
{
    printf("Usage:\tsetleds [monitor] [-v] [-name wildcard] [[+|-|^][ num | caps | scroll]]\n"
           "Thus,\tsetleds +caps -num ^scroll\n"
           "will set CapsLock, clear NumLock and toggle ScrollLock.\n"
           "Any leds changed are reported for each keyboard.\n"
           "Specify -v to shows state of all leds.\n"
           "Specify -name to match keyboard name with a wildcard\n"
           "Use the \"monitor\" sub command to run continously and toggle LEDs on keypress.");
}

Boolean isKeyboardDevice(IOHIDDeviceRef device)
{
    return IOHIDDeviceConformsTo(device, kHIDPage_GenericDesktop, kHIDUsage_GD_Keyboard);
}

void setKeyboard(IOHIDDeviceRef device, CFDictionaryRef keyboardDictionary, LedState changes[])
{
//    CFStringRef deviceNameRef = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
//    if (!deviceNameRef) return;
//    
//    CFStringRef deviceIdRef = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductIDKey));
//    if (!deviceIdRef) return;
//    
//    const char * deviceName = CFStringGetCStringPtr(deviceNameRef, kCFStringEncodingUTF8);
//    if (nameMatch && fnmatch(nameMatch, deviceName, 0) != 0)
//        return;
//    uint productId = 0;
//    CFTypeID numericTypeId = CFNumberGetTypeID();
//    if (deviceIdRef && CFGetTypeID(deviceIdRef) == numericTypeId) {
//        CFNumberGetValue((CFNumberRef)deviceIdRef, kCFNumberSInt32Type, &productId);
//    }
//    
//    if (changes[kHIDUsage_LED_ScrollLock] != NoChange) {
//        if (productId != 24926) return;
//    } else {
//        if (productId != 21667) return;
//    }
//    printf("\nDeviceid: \"%s\" (%d)", deviceName, productId);

    IOHIDDeviceOpen(device, 0);

    CFArrayRef elements = IOHIDDeviceCopyMatchingElements(device, keyboardDictionary, kIOHIDOptionsTypeNone);

    bool missingState = false;
    if (elements) {
        for (CFIndex elementIndex = 0; elementIndex < CFArrayGetCount(elements); elementIndex++) {
            IOHIDElementRef element = (IOHIDElementRef)CFArrayGetValueAtIndex(elements, elementIndex);

            if (element && kHIDPage_LEDs == IOHIDElementGetUsagePage(element)) {
                uint32_t led = IOHIDElementGetUsage(element);

                if (led > maxLeds) break;
                
                // Get current keyboard led status
                IOHIDValueRef currentValue = 0;
                IOHIDDeviceGetValue(device, element, &currentValue);
                
                if (currentValue == 0x00) {
                    missingState = true;
                    // printf("?%s ", ledNames[led - 1]);
                } else {
                    long current = IOHIDValueGetIntegerValue(currentValue);
                    CFRelease(CFRetain(currentValue));
//                    CFRelease(currentValue);

                    // Should we try to set the led?
                    if (changes[led] != NoChange && changes[led] != current) {
                        LedState newState = changes[led];
                        if (newState == Toggle) {
                            newState = current == 0 ? On : Off;
                        }
//                        LedState newState2 = changes[led];
//                        if (newState == Toggle) {
//                            newState2 = current == 0 ? Off : On;
//                        }
                        IOHIDValueRef newValue = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, newState);
                        if (newValue) {
                            // IOReturn changeResult = IOHIDDeviceSetValue(device, element, newValue);

                            IOHIDDeviceSetValue(device, element, newValue);

                            current_timestamp();
//                            usleep(100*1000);
//                            IOHIDValueRef newValue2 = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, newState2);
//                            IOHIDDeviceSetValue(device, element, newValue2);
//                            current_timestamp();
//                            CFRelease(newValue2);


                            // Was the change successful?
                            // if (kIOReturnSuccess == changeResult) {
                            //    printf("%s%s ", stateSymbol[newState], ledNames[led - 1]);
                            // }

                            CFRelease(newValue);
                        }
                    } else if (verbose) {
                            CFStringRef deviceNameRef = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
                            if (!deviceNameRef) return;
                        
                            CFStringRef deviceIdRef = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductIDKey));
                            if (!deviceIdRef) return;
                        
                            const char * deviceName = CFStringGetCStringPtr(deviceNameRef, kCFStringEncodingUTF8);
                            if (nameMatch && fnmatch(nameMatch, deviceName, 0) != 0)
                                return;
                            uint productId = 0;
                            CFTypeID numericTypeId = CFNumberGetTypeID();
                            if (deviceIdRef && CFGetTypeID(deviceIdRef) == numericTypeId) {
                                CFNumberGetValue((CFNumberRef)deviceIdRef, kCFNumberSInt32Type, &productId);
                            }
                        
                        printf("Device: \"%s\" (%d) %s%s ", deviceName, productId, stateSymbol[current], ledNames[led - 1]);
                    }
                }
            }
        }
        CFRelease(elements);
    }
    IOHIDDeviceClose(device, 0);
    
    // printf("\n");
    if (missingState) {
        printf("\nSome state could not be determined. Please try running as root/sudo.\n");
    }
}

void getRefs()
{
    if (devices) {
        CFIndex deviceCount = CFSetGetCount(devices);
        if (deviceCount == 0) {
            fprintf(stderr, "ERROR: Could not find any keyboard devices.\n");
        }
        else {
            // Loop through all keyboards attempting to get or display led state
            IOHIDDeviceRef *deviceRefs = malloc(sizeof(IOHIDDeviceRef) * deviceCount);
            if (deviceRefs) {
                CFSetGetValues(devices, (const void **) deviceRefs);
                for (CFIndex deviceIndex = 0; deviceIndex < deviceCount; deviceIndex++)
                    if (isKeyboardDevice(deviceRefs[deviceIndex])) {
                        CFStringRef deviceIdRef = IOHIDDeviceGetProperty(deviceRefs[deviceIndex], CFSTR(kIOHIDProductIDKey));
                        if (!deviceIdRef) return;
                        uint deviceId = 0;
                        CFTypeID numericTypeId = CFNumberGetTypeID();
                        if (deviceIdRef && CFGetTypeID(deviceIdRef) == numericTypeId) {
                            CFNumberGetValue((CFNumberRef)deviceIdRef, kCFNumberSInt32Type, &deviceId);
                        }
                        if (deviceId == 21667) {
                            printf("nano found");
                            tbDevice = (IOHIDDeviceRef)CFRetain(deviceRefs[deviceIndex]);
                        }
                        if (deviceId == 24926) {
                            printf("corne found");
                            kbDevice = (IOHIDDeviceRef)CFRetain(deviceRefs[deviceIndex]);
                        }
                    }

//                free(deviceRefs);
            }
        }
        
//        CFRelease(devices);
    }
    
//    CFRelease(keyboard);
}

void setAllKeyboards(LedState changes[])
{
    printf("casax\n");
    current_timestamp();
    
    
    printf("ueuuu\n");
    current_timestamp();
    printf("uTTeuuu\n");
    current_timestamp();
    if (devices) {
        CFIndex deviceCount = CFSetGetCount(devices);
        if (deviceCount == 0) {
            fprintf(stderr, "ERROR: Could not find any keyboard devices.\n");
        }
        else {
            // Loop through all keyboards attempting to get or display led state
            IOHIDDeviceRef *deviceRefs = malloc(sizeof(IOHIDDeviceRef) * deviceCount);
            if (deviceRefs) {
                CFSetGetValues(devices, (const void **) deviceRefs);
                for (CFIndex deviceIndex = 0; deviceIndex < deviceCount; deviceIndex++)
                    if (isKeyboardDevice(deviceRefs[deviceIndex])) {
                        current_timestamp();
                        setKeyboard(deviceRefs[deviceIndex], keyboard, changes);
                    }

                free(deviceRefs);
            }
        }
        
//        CFRelease(devices);
    }
    
//    CFRelease(keyboard);
}

CFMutableDictionaryRef getKeyboardDictionary()
{
    CFMutableDictionaryRef result = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    
    if (!result) return result;
    
    UInt32 inUsagePage = kHIDPage_GenericDesktop;
    UInt32 inUsage = kHIDUsage_GD_Keyboard;
    
    CFNumberRef page = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &inUsagePage);
    if (page) {
        CFDictionarySetValue(result, CFSTR(kIOHIDDeviceUsageKey), page);
        CFRelease(page);
        
        CFNumberRef usage = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &inUsage);
        if (usage) {
            CFDictionarySetValue(result, CFSTR(kIOHIDDeviceUsageKey), usage);
            CFRelease(usage);
        }
    }
    return result;
}
