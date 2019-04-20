# SetLEDs for Mac OS X + Monitor Mode

---
Original project: https://github.com/damieng/setledsmac
---

This command-line tool lets you set your keyboard LEDs. This is especially useful if you have a back-lit keyboard and don't want scroll lock, number lock or caps lock to remain unlit.

## Note
Setting the LED on or off does not affect the behavior of that key so even though the led for caps lock will be on caps lock itself will still be off. Tapping the key will cause the lock to come on but the LED will already be on so it will not appear to change. Tapping it again will turn it off (and cause the LED to turn off).

## Usage
You can set LEDs by simply specifing either a - to turn an LED off, a + to turn an LED on or a ^ to toggle an LED followed by either the word scroll (for scroll lock), num (for numeric lock) or caps (for caps lock). e.g.

```bash
setleds -caps +scroll ^num
```

### Name matching
By default setledsmac will set the modifiers for all keyboards attached to your Mac. If you wish to limit it you can use the -name parameter followed by a wildcard. Note that if you want to use a space then specify the wildcard in quotes, e.g.

```bash
setleds +scroll -name "Apple Key*"
```

### Verbose mode
setledsmac will report what keys it changed for each keyboard. This is sometimes different per keyboard if either the keyboard does not have that modifier (e.g. Apple keyboards do not have scroll lock) or if the keyboard already had that LED on.

Specifying -v on the command line will cause setledsmac to report the state of the other unchanged modifier keys on that keyboard too. Note that you will not see the state of modifiers that keyboard does not have.

### Monitor mode

Use the "monitor" sub command to run continuously and toggle LEDs on keypress. This allows running the binary as a daemon at startup for seamless functionality. This is useful if you have a keyboard incompatible with OSX that require frequent toggling of numlock keys (i.e., TKL CoolerMaster CM keyboards)

Usage:
```
$ setleds monitor
```

You may use the bundled LaunchDaemon configuration to launch setleds at startup.

```bash
# Build the binary from the sources or download the pre-built release from the github repo.
# Copy it to /usr/bin/setleds
$ cp Source/build/Release/SetLeds /usr/bin/setleds
$ chmod +x /usr/bin/setleds

# Copy the LaunchDaemon configuration
$ cp com.rajiteh.setleds.plist /Library/LaunchDaemons/com.rajiteh.setleds.plist
$ sudo chown root:wheel /Library/LaunchDaemons/com.rajiteh.setleds.plist

# Enable the launch configuration
$ sudo launchctl load /Library/LaunchDaemons/com.rajiteh.setleds.plist
```

Restart the mac and now you should have numlock toggling functionality without extra action, just like a normal keyboard!