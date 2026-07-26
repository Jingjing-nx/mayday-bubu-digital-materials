#include <ApplicationServices/ApplicationServices.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <IOKit/hidsystem/IOHIDShared.h>
#include <IOKit/hidsystem/IOLLEvent.h>
#include <mach/mach.h>
#include <stdbool.h>
#include <string.h>

bool BubuIsAccessibilityTrusted(void) {
    return AXIsProcessTrusted();
}

bool BubuRequestAccessibilityPermission(void) {
    const void *keys[] = {kAXTrustedCheckOptionPrompt};
    const void *values[] = {kCFBooleanTrue};
    CFDictionaryRef options = CFDictionaryCreate(
        kCFAllocatorDefault,
        keys,
        values,
        1,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    bool trusted = AXIsProcessTrustedWithOptions(options);
    CFRelease(options);
    return trusted;
}

// Chromium ignores synthetic CGEvent drag messages for avatar direction
// changes on some macOS versions. Posting through IOHIDSystem follows the same
// WindowServer path as a real held mouse button, which keeps the gesture state
// and its animation in sync.
bool BubuPostPhysicalLeftDrag(int x, int y) {
    if (!BubuIsAccessibilityTrusted()) {
        return false;
    }
    static io_connect_t connection = IO_OBJECT_NULL;
    if (connection == IO_OBJECT_NULL) {
        io_service_t service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem")
        );
        if (service == IO_OBJECT_NULL) {
            return false;
        }
        kern_return_t openResult = IOServiceOpen(
            service,
            mach_task_self(),
            kIOHIDParamConnectType,
            &connection
        );
        IOObjectRelease(service);
        if (openResult != KERN_SUCCESS) {
            connection = IO_OBJECT_NULL;
            return false;
        }
    }

    NXEventData data;
    memset(&data, 0, sizeof(data));
    data.mouse.pressure = 255;
    data.mouse.buttonNumber = 0;
    data.mouse.click = 1;
    data.mouse.subType = NX_SUBTYPE_DEFAULT;
    IOGPoint point = {x, y};
    kern_return_t result = IOHIDPostEvent(
        connection,
        NX_LMOUSEDRAGGED,
        point,
        &data,
        kNXEventDataVersion,
        0,
        kIOHIDSetCursorPosition | kIOHIDPostHIDManagerEvent
    );
    return result == KERN_SUCCESS;
}
