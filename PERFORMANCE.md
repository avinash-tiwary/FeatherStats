# FeatherStats resource profile

Profiled on Apple silicon with 18 GiB unified memory using the packaged release build.

## Production footprint

| Measure | Result |
| --- | ---: |
| Application bundle | 564 KiB |
| Compressed DMG | 412 KiB |
| Physical footprint after warm-up | 21 MiB |
| Peak physical footprint in the final run | 22 MiB |
| Observed RSS range | 12.8–25.0 MiB |
| RSS after the final trace | 16.4 MiB |
| CPU time added over 60 seconds | 0.37 seconds |
| Average CPU use | 0.62% of one logical core |
| Average share of this 11-core system | about 0.06% |

RSS moved both upward and downward during the trace instead of growing monotonically. This is expected as AppKit pages and purges framework caches.

## Leak checks

- A normal production trace remained bounded over three minutes of recurring samples.
- A temporary `get-task-allow` build was run with malloc stack logging.
- The first `leaks` snapshot found 18,816 bytes retained entirely by three macOS `NSXPCConnection`/AppIntents root cycles. No stack entered FeatherStats code.
- A baseline memory graph was captured, the app completed another two minutes of CPU, memory, temperature, disk, and battery refreshes, and `leaks --diffFrom` reported **0 new leaks for 0 bytes**.
- The temporary instrumented build and memory graph were removed after testing.

This does not mathematically prove that no leak can ever exist, but it rules out a per-refresh leak in the exercised paths and found no application-owned leak with Apple's allocation tooling.

## Sampling policy

To avoid repeatedly paying the hardware-sensor cost, refresh rates are tiered:

- CPU and unified memory: 3 seconds
- Temperature and battery: 30 seconds
- Disk: 60 seconds

This preserves a responsive menu-bar reading while keeping average utilization low.
