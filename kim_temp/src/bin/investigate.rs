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
    
    // Filter for all P-keys
    let p_keys: Vec<_> = keys.iter().filter(|k| {
        key_to_string(**k).starts_with('P')
    }).collect();

    println!("Found {} P-keys. Waiting for ANE > 10mW...", p_keys.len());

    let mut samples_collected = 0;
    let start_time = std::time::Instant::now();
    
    loop {
        if samples_collected >= 10 {
            println!("\nCollected 10 samples. Exiting.");
            break;
        }

        if start_time.elapsed().as_secs() > 60 {
            println!("\nTimeout: No ANE load detected after 60 seconds. Exiting.");
            break;
        }

        // 1. Get Official Power
        let output = Command::new("sudo")
            .args(["powermetrics", "-n", "1", "-i", "100", "--samplers", "cpu_power"])
            .output()
            .expect("failed to run powermetrics");
        let stdout = String::from_utf8_lossy(&output.stdout);
        
        let pm_val = stdout.lines()
            .find(|l| l.contains("ANE Power:"))
            .and_then(|l| l.split_whitespace().find(|s| s.parse::<f64>().is_ok()))
            .and_then(|s| s.parse::<f64>().ok())
            .unwrap_or(0.0) as f32;

        if pm_val > 10.0 {
            samples_collected += 1;
            println!("\n--- SAMPLE #{} | ANE LOAD DETECTED: {:.0} mW ---", samples_collected, pm_val);
            
            // 2. Scan ALL P-keys
            for key in &p_keys {
                if let Ok(val) = smc.read_key::<f32>(**key) {
                    let mw = val * 1000.0;
                    
                    // ANE Match: +/- 30% OR within 200mW
                    let diff = (mw - pm_val).abs();
                    if diff < (pm_val * 0.3) || diff < 200.0 {
                         println!("MATCH: {} = {:.0} mW (Diff: {:.0})", key_to_string(**key), mw, diff);
                    }
                }
            }
        } else {
            print!(".");
            use std::io::Write;
            std::io::stdout().flush().unwrap();
        }
        
        // No sleep here, we want to catch the spike as fast as powermetrics runs
    }
}
