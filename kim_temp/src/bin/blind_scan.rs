use smc::SMC;
use std::{thread, time};

fn key_to_string(key: four_char_code::FourCharCode) -> String {
    let bytes = key.0.to_be_bytes();
    String::from_utf8_lossy(&bytes).to_string()
}

fn main() {
    let smc = SMC::new().expect("SMC init failed");
    let keys = smc.keys().unwrap_or_default();
    
    // STRICT FILTER: Only P, V, I keys
    let candidates: Vec<_> = keys.iter().filter(|k| {
        let s = key_to_string(**k);
        s.starts_with('P') || s.starts_with('V') || s.starts_with('I')
    }).collect();

    println!("Scanning {} P/V/I Keys...", candidates.len());
    println!("1. Establishing Baseline (Set Brightness to 0%)...");

    let mut baseline = std::collections::HashMap::new();
    
    for key in &candidates {
        // We catch the panic? No. We hope most PVI keys are floats.
        // We know 'si8 ' caused a crash.
        // Let's exclude short keys?
        if let Ok(val) = smc.read_key::<f32>(**key) {
            baseline.insert(*key, val);
        }
    }
    
    println!("Baseline Set. Please SET BRIGHTNESS TO 100%!");
    thread::sleep(time::Duration::from_secs(5));
    
    println!("Scanning...");
    for key in &candidates {
        if let Ok(val) = smc.read_key::<f32>(**key) {
            if let Some(base) = baseline.get(key) {
                let delta = val - base;
                // If it's Power (mW), look for > 1000. If Voltage (V), look for > 1.0?
                // Backlight is ~5 Watts (5000 mW).
                if delta.abs() > 500.0 {
                    println!("MATCH: {} changed by {:.2} ({} -> {})", 
                        key_to_string(**key), delta, base, val);
                }
            }
        }
    }
    println!("Scan Complete.");
}
