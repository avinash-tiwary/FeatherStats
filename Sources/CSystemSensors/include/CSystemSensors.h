#ifndef CSystemSensors_h
#define CSystemSensors_h

/// Returns the hottest available Apple-silicon HID temperature in Celsius,
/// or NAN when the sensor service is unavailable.
double FSReadHIDTemperature(void);

#endif
