# KIM_DEV_TOOL: Apple Silicon Truth Monitor

> **How This README Was Written:** This documentation was developed collaboratively between a human developer and two AI assistants:
> 1. **Claude Opus 4.5** (Google Antigravity) - Initial design & logic.
> 2. **Gemini 3.0 CLI** - Optimization, low-observer streaming, and deep component breakdown.
>
> Each feature section explains **what** it is, **why** it was built that way, and **how** it's implemented. This approach ensures the reasoning behind every design decision is preserved.

---

> **Philosophy:** On Apple Silicon, optimizing for CPU % is obsolete. Optimize for **Power** (Watts), **Memory Pressure**, and **Wakeups**.

Activity Monitor shows CPU percentage, but that metric is misleading on Apple Silicon. A process using 50% CPU on efficiency cores uses far less power than 50% on performance cores. This tool shows what actually matters: real power consumption from hardware sensors.

---

## Tools Overview

We built two versions of this tool for different use cases:

| Tool | What It's For | How to Run | Latency | Overhead |
|------|---------------|------------|---------|----------|
| `kim_dev_tool.sh` | Interactive dashboard for humans | `sudo ./kim_dev_tool.sh` | 1.0s | **< 0.1% CPU** |
| `kim_temp_bin json` | Machine-readable JSON for LLMs/scripts | `./kim_temp_bin json` | ~1.5s | Low |

**Why the "Observer Effect" matters:**
In early versions, the monitoring tool itself consumed ~1 Watt of power just to run! We fixed this by rewriting the core loop in Rust to stream data directly from the kernel/SMC, avoiding heavy process spawning. The display now runs with near-zero impact on battery life.

---

## 📱 LLM JSON Mode (Full Analysis)

### What It Outputs
```bash
./kim_temp_bin json
```
```json
{
  "cpu_temp": 45.2,
  "gpu_temp": 39.5,
  "mem_temp": 36.1,
  "ssd_temp": 37.0,
  "bat_temp": 32.5,
  "power_w": 4.55,
  "bat_power_w": 10.20,
  "mem_power_w": 0.80,
  "cpu_mw": 250,
  "gpu_mw": 18,
  "ane_mw": 0,
  "battery_pct": 85,
  "charging": false,
  "mem_free_pct": 30,
  "efficiency_hrs": 6.5,
  "wakeups_per_sec": 450,
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

---

## 🔋 BATTERY Section

### What It Shows (Display Mode)
```
🔋 BATTERY:     76%   (@100%: 9.3h)
   ├─ Power Draw:  14.50 W
   ├─ Time Left:   5:32
   └─ Live @100%:  5.9h
```

### What Each Line Means

**`Power Draw: 14.50 W`** — The actual wattage flowing out of your battery (measured at the Battery Rail `PPBR`). This accounts for EVERYTHING: Screen, Speakers, CPU, Keyboard Backlight, and losses.

**`Time Left: 5:32`** — Apple's estimated time remaining based on current battery % and *instant* usage patterns.

**`Live @100%: 5.9h`** — If your battery was at 100% and you continued using it exactly like right now (e.g. watching 4K video), how long would it last?

---

## ⚡ POWER Section (The "Truth" Breakdown)

### What It Shows
```
⚡ POWER:       14.50 W   (Total System)
   ├─ CPU:       4287 mW
   ├─ GPU:       1095 mW
   ├─ ANE:          0 mW
   ├─ Memory:     800 mW   (Real Sensor)
   ├─ Screen:    8400 mW   (Est. from Rail Diff)
   └─ Misc:       250 mW   (WiFi, SSD, Losses)
```

### Data Sources & Secrets

| Metric | Source | Notes |
|--------|--------|-------|
| **Total System** | SMC key `PPBR` | We switched to "Battery Rail" because "System Power" (`PSTR`) often excludes the screen on MacBooks. |
| **CPU/GPU/ANE** | `powermetrics` | Apple's official performance counters. |
| **Memory** | SMC key `PHPM` | **Gemini Discovery:** We found this undocumented sensor that tracks LPDDR5 power accurately (~0.8W idle). |
| **Screen** | Calculated | `Total Battery - System Logic`. When you boost brightness, this number jumps. |
| **Misc** | Calculated | `System Logic - Components`. This captures WiFi radio, SSD controller, and motherboard efficiency losses. |

### Why This Breakdown Matters

Most tools just show "CPU Usage". But if your battery is draining fast and CPU is low, where is the power going?
- **High "Screen"?** Lower brightness.
- **High "Misc"?** Your WiFi is downloading something heavy or SSD is indexing.
- **High "Memory"?** You might have a stuck process thrashing RAM.

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
```

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

We use `sysctl hw.memsize` to dynamically detect your RAM size (8GB/16GB/32GB/etc) and `vm_stat` to count pages. This works on ANY Mac model automatically.

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
├── kim_dev_tool.sh      # Interactive bash script (human UI)
├── kim_temp_bin         # Compiled Rust binary (data engine)
├── kim_temp/            # Rust source code
│   ├── Cargo.toml
│   └── src/main.rs
├── README.md            # This file
└── codereview.md        # AI Review & Audit log
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

## Performance Engineering

| Mode | Latency | Power Impact | Implementation |
|------|---------|--------------|----------------|
| **Streaming** | 1.0s | **~0.05 W** | Rust loop reads SMC memory directly. Spawns `powermetrics` only every 5s. |
| **Legacy** | 1.0s | ~1.00 W | Spawning processes every second burned significant battery. |

**Why 1.5 seconds latency for JSON?**
- SMC sensors: ~10ms (Instant)
- powermetrics (CPU/GPU/ANE): ~1000ms sample window
- Battery/memory queries: ~100ms

The slowest part is `powermetrics` because it needs to sample over time to calculate accurate power values.

---

## 📝 License

MIT — Use it, modify it, ship it.