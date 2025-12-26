---
description: Check system metrics (temp, power, battery)
---

To check Mac system performance and health, run:

```bash
./kim_temp_bin json
```

This returns JSON with:
- CPU/GPU/Memory/SSD/Battery temperatures
- Total power draw and breakdown (CPU/GPU/ANE)
- Battery percentage and efficiency
- Process wakeups (battery drainers)

Parse the output and analyze:
- If temps >60°C, system is running hot
- If efficiency_hrs <6h, heavy usage
- Check high_wakeups array for battery.drainers
