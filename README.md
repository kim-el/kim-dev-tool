# KIM_DEV_TOOL: Apple Silicon Truth Monitor

> **How This README Was Written:** This documentation was developed collaboratively between a human developer and an AI assistant (Claude Opus 4.5 in Google Antigravity). Each feature section explains **what** it is, **why** it was built that way, and **how** it's implemented. This approach ensures the reasoning behind every design decision is preserved.

---

> **Philosophy:** On Apple Silicon, optimizing for CPU % is obsolete. Optimize for **Power** (Watts), **Memory Pressure**, and **Wakeups**.

Activity Monitor shows CPU percentage, but that metric is misleading on Apple Silicon. A process using 50% CPU on efficiency cores uses far less power than 50% on performance cores. This tool shows what actually matters: real power consumption from hardware sensors.

---

## Tools Overview

We built two versions of this tool for different use cases:

| Tool | What It's For | How to Run | Latency |
|------|---------------|------------|---------|
| `kim_dev_tool.sh` | Interactive dashboard for humans | `sudo ./kim_dev_tool.sh` | Continuous |
| `kim_temp_bin json` | Machine-readable JSON for LLMs/scripts | `./kim_temp_bin json` | ~1.5s |

**Why two versions?**
- The display version has colors, emojis, and formatting that's great for humans but hard for LLMs to parse
- The JSON version outputs ~180 tokens of structured data that LLMs can instantly understand
- Same data sources, different presentation

---

## 📱 LLM JSON Mode (Full Analysis)

### What It Outputs
```bash
./kim_temp_bin json
```
```json
{
  "cpu_temp": 62.9,
  "gpu_temp": 51.3,
  "mem_temp": 40.1,
  "ssd_temp": 41.7,
  "bat_temp": 34.0,
  "power_w": 16.66,
  "cpu_mw": 3731,
  "gpu_mw": 18,
  "ane_mw": 0,
  "battery_pct": 31,
  "charging": false,
  "mem_free_pct": 30,
  "efficiency_hrs": 3.1,
  "wakeups_per_sec": 8613,
  "top_cpu": [
    {"name": "WindowServer", "cpu_ms": 132.0, "wakeups": 64.1},
    {"name": "mds_stores", "cpu_ms": 95.2, "wakeups": 0.0}
  ],
  "high_wakeups": [
    {"name": "language_server_macos_arm", "cpu_ms": 1.8, "wakeups": 238.0}
  ]
}
```

### Why We Built This

When we were debugging power issues, we found ourselves NOT using the display tool we built. Why? Because:
1. It runs continuously (can't just get one reading)
2. Output is hard to parse (colors, emojis, formatting)
3. Needed sudo and password prompts

**Solution:** A one-shot JSON command that LLMs can call directly.

### Two Process Lists: Why?

**`top_cpu`** - Processes sorted by CPU usage. Shows what's actively working.

**`high_wakeups`** - Processes with >50 wakeups/sec, regardless of CPU usage.

**Why both?**
- A process can use 0.5ms CPU but 500 wakeups/sec
- It looks "idle" in Activity Monitor but drains battery
- These are "silent killers" that only `high_wakeups` catches

---

## 🔋 BATTERY Section

### What It Shows (Display Mode)
```
🔋 BATTERY:     49%   (@100%: 8.2h)
   ├─ Power Draw:  8.9 W
   ├─ Time Left:   5:32
   └─ Live @100%: 5.9h
```

### What Each Line Means

**`@100%: 8.2h`** — If your battery was at 100% and you continued using it exactly like right now, how long would it last? This uses a **10-minute rolling average** to give a stable number (not affected by temporary spikes).

**`Power Draw: 8.9 W`** — The actual wattage your entire system is consuming right now. This comes directly from Apple's SMC hardware sensor, not an estimate.

**`Time Left: 5:32`** — Apple's estimated time remaining based on current battery % and usage patterns.

**`Live @100%: 5.9h`** — Same calculation as the header, but uses the **instant** power reading instead of the average. Useful for seeing immediate impact when you change something.

### Why Two Efficiency Numbers (Average vs Live)?

**Problem:** Instant power readings jump around constantly. Open a webpage = spike to 20W. Close it = back to 5W. This makes it hard to understand your "real" efficiency.

**Solution:** 
- **Header (@100%)** = 10-minute rolling average (stable, like Activity Monitor)
- **Live @100%** = Instant reading (reacts immediately to changes)

Comparing them tells you: "Is my current activity typical or a spike?"

### How Battery Capacity is Calculated

**Problem:** We originally hardcoded 52Wh, but:
- MacBook Air 13" M4 = 53.8 Wh
- MacBook Air 15" M4 = 66.5 Wh
- MacBook Pro 14" = 70 Wh
- MacBook Pro 16" = 100 Wh

**Solution:** Read the capacity dynamically from your Mac:

```bash
# Get design capacity in mAh
ioreg -r -c AppleSmartBattery | grep "DesignCapacity"

# Convert to Wh
battery_wh = capacity_mah × 11.4V ÷ 1000
```

This works for any Mac model automatically.

---

## ⚡ POWER Section

### What It Shows
```
⚡ POWER:       8.9 W   (Total System)
   ├─ CPU:       800 mW
   ├─ GPU:        50 mW
   ├─ ANE:         0 mW
   └─ Other:    8050 mW   (Display, SSD, WiFi, etc)
```

### Data Sources

| Metric | Source | Why This Source |
|--------|--------|-----------------|
| **Total System Power** | SMC key `PSTR` | Direct hardware sensor, most accurate |
| **CPU/GPU/ANE** | `powermetrics` | Apple's official tool, includes all power domains |
| **Other** | Calculated | `Total - (CPU + GPU + ANE)` |

### Why We Use powermetrics Instead of SMC for CPU/GPU

**We tried SMC first.** SMC has keys like `PP0b` (CPU) and `PP7b` (GPU).

**The problem:** These only capture partial power. For example, CPU has multiple power domains (efficiency cores, performance cores, cache, etc.). SMC keys only show one rail.

**powermetrics** aggregates all power domains correctly. When we compared the numbers, powermetrics matched our total power much better.

### Why "Other" Power Matters

If "Other" is 6W of your 8W total, that's 75% of your power going to display, SSD, WiFi, etc.

**Actionable insight:** Dimming your screen would be more effective than closing apps.

---

## 🌡️ THERMAL Section

### What It Shows
```
🌡️  THERMAL:    54.9°C   (Target: <60°C) ✅
   ├─ CPU:        54.9°C
   ├─ GPU:        48.1°C
   ├─ Memory:     40.3°C
   ├─ SSD:        41.7°C
   └─ Battery:    34.6°C
```

### Why We Built Our Own Temperature Reader

**Problem:** There's no easy way to get Apple Silicon temperatures.
- `osx-cpu-temp` doesn't work on M-series chips
- IOReport framework was blocked by Apple
- Activity Monitor shows temperatures but provides no API

**Solution:** We built a Rust binary (`kim_temp_bin`) that reads directly from Apple's SMC (System Management Controller).

### How Temperature Reading Works

```rust
// We scan all SMC keys starting with 'T' (temperature)
for key in smc.keys() {
    if key.starts_with('T') {
        // Tp*, Te*, Tc* = CPU sensors
        // Tg* = GPU sensors
        // TM* = Memory sensors
        // TS* = SSD sensors
        // TB* = Battery sensors
    }
}
// Each component has multiple sensors; we average them
```

**Why Rust?** The `smc` crate provides safe access to macOS SMC. Compiles to a fast native binary with no runtime dependencies.

---

## 🧠 MEMORY Section

### What It Shows
```
🧠 MEMORY:     43% free   (Target: >30%) ✅
```

### Why Memory % Instead of GB

On Macs with unified memory, the exact GB used is less important than **whether you have headroom**. When memory gets low:
1. macOS starts compressing memory (uses CPU = power)
2. Then swaps to SSD (kills performance AND SSD lifespan)

The % free tells you: "Am I close to trouble?"

### How It's Calculated

```bash
# From vm_stat, we count:
# - Pages free (immediately available)
# - Pages inactive (reclaimable)
# - Pages speculative (pre-loaded, reclaimable)

free_pct = (free + inactive + speculative) ÷ total × 100
```

**Why include inactive and speculative?** These are pages macOS can reclaim instantly if needed. Only counting "free" would underestimate available memory.

---

## 💤 WAKEUPS Section

### What It Shows
```
💤 WAKEUPS:     520/s   (Target: <500/s) ✅
```

### What Are Wakeups?

Every time an app asks the CPU to do something, it "wakes up" the CPU. When idle, the CPU enters deep sleep states to save power. Frequent wakeups prevent this.

### Why This Is Critical for Battery

**Example:** An app checking for updates every 100ms = 10 wakeups/sec. Sounds small, right?

**The problem:** Each wakeup prevents the CPU from entering deep sleep. An app can use 0% CPU but 500 wakeups/sec. It looks idle in Activity Monitor, but it's constantly interrupting the CPU's sleep.

**This is why your MacBook sometimes drains overnight** even with the lid closed - some app is constantly waking the CPU.

### How We Detect "Silent Killers"

We added a `high_wakeups` array that catches processes with >50 wakeups/sec, even if their CPU usage is near zero.

**Example from real data:**
```json
{"name": "language_server_macos_arm", "cpu_ms": 0.8, "wakeups": 238.0}
```

This process uses only 0.8ms of CPU time but does 238 wakeups per second. It would never appear in a "top CPU" list, but it's a battery drainer.

---

## ⚙️ Setup

### Basic Usage
```bash
chmod +x kim_dev_tool.sh
sudo ./kim_dev_tool.sh
```

### Enable LLM Mode (No Password Prompts)

The LLM JSON mode needs to run `powermetrics` which normally requires sudo. To avoid password prompts:

```bash
echo 'YOUR_USERNAME ALL=(ALL) NOPASSWD: /usr/bin/powermetrics' | sudo tee /etc/sudoers.d/kim_metrics
```

Replace `YOUR_USERNAME` with your macOS username (run `whoami` to check).

After this, `./kim_temp_bin json` works without any password prompts.

---

## 📁 File Structure

```
Apple Silicon Benchmarking tools/
├── kim_dev_tool.sh      # Interactive bash script (display mode)
├── kim_temp_bin         # Compiled Rust binary (LLM mode)
├── kim_temp/            # Rust source code
│   ├── Cargo.toml
│   └── src/main.rs
├── README.md            # This file
└── TODO.md              # Future improvements
```

---

## 🔧 Rebuilding kim_temp_bin

If you modify the Rust code:
```bash
cd kim_temp
cargo build --release
cp target/release/kim_temp ../kim_temp_bin
```

---

## Performance

| Mode | Latency | Tokens | Use Case |
|------|---------|--------|----------|
| `kim_temp_bin json` | ~1.5s | ~180 | Full analysis, debugging |
| Display mode | Continuous | N/A | Human monitoring |

**Why 1.5 seconds?**
- SMC sensors: ~400ms
- powermetrics (CPU/GPU/ANE + processes): ~1000ms
- Battery/memory queries: ~100ms

The slowest part is `powermetrics` because it needs to sample over time to calculate accurate power values.

---

## 📝 License

MIT — Use it, modify it, ship it.
