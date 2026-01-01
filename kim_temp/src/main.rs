// kim_temp: Standalone Apple Silicon Sensor Reader
// Reads CPU/GPU temperature and system power from macOS SMC

use smc::SMC;
use std::env;

fn key_to_string(key: four_char_code::FourCharCode) -> String {
    let bytes = key.0.to_be_bytes();
    String::from_utf8_lossy(&bytes).to_string()
}

fn string_to_key(s: &str) -> four_char_code::FourCharCode {
    let bytes = s.as_bytes();
    let val = ((bytes[0] as u32) << 24) 
            | ((bytes[1] as u32) << 16) 
            | ((bytes[2] as u32) << 8) 
            | (bytes[3] as u32);
    four_char_code::FourCharCode(val)
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let mode = args.get(1).map(|s| s.as_str()).unwrap_or("cpu");

    // Open SMC connection
    let smc = match SMC::new() {
        Ok(s) => s,
        Err(e) => {
            eprintln!("Failed to open SMC: {:?}", e);
            println!("N/A");
            return;
        }
    };

    // Get all SMC keys
    let keys = match smc.keys() {
        Ok(k) => k,
        Err(_) => {
            println!("N/A");
            return;
        }
    };

    match mode {
        "cpu" => {
            let mut temps: Vec<f64> = Vec::new();
            
            for key in &keys {
                let key_str = key_to_string(*key);
                if key_str.starts_with("Tp") || key_str.starts_with("Te") || 
                   key_str.starts_with("Tc") || key_str.starts_with("TC") {
                    if let Ok(temp) = smc.temperature(*key) {
                        if temp > 0.0 && temp < 150.0 {
                            temps.push(temp);
                        }
                    }
                }
            }
            
            if temps.is_empty() {
                for key in &keys {
                    let key_str = key_to_string(*key);
                    if key_str.starts_with('T') {
                        if let Ok(temp) = smc.temperature(*key) {
                            if temp > 0.0 && temp < 150.0 {
                                temps.push(temp);
                            }
                        }
                    }
                }
            }
            
            if !temps.is_empty() {
                let avg = temps.iter().sum::<f64>() / temps.len() as f64;
                println!("{:.1}", avg);
            } else {
                println!("N/A");
            }
        }
        
        "gpu" => {
            let mut temps: Vec<f64> = Vec::new();
            
            for key in &keys {
                let key_str = key_to_string(*key);
                if key_str.starts_with("Tg") || key_str.starts_with("TG") {
                    if let Ok(temp) = smc.temperature(*key) {
                        if temp > 0.0 && temp < 150.0 {
                            temps.push(temp);
                        }
                    }
                }
            }
            
            if !temps.is_empty() {
                let avg = temps.iter().sum::<f64>() / temps.len() as f64;
                println!("{:.1}", avg);
            } else {
                println!("N/A");
            }
        }
        
        "battery" => {
            // TB = Battery temps
            let mut temps: Vec<f64> = Vec::new();
            
            for key in &keys {
                let key_str = key_to_string(*key);
                if key_str.starts_with("TB") {
                    if let Ok(temp) = smc.temperature(*key) {
                        if temp > 0.0 && temp < 80.0 {
                            temps.push(temp);
                        }
                    }
                }
            }
            
            if !temps.is_empty() {
                let avg = temps.iter().sum::<f64>() / temps.len() as f64;
                println!("{:.1}", avg);
            } else {
                println!("N/A");
            }
        }
        
        "memory" => {
            // TM = Memory temps
            let mut temps: Vec<f64> = Vec::new();
            
            for key in &keys {
                let key_str = key_to_string(*key);
                if key_str.starts_with("TM") || key_str.starts_with("Tm") {
                    if let Ok(temp) = smc.temperature(*key) {
                        if temp > 0.0 && temp < 100.0 {
                            temps.push(temp);
                        }
                    }
                }
            }
            
            if !temps.is_empty() {
                let avg = temps.iter().sum::<f64>() / temps.len() as f64;
                println!("{:.1}", avg);
            } else {
                println!("N/A");
            }
        }
        
        "ssd" => {
            // TSCD, TPD = SSD/Storage temps (NVMe dies)
            let mut temps: Vec<f64> = Vec::new();
            
            for key in &keys {
                let key_str = key_to_string(*key);
                if key_str.starts_with("TS") || key_str == "TSCD" {
                    if let Ok(temp) = smc.temperature(*key) {
                        if temp > 0.0 && temp < 100.0 {
                            temps.push(temp);
                        }
                    }
                }
            }
            
            if !temps.is_empty() {
                let avg = temps.iter().sum::<f64>() / temps.len() as f64;
                println!("{:.1}", avg);
            } else {
                println!("N/A");
            }
        }
        
        "power" => {
            // Read system power from PSTR key
            let pstr_key = string_to_key("PSTR");
            if let Ok(power) = smc.read_key::<f32>(pstr_key) {
                println!("{:.2}", power);
            } else {
                println!("N/A");
            }
        }
        
        "power-all" => {
            // Read all power-related keys
            let power_keys = [
                ("PSTR", "Total System"),
                ("PHPS", "Package"),
                ("PP0b", "CPU Package"),
                ("PP7b", "GPU"),
                ("PPBR", "Battery Rail"),
            ];
            
            for (key_name, label) in power_keys.iter() {
                let key = string_to_key(key_name);
                if let Ok(power) = smc.read_key::<f32>(key) {
                    println!("{}: {:.2}W", label, power);
                }
            }
        }
        
        "all" => {
            for key in &keys {
                let key_str = key_to_string(*key);
                if key_str.starts_with('T') {
                    if let Ok(temp) = smc.temperature(*key) {
                        if temp > 0.0 && temp < 150.0 {
                            println!("{}: {:.1}°C", key_str, temp);
                        }
                    }
                }
            }
        }
        
        "json" => {
            // Collect all temperature sensors
            let mut cpu_temps: Vec<f64> = Vec::new();
            let mut gpu_temps: Vec<f64> = Vec::new();
            let mut mem_temps: Vec<f64> = Vec::new();
            let mut ssd_temps: Vec<f64> = Vec::new();
            let mut bat_temps: Vec<f64> = Vec::new();
            
            for key in &keys {
                let key_str = key_to_string(*key);
                if key_str.starts_with('T') {
                    if let Ok(temp) = smc.temperature(*key) {
                        if temp > 0.0 && temp < 150.0 {
                            if key_str.starts_with("Tp") || key_str.starts_with("Te") || key_str.starts_with("Tc") {
                                cpu_temps.push(temp);
                            } else if key_str.starts_with("Tg") {
                                gpu_temps.push(temp);
                            } else if key_str.starts_with("TM") || key_str.starts_with("Tm") {
                                mem_temps.push(temp);
                            } else if key_str.starts_with("TS") || key_str == "TSCD" {
                                ssd_temps.push(temp);
                            } else if key_str.starts_with("TB") {
                                bat_temps.push(temp);
                            }
                        }
                    }
                }
            }
            
            let cpu_avg = if cpu_temps.is_empty() { 0.0 } else { cpu_temps.iter().sum::<f64>() / cpu_temps.len() as f64 };
            let gpu_avg = if gpu_temps.is_empty() { 0.0 } else { gpu_temps.iter().sum::<f64>() / gpu_temps.len() as f64 };
            let mem_avg = if mem_temps.is_empty() { 0.0 } else { mem_temps.iter().sum::<f64>() / mem_temps.len() as f64 };
            let ssd_avg = if ssd_temps.is_empty() { 0.0 } else { ssd_temps.iter().sum::<f64>() / ssd_temps.len() as f64 };
            let bat_avg = if bat_temps.is_empty() { 0.0 } else { bat_temps.iter().sum::<f64>() / bat_temps.len() as f64 };
            
            // System power from SMC (total system power)
            let pstr_key = string_to_key("PSTR");
            let sys_power = smc.read_key::<f32>(pstr_key).unwrap_or(0.0);
            
            // CPU/GPU/ANE power + tasks from powermetrics (requires NOPASSWD setup)
            // This matches the data shown in kim_dev_tool.sh display mode
            let pm_output = std::process::Command::new("sudo")
                .args(["powermetrics", "-n", "1", "-i", "100", "--samplers", "cpu_power,tasks"])
                .output()
                .ok()
                .and_then(|o| String::from_utf8(o.stdout).ok())
                .unwrap_or_default();
            
            // Parse CPU Power (in mW)
            let cpu_power_mw: i32 = pm_output.lines()
                .find(|line| line.contains("CPU Power:"))
                .and_then(|line| {
                    line.split_whitespace()
                        .find(|s| s.parse::<f64>().is_ok())
                        .and_then(|s| s.parse::<f64>().ok())
                })
                .map(|v| v as i32)  // Already in mW
                .unwrap_or(0);
            
            // Parse GPU Power (in mW)
            let gpu_power_mw: i32 = pm_output.lines()
                .find(|line| line.contains("GPU Power:"))
                .and_then(|line| {
                    line.split_whitespace()
                        .find(|s| s.parse::<f64>().is_ok())
                        .and_then(|s| s.parse::<f64>().ok())
                })
                .map(|v| v as i32)  // Already in mW
                .unwrap_or(0);
            
            // Parse ANE Power (in mW)
            let ane_power_mw: i32 = pm_output.lines()
                .find(|line| line.contains("ANE Power:"))
                .and_then(|line| {
                    line.split_whitespace()
                        .find(|s| s.parse::<f64>().is_ok())
                        .and_then(|s| s.parse::<f64>().ok())
                })
                .map(|v| v as i32)  // Already in mW
                .unwrap_or(0);
            
            // Battery info via pmset
            let battery_output = std::process::Command::new("pmset")
                .args(["-g", "batt"])
                .output()
                .ok()
                .and_then(|o| String::from_utf8(o.stdout).ok())
                .unwrap_or_default();
            
            let battery_pct: i32 = battery_output
                .split('%')
                .next()
                .and_then(|s| s.split_whitespace().last())
                .and_then(|s| s.parse().ok())
                .unwrap_or(0);
            
            let charging = battery_output.contains("; charging;") || 
                          (battery_output.contains("AC Power") && !battery_output.contains("discharging"));
            
            // Memory info via vm_stat
            let vm_output = std::process::Command::new("vm_stat")
                .output()
                .ok()
                .and_then(|o| String::from_utf8(o.stdout).ok())
                .unwrap_or_default();
            
            let page_size: u64 = 16384; // Apple Silicon uses 16KB pages
            let mut free_pages: u64 = 0;
            let mut inactive_pages: u64 = 0;
            let mut speculative_pages: u64 = 0;
            
            for line in vm_output.lines() {
                if line.starts_with("Pages free:") {
                    free_pages = line.split(':').nth(1)
                        .and_then(|s| s.trim().trim_end_matches('.').parse().ok())
                        .unwrap_or(0);
                } else if line.starts_with("Pages inactive:") {
                    inactive_pages = line.split(':').nth(1)
                        .and_then(|s| s.trim().trim_end_matches('.').parse().ok())
                        .unwrap_or(0);
                } else if line.starts_with("Pages speculative:") {
                    speculative_pages = line.split(':').nth(1)
                        .and_then(|s| s.trim().trim_end_matches('.').parse().ok())
                        .unwrap_or(0);
                }
            }
            
            let free_bytes = (free_pages + inactive_pages + speculative_pages) * page_size;
            let total_bytes: u64 = 16 * 1024 * 1024 * 1024; // Assume 16GB, could use sysctl
            let mem_free_pct = ((free_bytes as f64 / total_bytes as f64) * 100.0) as i32;
            
            // Get battery capacity dynamically (works for all Mac models)
            let ioreg_output = std::process::Command::new("ioreg")
                .args(["-r", "-c", "AppleSmartBattery"])
                .output()
                .ok()
                .and_then(|o| String::from_utf8(o.stdout).ok())
                .unwrap_or_default();
            
            let battery_mah: f32 = ioreg_output.lines()
                .find(|line| line.contains("\"DesignCapacity\""))
                .and_then(|line| {
                    line.split('=').nth(1)
                        .and_then(|s| s.trim().parse().ok())
                })
                .unwrap_or(4500.0);
            
            // Convert mAh to Wh using nominal voltage 11.4V (3-cell Li-ion)
            let battery_wh = battery_mah * 11.4 / 1000.0;
            
            // Efficiency @100%: hours = battery_wh / power_w
            let efficiency = if sys_power > 0.1 { battery_wh / sys_power } else { 99.0 };
            
            // Parse wakeups and top processes from powermetrics tasks output
            let mut total_wakeups: f64 = 0.0;
            let mut processes: Vec<(String, f64, f64)> = Vec::new(); // (name, cpu_ms, wakeups)
            let mut in_tasks = false;
            
            for line in pm_output.lines() {
                if line.starts_with("Name") {
                    in_tasks = true;
                    continue;
                }
                if line.starts_with("ALL_TASKS") || line.starts_with("CPU Power") {
                    break;
                }
                if in_tasks && !line.trim().is_empty() {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 8 {
                        // Check if second field is a PID (numeric)
                        if parts[1].parse::<i32>().is_ok() {
                            let name = parts[0].to_string();
                            let cpu_ms: f64 = parts[2].parse().unwrap_or(0.0);
                            let wakeups: f64 = parts[6].parse().unwrap_or(0.0);
                            total_wakeups += wakeups;
                            
                            // Skip system processes for top list
                            if !["kernel_task", "powerd", "powermetrics", "launchd"].contains(&parts[0]) {
                                processes.push((name, cpu_ms, wakeups));
                            }
                        }
                    }
                }
            }
            
            // Sort by CPU time and take top 5
            processes.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
            let top5: Vec<_> = processes.iter().take(5).collect();
            
            // Build top processes JSON array
            let top_json: String = top5.iter()
                .map(|(name, cpu, wakeups)| {
                    format!("{{\"name\":\"{}\",\"cpu_ms\":{:.1},\"wakeups\":{:.1}}}", name, cpu, wakeups)
                })
                .collect::<Vec<_>>()
                .join(",");
            
            // Find "silent killers" - processes with high wakeups (>50/s) but not in top CPU
            let high_wakeup_procs: Vec<_> = processes.iter()
                .filter(|(_, _, wakeups)| *wakeups > 50.0)
                .take(5)
                .collect();
            
            let high_wakeups_json: String = high_wakeup_procs.iter()
                .map(|(name, cpu, wakeups)| {
                    format!("{{\"name\":\"{}\",\"cpu_ms\":{:.1},\"wakeups\":{:.1}}}", name, cpu, wakeups)
                })
                .collect::<Vec<_>>()
                .join(",");
            
            println!("{{\"cpu_temp\":{:.1},\"gpu_temp\":{:.1},\"mem_temp\":{:.1},\"ssd_temp\":{:.1},\"bat_temp\":{:.1},\"power_w\":{:.2},\"cpu_mw\":{},\"gpu_mw\":{},\"ane_mw\":{},\"battery_pct\":{},\"charging\":{},\"mem_free_pct\":{},\"efficiency_hrs\":{:.1},\"wakeups_per_sec\":{:.0},\"top_cpu\":[{}],\"high_wakeups\":[{}]}}",
                cpu_avg, gpu_avg, mem_avg, ssd_avg, bat_avg, sys_power, cpu_power_mw, gpu_power_mw, ane_power_mw, battery_pct, charging, mem_free_pct, efficiency, total_wakeups, top_json, high_wakeups_json);
        }
        
        "stream" => {
            // STREAM MODE: Low-Observer Effect JSON Stream
            // - Updates Power/Temps every 1s (Cheap SMC call)
            // - Updates Process/Wakeups every 5s (Expensive powermetrics call)
            // - Prints 1 JSON line per second for external tools to consume
            
            let pstr_key = string_to_key("PSTR");
            
            // 1. One-time Setup: Battery Capacity
            let ioreg_output = std::process::Command::new("ioreg")
                .args(["-r", "-c", "AppleSmartBattery"])
                .output()
                .ok()
                .and_then(|o| String::from_utf8(o.stdout).ok())
                .unwrap_or_default();
            
            let battery_mah: f32 = ioreg_output.lines()
                .find(|line| line.contains("\"DesignCapacity\""))
                .and_then(|line| {
                    line.split('=').nth(1)
                        .and_then(|s| s.trim().parse().ok())
                })
                .unwrap_or(4500.0);
            let battery_wh = battery_mah * 11.4 / 1000.0;
            
            // Cache for the heavy "powermetrics" data
            let mut cached_cpu_mw = 0;
            let mut cached_gpu_mw = 0;
            let mut cached_ane_mw = 0;
            let mut cached_total_wakeups = 0.0;
            let mut cached_top_json = String::from("[]");
            let mut cached_high_wakeups_json = String::from("[]");
            
            let mut cycle_count = 0;

            loop {
                cycle_count += 1;
                
                // --- FAST METRICS (SMC) ---
                // Always fresh, takes <10ms
                
                // Power
                let sys_power = smc.read_key::<f32>(pstr_key).unwrap_or(0.0);
                
                // Temps
                let mut cpu_temps: Vec<f64> = Vec::new();
                let mut gpu_temps: Vec<f64> = Vec::new();
                let mut mem_temps: Vec<f64> = Vec::new();
                let mut ssd_temps: Vec<f64> = Vec::new();
                let mut bat_temps: Vec<f64> = Vec::new();
                
                for key in &keys {
                    let key_str = key_to_string(*key);
                    if key_str.starts_with('T') {
                        if let Ok(temp) = smc.temperature(*key) {
                            if temp > 0.0 && temp < 150.0 {
                                if key_str.starts_with("Tp") || key_str.starts_with("Te") || key_str.starts_with("Tc") {
                                    cpu_temps.push(temp);
                                } else if key_str.starts_with("Tg") {
                                    gpu_temps.push(temp);
                                } else if key_str.starts_with("TM") || key_str.starts_with("Tm") {
                                    mem_temps.push(temp);
                                } else if key_str.starts_with("TS") || key_str == "TSCD" {
                                    ssd_temps.push(temp);
                                } else if key_str.starts_with("TB") {
                                    bat_temps.push(temp);
                                }
                            }
                        }
                    }
                }
                
                let cpu_avg = if cpu_temps.is_empty() { 0.0 } else { cpu_temps.iter().sum::<f64>() / cpu_temps.len() as f64 };
                let gpu_avg = if gpu_temps.is_empty() { 0.0 } else { gpu_temps.iter().sum::<f64>() / gpu_temps.len() as f64 };
                let mem_avg = if mem_temps.is_empty() { 0.0 } else { mem_temps.iter().sum::<f64>() / mem_temps.len() as f64 };
                let ssd_avg = if ssd_temps.is_empty() { 0.0 } else { ssd_temps.iter().sum::<f64>() / ssd_temps.len() as f64 };
                let bat_avg = if bat_temps.is_empty() { 0.0 } else { bat_temps.iter().sum::<f64>() / bat_temps.len() as f64 };
                
                // Battery % (via pmset, fast enough)
                let battery_output = std::process::Command::new("pmset")
                    .args(["-g", "batt"])
                    .output()
                    .ok()
                    .and_then(|o| String::from_utf8(o.stdout).ok())
                    .unwrap_or_default();
                
                let battery_pct: i32 = battery_output
                    .split('%')
                    .next()
                    .and_then(|s| s.split_whitespace().last())
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0);
                
                let charging = battery_output.contains("; charging;") || 
                              (battery_output.contains("AC Power") && !battery_output.contains("discharging"));

                // Memory (via vm_stat, fast enough)
                let vm_output = std::process::Command::new("vm_stat")
                    .output()
                    .ok()
                    .and_then(|o| String::from_utf8(o.stdout).ok())
                    .unwrap_or_default();
                let page_size: u64 = 16384;
                let mut free_pages: u64 = 0;
                let mut inactive_pages: u64 = 0;
                let mut speculative_pages: u64 = 0;
                for line in vm_output.lines() {
                    if line.starts_with("Pages free:") {
                        free_pages = line.split(':').nth(1).and_then(|s| s.trim().trim_end_matches('.').parse().ok()).unwrap_or(0);
                    } else if line.starts_with("Pages inactive:") {
                        inactive_pages = line.split(':').nth(1).and_then(|s| s.trim().trim_end_matches('.').parse().ok()).unwrap_or(0);
                    } else if line.starts_with("Pages speculative:") {
                        speculative_pages = line.split(':').nth(1).and_then(|s| s.trim().trim_end_matches('.').parse().ok()).unwrap_or(0);
                    }
                }
                let free_bytes = (free_pages + inactive_pages + speculative_pages) * page_size;
                let total_bytes: u64 = 16 * 1024 * 1024 * 1024; // Assume 16GB
                let mem_free_pct = ((free_bytes as f64 / total_bytes as f64) * 100.0) as i32;
                
                // Efficiency Calc
                let efficiency = if sys_power > 0.1 { battery_wh / sys_power } else { 99.0 };

                // --- SLOW METRICS (Powermetrics) ---
                // Only run every 5th cycle (5 seconds)
                // This reduces observer effect by 80%
                if cycle_count % 5 == 1 { // Run on 1, 6, 11...
                     let pm_output = std::process::Command::new("sudo")
                        .args(["powermetrics", "-n", "1", "-i", "100", "--samplers", "cpu_power,tasks"])
                        .output()
                        .ok()
                        .and_then(|o| String::from_utf8(o.stdout).ok())
                        .unwrap_or_default();
                    
                    cached_cpu_mw = pm_output.lines().find(|l| l.contains("CPU Power:")).and_then(|l| l.split_whitespace().find(|s| s.parse::<f64>().is_ok()).and_then(|s| s.parse::<f64>().ok())).map(|v| v as i32).unwrap_or(0);
                    cached_gpu_mw = pm_output.lines().find(|l| l.contains("GPU Power:")).and_then(|l| l.split_whitespace().find(|s| s.parse::<f64>().is_ok()).and_then(|s| s.parse::<f64>().ok())).map(|v| v as i32).unwrap_or(0);
                    cached_ane_mw = pm_output.lines().find(|l| l.contains("ANE Power:")).and_then(|l| l.split_whitespace().find(|s| s.parse::<f64>().is_ok()).and_then(|s| s.parse::<f64>().ok())).map(|v| v as i32).unwrap_or(0);
                    
                    let mut total_wakeups: f64 = 0.0;
                    let mut processes: Vec<(String, f64, f64)> = Vec::new();
                    let mut in_tasks = false;
                    for line in pm_output.lines() {
                        if line.starts_with("Name") { in_tasks = true; continue; }
                        if line.starts_with("ALL_TASKS") || line.starts_with("CPU Power") { break; }
                        if in_tasks && !line.trim().is_empty() {
                            let parts: Vec<&str> = line.split_whitespace().collect();
                            if parts.len() >= 8 && parts[1].parse::<i32>().is_ok() {
                                let name = parts[0].to_string();
                                let cpu_ms: f64 = parts[2].parse().unwrap_or(0.0);
                                let wakeups: f64 = parts[6].parse().unwrap_or(0.0);
                                total_wakeups += wakeups;
                                if !["kernel_task", "powerd", "powermetrics", "launchd"].contains(&parts[0]) {
                                    processes.push((name, cpu_ms, wakeups));
                                }
                            }
                        }
                    }
                    cached_total_wakeups = total_wakeups;
                    processes.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
                    cached_top_json = processes.iter().take(5).map(|(n,c,w)| format!("{{\"name\":\"{}\",\"cpu_ms\":{:.1},\"wakeups\":{:.1}}}", n, c, w)).collect::<Vec<_>>().join(",");
                    cached_high_wakeups_json = processes.iter().filter(|(_,_,w)| *w > 50.0).take(5).map(|(n,c,w)| format!("{{\"name\":\"{}\",\"cpu_ms\":{:.1},\"wakeups\":{:.1}}}", n, c, w)).collect::<Vec<_>>().join(",");
                }

                // PRINT JSON LINE
                println!("{{\"cpu_temp\":{:.1},\"gpu_temp\":{:.1},\"mem_temp\":{:.1},\"ssd_temp\":{:.1},\"bat_temp\":{:.1},\"power_w\":{:.2},\"cpu_mw\":{},\"gpu_mw\":{},\"ane_mw\":{},\"battery_pct\":{},\"charging\":{},\"mem_free_pct\":{},\"efficiency_hrs\":{:.1},\"wakeups_per_sec\":{:.0},\"top_cpu\":[{}],\"high_wakeups\":[{}]}}",
                    cpu_avg, gpu_avg, mem_avg, ssd_avg, bat_avg, sys_power, cached_cpu_mw, cached_gpu_mw, cached_ane_mw, battery_pct, charging, mem_free_pct, efficiency, cached_total_wakeups, cached_top_json, cached_high_wakeups_json);
                
                use std::io::Write;
                std::io::stdout().flush().unwrap();
                
                std::thread::sleep(std::time::Duration::from_millis(1000));
            }
        }
        
        _ => {
            println!("Usage: kim_temp [cpu|gpu|power|power-all|all|json|monitor]");
        }
    }
}
