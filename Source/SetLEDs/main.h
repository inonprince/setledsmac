/*  setleds for Mac
 http://github.com/damieng/setledsmac
 Copyright 2015 Damien Guard. GPL 2 licenced.
 */

#ifndef SetLEDs_main_h
#define SetLEDs_main_h

#include <CoreFoundation/CoreFoundation.h>
#include <Carbon/Carbon.h>
#include <IOKit/hid/IOHIDLib.h>
#include <fnmatch.h>

const int maxLeds = 3;
const char* ledNames[] = { "num", "caps", "scroll" };
const char* stateSymbol[] = {"-", "+" };
typedef enum { NoChange = -1, Off, On, Toggle } LedState;
typedef enum { MODE_TRACKBALL_SIGNALED, MODE_OS_MONITORED } AutomouseMode;

void parseOptions(int argc, const char * argv[]);
void explainUsage(void);
void startMonitor(void);
void setAllKeyboards(LedState changes[]);
void setKeyboard(IOHIDDeviceRef device, CFDictionaryRef keyboardDictionary, LedState changes[]);
void send_feature_report(IOHIDDeviceRef device, bool active);
void send_raw_hid_command(IOHIDDeviceRef device, uint8_t command);
CFMutableDictionaryRef getJoystickDictionary(void);
CFMutableDictionaryRef getKeyboardDictionary(void);
CGEventRef eventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon);
void mouse_idle_timeout(CFRunLoopTimerRef timer, void *info);
static void device_add_callback(void* context, IOReturn result, void* sender, IOHIDDeviceRef device);
static void device_remove_callback(void* context, IOReturn result, void* sender, IOHIDDeviceRef device);
static void vendor_device_add_callback(void* context, IOReturn result, void* sender, IOHIDDeviceRef device);
static void vendor_device_remove_callback(void* context, IOReturn result, void* sender, IOHIDDeviceRef device);
static void tb_raw_hid_add_callback(void* context, IOReturn result, void* sender, IOHIDDeviceRef device);
static void tb_raw_hid_remove_callback(void* context, IOReturn result, void* sender, IOHIDDeviceRef device);
void joystickAction(void* inContext, IOReturn inResult, void* inSender, IOHIDValueRef value);

Boolean isKeyboardDevice(IOHIDDeviceRef device);
#endif

