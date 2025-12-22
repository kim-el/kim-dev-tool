# KIM_DEV_TOOL: Apple Silicon Truth Monitor

> **Philosophy:** On Apple Silicon, optimizing for CPU % is obsolete. Optimize for **Power** (Watts), **Memory Pressure**, and **Wakeups**.

Activity Monitor shows CPU percentage, but hides the true energy cost of GPU and Neural Engine workloads. `kim_dev_tool` is a lightweight bash wrapper around macOS's `powermetrics` that exposes the real hardware cost of your code.

---

## 🔬 What It Measures

| Metric | What It Shows | Why It Matters |
|--------|--------------|----------------|
| **Power (mW)** | Combined CPU + GPU + ANE wattage | The true energy cost, not a percentage approximation |
| **Memory Pressure** | System memory state (Normal/Warning/Critical) | When this goes red, macOS swaps to disk |
| **Thermal** | Thermal pressure level (Nominal/Fair/Serious/Critical) | Explains throttling behavior |
| **Wakeups/sec** | CPU interrupts per second | The silent battery killer — frequent wakeups cost more than bursts of work |
| **Battery Impact** | Apps with >100 wakeups/sec | Highlights which apps are draining your battery |

---

## 🚀 Quick Start

```bash
# Make executable
chmod +x kim_dev_tool.sh

# Run (requires sudo for SMC access)
sudo ./kim_dev_tool.sh
```

---

## 📊 Sample Output

```
========================================================================
           🔬 KIM_DEV_TOOL: Apple Silicon Truth Monitor
========================================================================
⚡ POWER:         205 mW   (Base: 347 | Δ -142)
   ├─ CPU:       202 mW 
   ├─ GPU:         3 mW
   └─ ANE:         0 mW

🧠 MEMORY:     Normal   (33% avail)
🌡️  THERMAL:    Nominal
💤 WAKEUPS:     1510 /s

------------------------------------------------------------------------
TOP PROCESSES                       |   CPU ms/s |    WAKEUPS
------------------------------------------------------------------------
kernel_task                         |      42.16 |     714.06
WindowServer                        |      23.27 |      53.41
language_server_macos_arm           |       9.64 |     590.43
...
------------------------------------------------------------------------

🔋 BATTERY IMPACT: Apps with high wakeups (>100/s):
   ⚠️  language_server_macos_arm (590/s)
   → These apps prevent deep sleep and drain battery faster
------------------------------------------------------------------------
```

---

## 🔋 Understanding Battery Impact

Apple's "18 hours of battery" claim is based on minimal workload. In reality:

| App Type | Typical Wakeups/sec | Battery Impact |
|----------|---------------------|----------------|
| Safari (idle tabs) | 10-50 | Low |
| VS Code / Cursor (LSP active) | 300-600 | High |
| Chrome (with extensions) | 100-300 | Medium-High |
| Electron apps (Slack, Discord) | 50-200 | Medium |
| Bluetooth scanning | 20-50 | Low |

**Rule of thumb:** If an app has >100 wakeups/sec when you're not actively using it, it's draining your battery unnecessarily.

---

## 🎯 How To Use This For Optimization

| Observation | Action |
|-------------|--------|
| Battery Impact shows an app | Quit it when not needed, or find alternatives |
| High wakeups from background apps | Disable background refresh or notifications |
| Memory: Warning/Critical | Close apps or investigate memory leaks |
| Thermal: Fair/Serious | Your Mac is hot — reduce workload or improve ventilation |

---

## ⚙️ Requirements

- macOS (Apple Silicon recommended, Intel supported)
- `sudo` access (required for `powermetrics`)
- No external dependencies — uses only native macOS tools

---

## 📝 License

MIT — Use it, modify it, ship it.
