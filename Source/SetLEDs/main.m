
/* syncleds for MacOS
 based on work by damieng and rajiteh
 GPL 2 licenced.
 */

#include "main.h"

Boolean verbose = false;
const char * nameMatch;
int kbMatch;
int tbMatch;
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
    printf("Starting SyncLeds\n");
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
    Boolean nextIsKb = false;
    Boolean nextIsTb = false;

    Boolean monitorMode = false;
    
    LedState changes[] = { NoChange, NoChange, NoChange, NoChange };
    
    for (int i = 1; i < argc; i++) {
        if (strcasecmp(argv[i], "monitor") == 0)
            monitorMode = true;
        else if (strcasecmp(argv[i], "-v") == 0)
            verbose = true;
        else if(strcasecmp(argv[i], "-name") == 0)
            nextIsName = true;
        else if(strcasecmp(argv[i], "-kb") == 0)
            nextIsKb = true;
        else if(strcasecmp(argv[i], "-tb") == 0)
            nextIsTb = true;
        
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
            else if (nextIsTb) {
                tbMatch = (int)strtol(argv[i], NULL, 16);
                nextIsTb = false;
            }
            else if (nextIsKb) {
                kbMatch = (int)strtol(argv[i], NULL, 16);
                nextIsKb = false;
            } else {
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
    IOHIDManagerRegisterDeviceMatchingCallback(manager, device_add_callback, NULL);
//    IOHIDManagerRegisterDeviceRemovalCallback(manager, device_remove_callback, NULL);
    IOHIDManagerScheduleWithRunLoop(
          manager,
          CFRunLoopGetMain(),
          kCFRunLoopDefaultMode
       );
    
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

static void device_add_callback(
   void *context,
   IOReturn result,
   void *sender,
   IOHIDDeviceRef ref
) {
   (void)context;
   (void)result;
   (void)sender;

     if (isKeyboardDevice(ref)) {
        CFStringRef deviceIdRef = IOHIDDeviceGetProperty(ref, CFSTR(kIOHIDProductIDKey));
        if (!deviceIdRef) return;
        uint deviceId = 0;
        CFTypeID numericTypeId = CFNumberGetTypeID();
        if (deviceIdRef && CFGetTypeID(deviceIdRef) == numericTypeId) {
            CFNumberGetValue((CFNumberRef)deviceIdRef, kCFNumberSInt32Type, &deviceId);
        }
        if (deviceId == tbMatch) {
            printf("ball found\n");
            tbDevice = (IOHIDDeviceRef)CFRetain(ref);
        }
        if (deviceId == kbMatch) {
            printf("keeb found\n");
            kbDevice = (IOHIDDeviceRef)CFRetain(ref);
        }
    }
}
//
//static void device_remove_callback(
//   void *context,
//   IOReturn result,
//   void *sender,
//   IOHIDDeviceRef ref
//) {
//    current_timestamp();
//}


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
            case 0x68: //this is KC_LNG1. use 0x47 for KC_NUM_LOCK
                changes[kHIDUsage_LED_NumLock] = Toggle;
                setKeyboard(kbDevice, keyboard, changes);
                break;
            case 0x6b:
                changes[kHIDUsage_LED_ScrollLock] = Toggle;
                setKeyboard(tbDevice, keyboard, changes);
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
    printf("Usage:\tsetleds [monitor] [-v] [-name wildcard]  [-kb num]  [-tb num] [[+|-|^][ num | caps | scroll]]\n"
           "Thus,\tsetleds +caps -num ^scroll\n"
           "will set CapsLock, clear NumLock and toggle ScrollLock.\n"
           "Any leds changed are reported for each keyboard.\n"
           "Specify -v to shows state of all leds.\n"
           "Specify -name to match keyboard name with a wildcard\n"
           "Use the \"monitor\" sub command to run continously and toggle LEDs on keypress.\n"
           "Specify \"-kb [num] -tb [num]\" to sync QMK keeb and trackball. Get \"Product ID\" values from \"System Information\"\n");
}

Boolean isKeyboardDevice(IOHIDDeviceRef device)
{
    return IOHIDDeviceConformsTo(device, kHIDPage_GenericDesktop, kHIDUsage_GD_Keyboard);
}

void setKeyboard(IOHIDDeviceRef device, CFDictionaryRef keyboardDictionary, LedState changes[])
{
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

                    // Should we try to set the led?
                    if (changes[led] != NoChange && changes[led] != current) {
                        LedState newState = changes[led];
                        if (newState == Toggle) {
                            newState = current == 0 ? On : Off;
                        }

                        IOHIDValueRef newValue = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, newState);
                        if (newValue) {
                            // IOReturn changeResult = IOHIDDeviceSetValue(device, element, newValue);
                            IOHIDDeviceSetValue(device, element, newValue);
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

void setAllKeyboards(LedState changes[])
{
    CFSetRef devices = IOHIDManagerCopyDevices(manager);
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
                        setKeyboard(deviceRefs[deviceIndex], keyboard, changes);
                    }

                free(deviceRefs);
            }
        }
        
        CFRelease(devices);
    }
    
    CFRelease(keyboard);
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
