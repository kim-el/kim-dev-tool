use smc::SMC;
use std::{thread, time};

fn key_to_string(key: four_char_code::FourCharCode) -> String {
    let bytes = key.0.to_be_bytes();
    String::from_utf8_lossy(&bytes).to_string()
}

fn main() {
    let smc = SMC::new().expect("SMC init failed");
    let keys = smc.keys().unwrap_or_default();
    let p_keys: Vec<_> = keys.iter().filter(|k| key_to_string(**k).starts_with('P')).collect();

    println!("Scanning 52 P-keys for SSD Activity...");
    println!("1. Establishing Baseline (Wait for 'GO'...)...");

    let mut baseline = std::collections::HashMap::new();
    for _ in 0..10 {
        for key in &p_keys {
            if let Ok(val) = smc.read_key::<f32>(**key) {
                *baseline.entry(*key).or_insert(0.0) += val;
            }
        }
        thread::sleep(time::Duration::from_millis(100));
    }
    for val in baseline.values_mut() { *val /= 10.0; }

    println!("Baseline Set. GO!");

    for i in 1..=60 {
        let mut movers = Vec::new();
        for key in &p_keys {
            if let Ok(val) = smc.read_key::<f32>(**key) {
                let base = *baseline.get(key).unwrap_or(&0.0);
                let delta = (val - base) * 1000.0;
                if delta.abs() > 100.0 {
                    movers.push((key_to_string(**key), delta));
                }
            }
        }
        
        movers.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        if !movers.is_empty() {
            print!("\n[{:3}] ", i);
            for (name, delta) in movers.iter().take(5) {
                print!("{} ({:+.0}mW) ", name, delta);
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
