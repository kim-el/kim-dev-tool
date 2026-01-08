
# Issue Report: High Power Consumption with `kim_temp_bin trigger` Mode

## Context
I integrated `kim_temp_bin trigger` mode into the Content-Aware Brightness app as per the INTEGRATION_GUIDE.md. The guide stated:

> **Resource Usage:** < 0.1% CPU (Sleeps 99% of the time)

## Benchmark Setup
1. **Baseline**: Measured system with app NOT running (10 readings, 1s intervals)
2. **Load**: Measured system with app running `power_monitor_bin trigger 300 100`
3. Used `kim_temp_bin json` for all measurements (Delta Method from LLM_INSTRUCTIONS.md)

## Results

| Metric | Baseline | With App | Delta |
|--------|----------|----------|-------|
| **Power (W)** | 11.44 | 17.82 | **+6.38W** |
| **Wakeups/sec** | 7,996 | 8,518 | +522 |
| **CPU Temp (°C)** | 65.5 | 78.2 | +12.7 |

## Configuration Used
```bash
./power_monitor_bin trigger 300 100
```
- Threshold: 300mW
- Polling interval: 100ms
- Cooldown after trigger: 200ms (modified from original 1000ms)

## Questions for the Tool Author
1. The +6.4W increase contradicts the "<0.1% CPU" claim. Is the `trigger` mode designed for continuous operation, or only short bursts?
2. The SMC reads every 100ms might be the bottleneck. What's the minimum safe interval?
3. Would switching to a "push" model (IOKit notifications) instead of polling be feasible?

## Current Workaround Options
1. Increase polling interval to 500ms+ (reduces responsiveness)
2. Only run the power monitor during active use, not 24/7
3. Hybrid approach: Use OS-level triggers for app switches, power trigger only for scroll/video detection

---
*Reported: 2026-01-09T03:41+08:00*
