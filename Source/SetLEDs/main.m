
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
IOHIDDeviceRef vendorDevice;
static IOHIDManagerRef vendor_manager = NULL;

static AutomouseMode automouse_mode = MODE_TRACKBALL_SIGNALED;
static bool automouse_active = false;
static CFRunLoopTimerRef mouse_idle_timer = NULL;
static const CFTimeInterval MOUSE_IDLE_TIMEOUT = 0.45; // 450ms
static dispatch_queue_t led_queue = NULL; // serial queue for async LED I/O

static void pointing_device_added(void *context, IOReturn result, void *sender, IOHIDDeviceRef device);

static int blacklist_pids[16];
static int blacklist_count = 0;
static CFAbsoluteTime last_blacklisted_input = 0;
static IOHIDManagerRef pointing_manager = NULL;
static const CFAbsoluteTime BLACKLIST_WINDOW = 0.015; // 15ms correlation window

void current_timestamp() {
    struct timeval te;
    gettimeofday(&te, NULL); // get current time
    long long milliseconds = te.tv_sec*1000LL + te.tv_usec/1000; // calculate milliseconds
    printf("milliseconds: %lld\n", milliseconds);
}

void send_feature_report(IOHIDDeviceRef device, bool active) {
    uint8_t report[] = { 0x01, active ? 0x04 : 0x00 };  // Report ID 1, ScrollLock bit
    IOReturn ret = IOHIDDeviceSetReport(
        device, kIOHIDReportTypeFeature, 0x01, report, sizeof(report));
    if (verbose) printf("Feature report: automouse=%s (ret=0x%x)\n",
                        active ? "ON" : "OFF", ret);
}

int main(int argc, const char * argv[])
{
    setlinebuf(stdout);
    setlinebuf(stderr);
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
    Boolean nextIsBlacklist = false;

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
        else if(strcasecmp(argv[i], "-os") == 0)
            automouse_mode = MODE_OS_MONITORED;
        else if(strcasecmp(argv[i], "-blacklist") == 0)
            nextIsBlacklist = true;
        
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
            }
            else if (nextIsBlacklist) {
                char *str = strdup(argv[i]);
                char *token = strtok(str, ",");
                while (token && blacklist_count < 16) {
                    blacklist_pids[blacklist_count++] = (int)strtol(token, NULL, 16);
                    token = strtok(NULL, ",");
                }
                free(str);
                nextIsBlacklist = false;
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
    IOHIDManagerRegisterInputValueCallback(manager, joystickAction, NULL);
    IOHIDManagerRegisterDeviceRemovalCallback(manager, device_remove_callback, NULL);
    IOHIDManagerScheduleWithRunLoop(
          manager,
          CFRunLoopGetMain(),
          kCFRunLoopDefaultMode
       );
    
    // Set up vendor HID manager for feature report channel (bypasses KVM)
    if (kbMatch && automouse_mode == MODE_OS_MONITORED) {
        vendor_manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
        if (vendor_manager) {
            IOHIDManagerOpen(vendor_manager, kIOHIDOptionsTypeNone);

            // Match vendor-defined usage page (0xFF00) with the keyboard's vendor ID
            UInt32 vendorPage = 0xFF00;
            UInt32 vendorUsage = 0x01;
            CFMutableDictionaryRef vendorDict = CFDictionaryCreateMutable(kCFAllocatorDefault, 2,
                &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            CFNumberRef vp = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vendorPage);
            CFNumberRef vu = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vendorUsage);
            CFDictionarySetValue(vendorDict, CFSTR(kIOHIDDeviceUsagePageKey), vp);
            CFDictionarySetValue(vendorDict, CFSTR(kIOHIDDeviceUsageKey), vu);
            CFRelease(vp); CFRelease(vu);

            IOHIDManagerSetDeviceMatching(vendor_manager, vendorDict);
            CFRelease(vendorDict);

            IOHIDManagerRegisterDeviceMatchingCallback(vendor_manager, vendor_device_add_callback, NULL);
            IOHIDManagerRegisterDeviceRemovalCallback(vendor_manager, vendor_device_remove_callback, NULL);
            IOHIDManagerScheduleWithRunLoop(vendor_manager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);

            if (verbose) printf("Vendor HID manager initialized for feature report channel\n");
        }
    }

    // Set up blacklist monitoring for pointing devices
    if (blacklist_count > 0 && automouse_mode == MODE_OS_MONITORED) {
        pointing_manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
        if (pointing_manager) {
            IOHIDManagerOpen(pointing_manager, kIOHIDOptionsTypeNone);

            UInt32 gdPage = kHIDPage_GenericDesktop;
            UInt32 mouseUsage = kHIDUsage_GD_Mouse;
            UInt32 ptrUsage = kHIDUsage_GD_Pointer;

            CFMutableDictionaryRef mouseDict = CFDictionaryCreateMutable(kCFAllocatorDefault, 2,
                &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            CFNumberRef mp = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &gdPage);
            CFNumberRef mu = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &mouseUsage);
            CFDictionarySetValue(mouseDict, CFSTR(kIOHIDDeviceUsagePageKey), mp);
            CFDictionarySetValue(mouseDict, CFSTR(kIOHIDDeviceUsageKey), mu);
            CFRelease(mp); CFRelease(mu);

            CFMutableDictionaryRef ptrDict = CFDictionaryCreateMutable(kCFAllocatorDefault, 2,
                &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
            CFNumberRef pp = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &gdPage);
            CFNumberRef pu = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &ptrUsage);
            CFDictionarySetValue(ptrDict, CFSTR(kIOHIDDeviceUsagePageKey), pp);
            CFDictionarySetValue(ptrDict, CFSTR(kIOHIDDeviceUsageKey), pu);
            CFRelease(pp); CFRelease(pu);

            CFDictionaryRef matchDicts[] = { mouseDict, ptrDict };
            CFArrayRef matchArray = CFArrayCreate(kCFAllocatorDefault,
                (const void **)matchDicts, 2, &kCFTypeArrayCallBacks);
            CFRelease(mouseDict); CFRelease(ptrDict);

            IOHIDManagerSetDeviceMatchingMultiple(pointing_manager, matchArray);
            CFRelease(matchArray);

            IOHIDManagerRegisterDeviceMatchingCallback(pointing_manager, pointing_device_added, NULL);
            IOHIDManagerScheduleWithRunLoop(pointing_manager, CFRunLoopGetMain(), kCFRunLoopDefaultMode);

            if (verbose) {
                printf("Blacklist active for %d device(s):", blacklist_count);
                for (int i = 0; i < blacklist_count; i++) printf(" 0x%x", blacklist_pids[i]);
                printf("\n");
            }
        }
    }

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
    led_queue = dispatch_queue_create("org.inonio.setleds.led", DISPATCH_QUEUE_SERIAL);

    @autoreleasepool {
        eventMask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) | CGEventMaskBit(kCGEventFlagsChanged);
        if (automouse_mode == MODE_OS_MONITORED) {
            eventMask |= CGEventMaskBit(kCGEventMouseMoved);
            printf("OS-monitored automouse enabled.\n");
        }
    
//        eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, 0, eventMask, eventCallback, NULL);
        eventTap = CGEventTapCreate(kCGHIDEventTap,
                                    kCGHeadInsertEventTap, // kCGTailAppendEventTap,
                                    kCGEventTapOptionDefault, // kCGEventTapOptionListenOnly,
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

void joystickAction(void* inContext, IOReturn inResult, void* inSender, IOHIDValueRef value) {
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
static void device_remove_callback(
   void *context,
   IOReturn result,
   void *sender,
   IOHIDDeviceRef ref
) {
   (void)context;
   (void)result;
   (void)sender;

    if (ref == tbDevice) {
        printf("ball removed\n");
        CFRelease(tbDevice);
        tbDevice = NULL;
    }
    if (ref == kbDevice) {
        printf("keeb removed\n");
        CFRelease(kbDevice);
        kbDevice = NULL;
        // Cancel any pending automouse timeout if no vendor device either
        if (!vendorDevice) {
            if (mouse_idle_timer != NULL) {
                CFRunLoopTimerInvalidate(mouse_idle_timer);
                CFRelease(mouse_idle_timer);
                mouse_idle_timer = NULL;
            }
            automouse_active = false;
        }
    }
}


static void vendor_device_add_callback(
   void *context,
   IOReturn result,
   void *sender,
   IOHIDDeviceRef ref
) {
   (void)context;
   (void)result;
   (void)sender;

    CFNumberRef pidRef = IOHIDDeviceGetProperty(ref, CFSTR(kIOHIDProductIDKey));
    if (!pidRef || CFGetTypeID(pidRef) != CFNumberGetTypeID()) return;

    uint deviceId = 0;
    CFNumberGetValue((CFNumberRef)pidRef, kCFNumberSInt32Type, &deviceId);

    if (deviceId == kbMatch) {
        printf("vendor HID device found (PID 0x%x)\n", deviceId);
        vendorDevice = (IOHIDDeviceRef)CFRetain(ref);
    }
}

static void vendor_device_remove_callback(
   void *context,
   IOReturn result,
   void *sender,
   IOHIDDeviceRef ref
) {
   (void)context;
   (void)result;
   (void)sender;

    if (ref == vendorDevice) {
        printf("vendor HID device removed\n");
        CFRelease(vendorDevice);
        vendorDevice = NULL;
    }
}

static void blacklisted_input_callback(void *context, IOReturn result, void *sender, IOHIDValueRef value) {
    last_blacklisted_input = CFAbsoluteTimeGetCurrent();
}

static void pointing_device_added(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    CFNumberRef pidRef = IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductIDKey));
    if (!pidRef || CFGetTypeID(pidRef) != CFNumberGetTypeID()) return;

    int pid = 0;
    CFNumberGetValue(pidRef, kCFNumberSInt32Type, &pid);

    for (int i = 0; i < blacklist_count; i++) {
        if (pid == blacklist_pids[i]) {
            if (verbose) printf("Blacklisted pointing device matched: 0x%x\n", pid);
            IOHIDDeviceRegisterInputValueCallback(device, blacklisted_input_callback, NULL);
            return;
        }
    }
}

void mouse_idle_timeout(CFRunLoopTimerRef timer, void *info)
{
    if (!vendorDevice && !kbDevice) return;
    if (verbose) printf("Mouse idle timeout — sending automouse OFF\n");
    automouse_active = false;

    if (vendorDevice) {
        send_feature_report(vendorDevice, false);
    } else {
        dispatch_async(led_queue, ^{
            LedState changes[] = { NoChange, NoChange, NoChange, NoChange };
            changes[kHIDUsage_LED_ScrollLock] = Off;
            setKeyboard(kbDevice, keyboard, changes);
        });
    }

    // Non-repeating timer is invalidated after firing; release and null
    // so the next mouse movement creates a fresh timer
    if (mouse_idle_timer != NULL) {
        CFRunLoopTimerInvalidate(mouse_idle_timer);
        CFRelease(mouse_idle_timer);
        mouse_idle_timer = NULL;
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

    // OS-monitored automouse: detect physical cursor movement
    if (kCGEventMouseMoved == type && automouse_mode == MODE_OS_MONITORED) {
        // Filter out programmatic mouse movement (scripts, AppleScript, etc.)
        int64_t sourcePid = CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID);
        if (sourcePid != 0) return event;

        if (!vendorDevice && !kbDevice) return event;

        // Skip if a blacklisted device recently sent HID input
        if (blacklist_count > 0 &&
            (CFAbsoluteTimeGetCurrent() - last_blacklisted_input) < BLACKLIST_WINDOW) {
            return event;
        }

        if (!automouse_active) {
            if (verbose) printf("Mouse movement detected — sending automouse ON\n");
            automouse_active = true;
            if (vendorDevice) {
                send_feature_report(vendorDevice, true);
            } else {
                dispatch_async(led_queue, ^{
                    LedState changes[] = { NoChange, NoChange, NoChange, NoChange };
                    changes[kHIDUsage_LED_ScrollLock] = On;
                    setKeyboard(kbDevice, keyboard, changes);
                });
            }
        }

        // Create or reset the idle timer
        if (mouse_idle_timer == NULL) {
            mouse_idle_timer = CFRunLoopTimerCreate(
                kCFAllocatorDefault,
                CFAbsoluteTimeGetCurrent() + MOUSE_IDLE_TIMEOUT,
                0, // non-repeating
                0, 0,
                mouse_idle_timeout,
                NULL
            );
            CFRunLoopAddTimer(CFRunLoopGetCurrent(), mouse_idle_timer, kCFRunLoopCommonModes);
        } else {
            CFRunLoopTimerSetNextFireDate(mouse_idle_timer, CFAbsoluteTimeGetCurrent() + MOUSE_IDLE_TIMEOUT);
        }

        return event; // never swallow mouse events
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
            case 0x5e: // KC_INTERNATIONAL_1 - trackball movement start
                if (automouse_mode == MODE_OS_MONITORED) break;
                changes[kHIDUsage_LED_ScrollLock] = On;
                setKeyboard(kbDevice, keyboard, changes);
                break;
            case 0x68: // KC_LANG1 - trackball movement stop
                if (automouse_mode == MODE_OS_MONITORED) break;
                changes[kHIDUsage_LED_ScrollLock] = Off;
                setKeyboard(kbDevice, keyboard, changes);
                break;
            case 0x47: // KP_NLCK - command from keyboard to trackball
                changes[kHIDUsage_LED_ScrollLock] = Toggle;
                setKeyboard(tbDevice, keyboard, changes);
                break;
            default:
                return event;

        }
    }
    // Swallow keyboard-to-trackball commands; in OS mode let INT1/LANG1 pass through
    if (keyCode == 0x47) {
        return nil;
    }
    if (automouse_mode != MODE_OS_MONITORED && (keyCode == 0x5e || keyCode == 0x68)) {
        return nil;
    }
    return event;
}

void explainUsage()
{
    printf("Usage:\tsetleds [monitor] [-v] [-name wildcard]  [-kb num]  [-tb num] [-os] [-blacklist pid,...] [[+|-|^][ num | caps | scroll]]\n"
           "Thus,\tsetleds +caps -num ^scroll\n"
           "will set CapsLock, clear NumLock and toggle ScrollLock.\n"
           "Any leds changed are reported for each keyboard.\n"
           "Specify -v to shows state of all leds.\n"
           "Specify -name to match keyboard name with a wildcard\n"
           "Use the \"monitor\" sub command to run continously and toggle LEDs on keypress.\n"
           "Specify \"-kb [num] -tb [num]\" to sync QMK keeb and trackball. Get \"Product ID\" values from \"System Information\"\n"
           "Specify -os for OS-level automouse detection (cursor movement from any device triggers automouse).\n"
           "  Without -os, automouse relies on trackball firmware signals (default).\n"
           "Specify -blacklist with comma-separated hex Product IDs to exclude devices from triggering automouse.\n"
           "  e.g. -blacklist 0x1234,0x5678. Use with -os. Magic Trackpad is unaffected (not a HID mouse).\n");
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
                } else {
                    long current = IOHIDValueGetIntegerValue(currentValue);
                    CFRelease(CFRetain(currentValue));

                    // Should we try to set the led?
                    if (changes[led] != NoChange) {
                        LedState newState = changes[led];
                        if (newState == Toggle) {
                            newState = current == 0 ? On : Off;
                        }

                        IOHIDValueRef newValue = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, element, 0, newState);
                        if (newValue) {
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

CFMutableDictionaryRef getJoystickDictionary()
{
    CFMutableDictionaryRef result = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    
    if (!result) return result;
    
    UInt32 inUsagePage = kHIDPage_GenericDesktop;
    UInt32 inUsage = kHIDUsage_GD_Joystick;
    
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

