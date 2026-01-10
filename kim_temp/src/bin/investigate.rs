use smc::SMC;
use std::{thread, time};

fn key_to_string(key: four_char_code::FourCharCode) -> String {
    let bytes = key.0.to_be_bytes();
    String::from_utf8_lossy(&bytes).to_string()
}

fn main() {
    let smc = SMC::new().expect("SMC init failed");
    let keys = smc.keys().unwrap_or_default();
    
    // Filter for "I" (Current) keys related to Backlight/Display
    // IB = Current Battery/Backlight? ID = Current DC?
    let candidates: Vec<_> = keys.iter().filter(|k| {
        let s = key_to_string(**k);
        // "IB" often means Current Battery or Backlight
        // "ID" often means Current DC-In
        // "VP" often means Voltage Power
        s.starts_with("IB") || s.starts_with("VP") || s.starts_with("VD")
    }).collect();

    println!("Scanning {} Candidate Keys (IB/VP/VD)...", candidates.len());
    println!("1. Establishing Baseline (Set Brightness to 0%)...");

    let mut baseline = std::collections::HashMap::new();
    
    for _ in 0..10 {
        for key in &candidates {
            // Attempt to read as f32 (most common for sensors)
            if let Ok(val) = smc.read_key::<f32>(**key) {
                *baseline.entry(*key).or_insert(0.0) += val;
            }
        }
        thread::sleep(time::Duration::from_millis(100));
    }
    for val in baseline.values_mut() { *val /= 10.0; }

    println!("Baseline Set. Please SET BRIGHTNESS TO 100%!");
    println!("Scanning (60 samples)... \n");

    for i in 1..=60 {
        let mut movers = Vec::new();
        for key in &candidates {
            if let Ok(val) = smc.read_key::<f32>(**key) {
                let base = *baseline.get(key).unwrap_or(&0.0);
                let delta = val - base;

                if delta.abs() > 0.1 {
                    movers.push((key_to_string(**key), delta));
                }
            }
        }
        
        if !movers.is_empty() {
            movers.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));
            print!("\n[{:2}] ", i);
            for (name, d) in movers.iter().take(4) {
                print!("{} {:+.2} | ", name, d);
            }
        } else {
            print!(".");
        }
        
        use std::io::Write;
        std::io::stdout().flush().unwrap();
        thread::sleep(time::Duration::from_millis(500));
    }
    println!("\nScan complete.");
}