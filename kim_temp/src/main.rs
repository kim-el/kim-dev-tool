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

    // Common Power Keys
    let pstr_key = string_to_key("PSTR"); // System Total (Logic)
    let ppbr_key = string_to_key("PPBR"); // Battery Rail (Physical Total)
    let phps_key = string_to_key("PHPS"); // Package Total (SoC + some extras)
    let phpm_key = string_to_key("PHPM"); // Memory
    let pp0b_key = string_to_key("PP0b"); // CPU
    let pp7b_key = string_to_key("PP7b"); // GPU

    match mode {
        "cpu" => {
            if let Ok(keys) = smc.keys() {
                let mut temps: Vec<f64> = Vec::new();
                for key in &keys {
                    let key_str = key_to_string(*key);
                    if key_str.starts_with("Tp") || key_str.starts_with("Te") || 
                       key_str.starts_with("Tc") || key_str.starts_with("TC") {
                        if let Ok(temp) = smc.temperature(*key) {
                            if temp > 0.0 && temp < 150.0 { temps.push(temp); }
                        }
                    }
                }
                if !temps.is_empty() {
                    let avg = temps.iter().sum::<f64>() / temps.len() as f64;
                    println!("{:.1}", avg);
                } else { println!("N/A"); }
            } else { println!("N/A"); }
        }
        
        "gpu" => {
            if let Ok(keys) = smc.keys() {
                let mut temps: Vec<f64> = Vec::new();
                for key in &keys {
                    let key_str = key_to_string(*key);
                    if key_str.starts_with("Tg") || key_str.starts_with("TG") {
                        if let Ok(temp) = smc.temperature(*key) {
                            if temp > 0.0 && temp < 150.0 { temps.push(temp); }
                        }
                    }
                }
                if !temps.is_empty() {
                    let avg = temps.iter().sum::<f64>() / temps.len() as f64;
                    println!("{:.1}", avg);
                } else { println!("N/A"); }
            } else { println!("N/A"); }
        }
        
        "power" => {
            if let Ok(power) = smc.read_key::<f32>(pstr_key) {
                println!("{:.2}", power);
            } else { println!("N/A"); }
        }
        
        "json" | "stream" => {
            let ioreg_batt = std::process::Command::new("ioreg").args(["-r", "-c", "AppleSmartBattery"]).output().ok().and_then(|o| String::from_utf8(o.stdout).ok()).unwrap_or_default();
            let battery_mah: f32 = ioreg_batt.lines().find(|l| l.contains("\"DesignCapacity\"")).and_then(|l| l.split('=').nth(1).and_then(|s| s.trim().parse().ok())).unwrap_or(4500.0);
            let battery_wh = battery_mah * 11.4 / 1000.0;
            
            let total_bytes: u64 = std::process::Command::new("sysctl").args(["-n", "hw.memsize"]).output().ok().and_then(|o| String::from_utf8(o.stdout).ok()).and_then(|s| s.trim().parse().ok()).unwrap_or(16 * 1024 * 1024 * 1024);
            let page_size: u64 = std::process::Command::new("pagesize").output().ok().and_then(|o| String::from_utf8(o.stdout).ok()).and_then(|s| s.trim().parse().ok()).unwrap_or(16384);

            let keys = smc.keys().unwrap_or_default();
            
            loop {
                let sys_power = smc.read_key::<f32>(pstr_key).unwrap_or(0.0);
                let bat_power = smc.read_key::<f32>(ppbr_key).unwrap_or(0.0);
                let phps = smc.read_key::<f32>(phps_key).unwrap_or(0.0);
                let mem_power = smc.read_key::<f32>(phpm_key).unwrap_or(0.0);
                let cpu_smc = smc.read_key::<f32>(pp0b_key).unwrap_or(0.0);
                let gpu_smc = smc.read_key::<f32>(pp7b_key).unwrap_or(0.0);
                
                let _display_w_placeholder = (phps - cpu_smc - gpu_smc - mem_power).max(0.0);
                
                let mut cpu_temps = Vec::new(); let mut gpu_temps = Vec::new(); let mut mem_temps = Vec::new(); let mut ssd_temps = Vec::new(); let mut bat_temps = Vec::new();
                for key in &keys {
                    let ks = key_to_string(*key);
                    if let Ok(t) = smc.temperature(*key) {
                        if t > 0.0 && t < 150.0 {
                            if ks.starts_with("Tp") || ks.starts_with("Te") || ks.starts_with("Tc") { cpu_temps.push(t); }
                            else if ks.starts_with("Tg") { gpu_temps.push(t); }
                            else if ks.starts_with("TM") { mem_temps.push(t); }
                            else if ks.starts_with("TS") { ssd_temps.push(t); }
                            else if ks.starts_with("TB") { bat_temps.push(t); }
                        }
                    }
                }
                
                let cpu_avg = if cpu_temps.is_empty() { 0.0 } else { cpu_temps.iter().sum::<f64>() / cpu_temps.len() as f64 };
                let gpu_avg = if gpu_temps.is_empty() { 0.0 } else { gpu_temps.iter().sum::<f64>() / gpu_temps.len() as f64 };
                let mem_avg = if mem_temps.is_empty() { 0.0 } else { mem_temps.iter().sum::<f64>() / mem_temps.len() as f64 };
                let ssd_avg = if ssd_temps.is_empty() { 0.0 } else { ssd_temps.iter().sum::<f64>() / ssd_temps.len() as f64 };
                let bat_avg = if bat_temps.is_empty() { 0.0 } else { bat_temps.iter().sum::<f64>() / bat_temps.len() as f64 };

                let battery_output = std::process::Command::new("pmset").args(["-g", "batt"]).output().ok().and_then(|o| String::from_utf8(o.stdout).ok()).unwrap_or_default();
                let battery_pct: i32 = battery_output.split('%').next().and_then(|s| s.split_whitespace().last()).and_then(|s| s.parse().ok()).unwrap_or(0);
                let charging = battery_output.contains("; charging;") || (battery_output.contains("AC Power") && !battery_output.contains("discharging"));

                let vm_output = std::process::Command::new("vm_stat").output().ok().and_then(|o| String::from_utf8(o.stdout).ok()).unwrap_or_default();
                let mut free_pages: u64 = 0; let mut inactive_pages: u64 = 0; let mut speculative_pages: u64 = 0;
                for line in vm_output.lines() {
                    if line.starts_with("Pages free:") { free_pages = line.split(':').nth(1).and_then(|s| s.trim().trim_end_matches('.').parse().ok()).unwrap_or(0); }
                    else if line.starts_with("Pages inactive:") { inactive_pages = line.split(':').nth(1).and_then(|s| s.trim().trim_end_matches('.').parse().ok()).unwrap_or(0); }
                    else if line.starts_with("Pages speculative:") { speculative_pages = line.split(':').nth(1).and_then(|s| s.trim().trim_end_matches('.').parse().ok()).unwrap_or(0); }
                }
                let free_bytes = (free_pages + inactive_pages + speculative_pages) * page_size;
                let mem_free_pct = ((free_bytes as f64 / total_bytes as f64) * 100.0) as i32;
                let efficiency = if sys_power > 0.1 { battery_wh / sys_power } else { 99.0 };

                let pm_output = std::process::Command::new("sudo")
                    .args(["powermetrics", "-n", "1", "-i", "100", "--samplers", "cpu_power,tasks"])
                    .output().ok().and_then(|o| String::from_utf8(o.stdout).ok()).unwrap_or_default();
                
                let cpu_mw: i32 = pm_output.lines().find(|l| l.contains("CPU Power:")).and_then(|l| l.split_whitespace().find(|s| s.parse::<f64>().is_ok()).and_then(|s| s.parse::<f64>().ok())).map(|v| v as i32).unwrap_or(0);
                let gpu_mw: i32 = pm_output.lines().find(|l| l.contains("GPU Power:")).and_then(|l| l.split_whitespace().find(|s| s.parse::<f64>().is_ok()).and_then(|s| s.parse::<f64>().ok())).map(|v| v as i32).unwrap_or(0);
                let ane_mw: i32 = pm_output.lines().find(|l| l.contains("ANE Power:")).and_then(|l| l.split_whitespace().find(|s| s.parse::<f64>().is_ok()).and_then(|s| s.parse::<f64>().ok())).map(|v| v as i32).unwrap_or(0);

                // Formula: Display = System Total (PSTR) - Components (CPU+GPU+ANE+Memory)
                // Note: PSTR is from SMC (avg over time), Components are from Powermetrics (instant).
                // We use max(0) to handle sampling sync noise.
                let components_w = (cpu_mw as f32 + gpu_mw as f32 + ane_mw as f32) / 1000.0 + mem_power;
                let display_w = (sys_power - components_w).max(0.0);

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
                processes.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
                let top_json = processes.iter().take(5).map(|(n,c,w)| format!("{{\"name\":\"{}\",\"cpu_ms\":{:.1},\"wakeups\":{:.1}}}", n, c, w)).collect::<Vec<_>>().join(",");
                let high_wakeups_json = processes.iter().filter(|(_,_,w)| *w > 50.0).take(5).map(|(n,c,w)| format!("{{\"name\":\"{}\",\"cpu_ms\":{:.1},\"wakeups\":{:.1}}}", n, c, w)).collect::<Vec<_>>().join(",");

                println!("{{\"cpu_temp\":{:.1},\"gpu_temp\":{:.1},\"mem_temp\":{:.1},\"ssd_temp\":{:.1},\"bat_temp\":{:.1},\"power_w\":{:.2},\"bat_power_w\":{:.2},\"mem_power_w\":{:.2},\"display_w\":{:.2},\"cpu_mw\":{},\"gpu_mw\":{},\"ane_mw\":{},\"battery_pct\":{},\"charging\":{},\"mem_free_pct\":{},\"efficiency_hrs\":{:.1},\"wakeups_per_sec\":{:.0},\"top_cpu\":[{}],\"high_wakeups\":[{}]}}",
                    cpu_avg, gpu_avg, mem_avg, ssd_avg, bat_avg, sys_power, bat_power, mem_power, display_w, cpu_mw, gpu_mw, ane_mw, battery_pct, charging, mem_free_pct, efficiency, total_wakeups, top_json, high_wakeups_json);
                
                if mode == "json" { break; }
                use std::io::Write;
                std::io::stdout().flush().unwrap();
                std::thread::sleep(std::time::Duration::from_millis(1000));
            }
        }
        
        "monitor" => {
            let ioreg_batt = std::process::Command::new("ioreg").args(["-r", "-c", "AppleSmartBattery"]).output().ok().and_then(|o| String::from_utf8(o.stdout).ok()).unwrap_or_default();
            let battery_mah: f32 = ioreg_batt.lines().find(|l| l.contains("\"DesignCapacity\"")).and_then(|l| l.split('=').nth(1).and_then(|s| s.trim().parse().ok())).unwrap_or(4500.0);
            let battery_wh = battery_mah * 11.4 / 1000.0;
            let keys = smc.keys().unwrap_or_default();

            loop {
                let sys_power = smc.read_key::<f32>(pstr_key).unwrap_or(0.0);
                let bat_power = smc.read_key::<f32>(ppbr_key).unwrap_or(0.0);
                let mem_power = smc.read_key::<f32>(phpm_key).unwrap_or(0.0);
                
                // Need powermetrics for CPU/GPU power
                let pm_output = std::process::Command::new("sudo")
                    .args(["powermetrics", "-n", "1", "-i", "50", "--samplers", "cpu_power"])
                    .output().ok().and_then(|o| String::from_utf8(o.stdout).ok()).unwrap_or_default();
                
                let cpu_mw: f32 = pm_output.lines().find(|l| l.contains("CPU Power:")).and_then(|l| l.split_whitespace().find(|s| s.parse::<f64>().is_ok()).and_then(|s| s.parse::<f32>().ok())).unwrap_or(0.0);
                let gpu_mw: f32 = pm_output.lines().find(|l| l.contains("GPU Power:")).and_then(|l| l.split_whitespace().find(|s| s.parse::<f64>().is_ok()).and_then(|s| s.parse::<f32>().ok())).unwrap_or(0.0);
                let ane_mw: f32 = pm_output.lines().find(|l| l.contains("ANE Power:")).and_then(|l| l.split_whitespace().find(|s| s.parse::<f64>().is_ok()).and_then(|s| s.parse::<f32>().ok())).unwrap_or(0.0);

                let display_w = (sys_power - (cpu_mw + gpu_mw + ane_mw)/1000.0 - mem_power).max(0.0);
                
                let mut cpu_temps = Vec::new();
                for key in &keys {
                     let ks = key_to_string(*key);
                     if ks.starts_with("Tp") || ks.starts_with("Te") {
                         if let Ok(t) = smc.temperature(*key) { cpu_temps.push(t); }
                     }
                }
                let cpu_temp = if cpu_temps.is_empty() { 0.0 } else { cpu_temps.iter().sum::<f64>() / cpu_temps.len() as f64 };
                let est_hrs = if bat_power > 0.5 { battery_wh / bat_power } else { 99.9 };
                
                print!("\r⚡ Sys: {:.2}W | Disp: {:.2}W | Bat: {:.2}W | 🔋 Est: {:.1}h | 🌡️  {:.1}°C      ", sys_power, display_w, bat_power, est_hrs, cpu_temp);
                use std::io::Write;
                std::io::stdout().flush().unwrap();
                std::thread::sleep(std::time::Duration::from_millis(500));
            }
        }

        "monitor-p" => {
             if let Ok(keys) = smc.keys() {
                 let p_keys: Vec<_> = keys.iter().filter(|k| key_to_string(**k).starts_with('P')).map(|k| (key_to_string(*k), *k)).collect();
                 loop {
                     print!("\x1B[2J\x1B[H"); // Clear screen
                     for (name, key) in &p_keys {
                         if let Ok(val) = smc.read_key::<f32>(*key) { println!("{}: {:.4}", name, val); }
                     }
                     use std::io::Write;
                     std::io::stdout().flush().unwrap();
                     std::thread::sleep(std::time::Duration::from_millis(1000));
                 }
             }
        }

        "trigger" => {
            // Default threshold: 500mW
            let threshold_mw = args.get(2).and_then(|s| s.parse::<f32>().ok()).unwrap_or(500.0);
            // Default interval: 100ms (10Hz)
            let interval_ms = args.get(3).and_then(|s| s.parse::<u64>().ok()).unwrap_or(100);
            
            let pstr_key = string_to_key("PSTR");
            let phpm_key = string_to_key("PHPM");
            let pp0b_key = string_to_key("PP0b");
            let pp7b_key = string_to_key("PP7b");

            // Use PSTR (Total System) for maximum sensitivity to backlight + pixels
            let get_disp_mw = |smc: &SMC| -> f32 {
                let total = smc.read_key::<f32>(pstr_key).unwrap_or(0.0);
                let mem = smc.read_key::<f32>(phpm_key).unwrap_or(0.0);
                let cpu = smc.read_key::<f32>(pp0b_key).unwrap_or(0.0);
                let gpu = smc.read_key::<f32>(pp7b_key).unwrap_or(0.0);
                ((total - cpu - gpu - mem).max(0.0)) * 1000.0
            };

            let mut last_stable = get_disp_mw(&smc);
            
            // Smoothing: Exponential Moving Average (EMA)
            let alpha = 0.2; 
            let mut smoothed_val = last_stable;

            loop {
                let raw_current = get_disp_mw(&smc);
                smoothed_val = alpha * raw_current + (1.0 - alpha) * smoothed_val;
                
                let delta = (smoothed_val - last_stable).abs();

                if delta > threshold_mw {
                    println!("{{\"event\":\"content_change\",\"delta_mw\":{:.0},\"current_mw\":{:.0}}}", delta, smoothed_val);
                    last_stable = smoothed_val;
                    std::thread::sleep(std::time::Duration::from_millis(1000)); 
                }
                
                use std::io::Write;
                std::io::stdout().flush().unwrap();
                std::thread::sleep(std::time::Duration::from_millis(interval_ms));
            }
        }

        _ => { println!("Usage: kim_temp [cpu|gpu|power|json|stream|monitor|monitor-p|trigger <threshold_mw> <interval_ms>]"); }
    }
}