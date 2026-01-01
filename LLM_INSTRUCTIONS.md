# 🤖 Instructions for AI Agents (LLMs)

If you are an AI assistant (Claude, Gemini, ChatGPT) asked to use this tool, please follow these patterns to ensure efficiency and accuracy.

---

## 1. Quick Status Check (The Standard)

If the user asks "Why is my Mac hot?" or "Check power usage":

**Run this command ONCE:**
```bash
./kim_temp_bin json
```

**Why only once?**
- The tool performs an internal 1-second sampling window. The data returned is already a stable average, not a microsecond spike.
- Running it in a loop floods the context window with repetitive JSON tokens.

**How to Interpret the Output:**
```json
{
  "power_w": 4.5,       // Logic Board Power (CPU + GPU + WiFi + Memory)
  "bat_power_w": 12.0,  // Total Battery Drain (Includes Screen!)
  "cpu_temp": 45.0,
  ...
}
```
- **If `bat_power_w` > `power_w`:** The difference is mostly **Screen Brightness**.
- **If `power_w` is high (e.g. >10W):** Check the `top_cpu` list.
- **If `wakeups_per_sec` > 500:** Check the `high_wakeups` list (Silent battery killers).

---

## 2. Deep Monitoring (Time-Based)

If the user asks "Monitor while I run a benchmark" or "Watch for 30 seconds":

**❌ DO NOT:** Run a loop that prints to stdout.
```bash
# BAD: Floods context window, crashes browser
for i in {1..30}; do ./kim_temp_bin json; sleep 1; done
```

**✅ DO:** Log to a file, then analyze.
```bash
# GOOD: Silent collection
timeout 30 ./kim_temp_bin stream > /tmp/power_log.jsonl
```

**After the command finishes, analyze the data:**
```bash
# Get Average Power
jq -s 'map(.bat_power_w) | add / length' /tmp/power_log.jsonl

# Find Peak CPU Power
jq -s 'map(.cpu_mw) | max' /tmp/power_log.jsonl

# Identify Spiking Processes
jq -r '.top_cpu[0].name' /tmp/power_log.jsonl | sort | uniq -c | sort -nr
```

---

## 3. Troubleshooting "Zero" Values

- **Screen Power = 0?** This happens if `bat_power_w` (Battery) reads slightly lower than `power_w` (System) due to sensor timing. Treat it as "Low/Idle".
- **Misc Power = 0?** Same reason. Sensors are asynchronous.
- **Memory Power?** We found the specific sensor `PHPM` was static on some M-series chips, so we removed it from the UI. Trust `power_w` as the logic board total.

---

## 4. Key Capabilities (What you can see)

| Metric | Source | Accuracy |
|--------|--------|----------|
| **Total Power** | Battery Rail (`PPBR`) | ⚡ High (Real hardware sensor) |
| **CPU/GPU** | Performance Counters | ⚡ High (Exact silicon counters) |
| **Screen** | `Total - System` | ⚠️ Estimate (Good for trends) |
| **WiFi/SSD** | `System - Components` | ⚠️ Estimate (Hides in "Misc") |
