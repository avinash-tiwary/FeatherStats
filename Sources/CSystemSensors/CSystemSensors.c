#include "CSystemSensors.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <dispatch/dispatch.h>
#include <math.h>

typedef struct __IOHIDEvent *IOHIDEventRef;

// Present in IOKit on Apple silicon but not declared in the public SDK headers.
extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern void IOHIDEventSystemClientSetMatching(
    IOHIDEventSystemClientRef client,
    CFDictionaryRef matching
);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(
    IOHIDServiceClientRef service,
    int64_t eventType,
    int32_t matchingEvent,
    int64_t options
);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

static IOHIDEventSystemClientRef temperatureClient = NULL;
static CFArrayRef temperatureServices = NULL;

static void initializeTemperatureServices(void *context) {
    temperatureClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!temperatureClient) return;

    int usagePageValue = 0xff00;
    int usageValue = 5;
    CFNumberRef usagePage = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usagePageValue);
    CFNumberRef usage = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usageValue);
    const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
    const void *values[] = { usagePage, usage };
    CFDictionaryRef matching = CFDictionaryCreate(
        kCFAllocatorDefault,
        keys,
        values,
        2,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );

    IOHIDEventSystemClientSetMatching(temperatureClient, matching);
    temperatureServices = IOHIDEventSystemClientCopyServices(temperatureClient);
    CFRelease(matching);
    CFRelease(usagePage);
    CFRelease(usage);
}

double FSReadHIDTemperature(void) {
    static dispatch_once_t onceToken;
    dispatch_once_f(&onceToken, NULL, initializeTemperatureServices);
    if (!temperatureServices) return NAN;

    const int64_t temperatureEventType = 15;
    const int32_t temperatureField = 15 << 16;
    double hottest = NAN;

    CFIndex count = CFArrayGetCount(temperatureServices);
    for (CFIndex index = 0; index < count; index++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)
            CFArrayGetValueAtIndex(temperatureServices, index);
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(
            service, temperatureEventType, 0, 0
        );
        if (!event) continue;

        double value = IOHIDEventGetFloatValue(event, temperatureField);
        CFRelease(event);
        if (value >= 10.0 && value <= 115.0 && (isnan(hottest) || value > hottest)) {
            hottest = value;
        }
    }
    return hottest;
}
