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

void parseOptions(int argc, const char * argv[]);
void explainUsage(void);
void startMonitor(void);
void setAllKeyboards(LedState changes[]);
void setKeyboard(IOHIDDeviceRef device, CFDictionaryRef keyboardDictionary, LedState changes[]);
CFMutableDictionaryRef getKeyboardDictionary(void);
CGEventRef eventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon);
static void device_add_callback(void* context, IOReturn result, void* sender, IOHIDDeviceRef device);
//static void device_remove_callback(void* context, IOReturn result, void* sender, IOHIDDeviceRef device);
Boolean isKeyboardDevice(IOHIDDeviceRef device);
#endif

