use smc::SMC;
use std::{thread, time};
use std::process::Command;

fn key_to_string(key: four_char_code::FourCharCode) -> String {
    let bytes = key.0.to_be_bytes();
    String::from_utf8_lossy(&bytes).to_string()
}

fn main() {
    let smc = SMC::new().expect("SMC init failed");
    let keys = smc.keys().unwrap_or_default();
    
    // Filter for keys starting with 'P'
    let p_keys: Vec<_> = keys.iter().filter(|k| {
        key_to_string(**k).starts_with('P')
    }).collect();

    println!("Found {} P-keys. Starting correlation scan...", p_keys.len());

    for _ in 0..5 {
        // 1. Get Official Power
        let output = Command::new("sudo")
            .args(["powermetrics", "-n", "1", "-i", "100", "--samplers", "cpu_power"])
            .output()
            .expect("failed to run powermetrics");
        let stdout = String::from_utf8_lossy(&output.stdout);
        
        let cpu_mw = stdout.lines()
            .find(|l| l.contains("CPU Power:"))
            .and_then(|l| l.split_whitespace().find(|s| s.parse::<f64>().is_ok()))
            .and_then(|s| s.parse::<f64>().ok())
            .unwrap_or(0.0) as f32;

        let gpu_mw = stdout.lines()
            .find(|l| l.contains("GPU Power:"))
            .and_then(|l| l.split_whitespace().find(|s| s.parse::<f64>().is_ok()))
            .and_then(|s| s.parse::<f64>().ok())
            .unwrap_or(0.0) as f32;

        println!("\n--- Sample ---");
        println!("OFFICIAL: CPU: {:.0} mW | GPU: {:.0} mW", cpu_mw, gpu_mw);

        // 2. Read All SMC Keys
        let mut matches = Vec::new();
        for key in &p_keys {
            if let Ok(val) = smc.read_key::<f32>(**key) {
                let mw = val * 1000.0;
                // If the value is within 20% or 100mW of CPU, mark it
                // We use a loose threshold because sampling times differ slightly
                if (mw - cpu_mw).abs() < (cpu_mw * 0.2 + 100.0) {
                     matches.push(format!("CPU MATCH? {} = {:.0} mW", key_to_string(**key), mw));
                }
                if (mw - gpu_mw).abs() < (gpu_mw * 0.2 + 50.0) {
                     matches.push(format!("GPU MATCH? {} = {:.0} mW", key_to_string(**key), mw));
                }
            }
        }
        
        for m in matches {
            println!("  -> {}", m);
        }
        
        thread::sleep(time::Duration::from_millis(2000));
    }
}