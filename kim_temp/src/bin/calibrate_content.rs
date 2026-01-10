use smc::SMC;
use std::io;
use std::process::Command;
use std::thread;
use std::time::Duration;

fn key_to_string(key: four_char_code::FourCharCode) -> String {
    let bytes = key.0.to_be_bytes();
    String::from_utf8_lossy(&bytes).to_string()
}

fn wait_for_enter(prompt: &str) {
    println!("\n{}", prompt);
    let mut input = String::new();
    io::stdin().read_line(&mut input).unwrap();
}

fn get_display_power(smc: &SMC, pp0b: four_char_code::FourCharCode, pp7b: four_char_code::FourCharCode) -> f32 {
    let pstr = smc.read_key::<f32>(four_char_code::FourCharCode(*b"PSTR")).unwrap_or(0.0);
    let mem  = smc.read_key::<f32>(four_char_code::FourCharCode(*b"PHPM")).unwrap_or(0.0);
    // Use user-provided calibrated keys if possible, otherwise defaults
    let cpu = smc.read_key::<f32>(pp0b).unwrap_or(0.0);
    let gpu = smc.read_key::<f32>(pp7b).unwrap_or(0.0);
    
    (pstr - cpu - gpu - mem).max(0.0) * 1000.0 // return in mW
}

fn get_backlight_level() -> u64 {
    let output = Command::new("sh")
        .arg("-c")
        .arg("ioreg -c IOMobileFramebuffer | grep \"IOMFBBrightnessLevel\" = | head -n 1")
        .output()
        .expect("ioreg failed");
    let s = String::from_utf8_lossy(&output.stdout);
    if let Some(val_str) = s.split('=').nth(1) {
        return val_str.trim().parse::<u64>().unwrap_or(0);
    }
    0
}

fn measure_average_mw(smc: &SMC, pp0b: four_char_code::FourCharCode, pp7b: four_char_code::FourCharCode) -> f32 {
    let mut sum = 0.0;
    let samples = 10;
    print!("Measuring...");
    for _ in 0..samples {
        sum += get_display_power(smc, pp0b, pp7b);
        print!(".");
        use std::io::Write;
        std::io::stdout().flush().unwrap();
        thread::sleep(Duration::from_millis(200));
    }
    println!(" Done.");
    sum / samples as f32
}

fn main() {
    let smc = SMC::new().expect("SMC init failed");
    
    // Hardcoded keys for M4 based on previous discovery (update if needed)
    // CPU: PZD1, GPU: PP2b (from user logs)
    // Ideally we re-run calibration logic here, but for simplicity let's ask the user or assume PZD1/PP2b for this specific session.
    // Actually, let's use the ones we saw in the logs: CPU=PZD1, GPU=PP2b (approx).
    // Better: Scan for PZD1.
    let pp0b = four_char_code::FourCharCode(*b"PZD1");
    let pp7b = four_char_code::FourCharCode(*b"PP2b");

    println!("--- Content Brightness Calibrator (M4) ---");
    println!("Using Power Keys -> CPU: PZD1, GPU: PP2b");

    // 1. Max Brightness + WHITE
    wait_for_enter("1. Set Brightness to MAXIMUM (100%).\n   Open a PURE WHITE window (e.g. empty browser tab) covering the whole screen.\n   Press Enter when ready.");
    let bl_max = get_backlight_level();
    let mw_white = measure_average_mw(&smc, pp0b, pp7b);
    println!("   -> Backlight: {}, Power: {:.0} mW", bl_max, mw_white);

    // 2. Max Brightness + BLACK
    wait_for_enter("2. Keep Brightness at MAXIMUM.\n   Open a PURE BLACK window (e.g. terminal fullscreen).\n   Press Enter when ready.");
    let mw_black = measure_average_mw(&smc, pp0b, pp7b);
    println!("   -> Backlight: {}, Power: {:.0} mW", bl_max, mw_black);
    
    // Analysis
    let dynamic_range = mw_white - mw_black;
    println!("\n--- Calibration Results ---");
    println!("Dynamic Power Range: {:.0} mW", dynamic_range);
    
    if dynamic_range < 500.0 {
        println!("WARNING: Low dynamic range detected. Is the screen actually XDR/OLED? Or did the content not change?");
    } else {
        println!("Content Signal Thresholds (at Max Brightness):");
        let step = dynamic_range / 3.0;
        let t1 = mw_black + step;
        let t2 = mw_black + step * 2.0;
        
        println!("   Signal 1 (Dark):   < {:.0} mW", t1);
        println!("   Signal 2 (Mid):    {:.0} mW - {:.0} mW", t1, t2);
        println!("   Signal 3 (Bright): > {:.0} mW", t2);
        
        // Normalize per backlight unit
        // Pixels_mW = (Current_mW - Base_mW)
        // We assume Base_mW scales with Backlight too? Or is it fixed logic?
        // Let's assume simplest model: Power = k * Backlight * Content_Whiteness
        
        let mw_per_bl_unit_white = mw_white / bl_max as f32;
        let mw_per_bl_unit_black = mw_black / bl_max as f32;
        
        println!("\nNormalized Factors (mW per Backlight Unit):");
        println!("   White Factor: {:.8}", mw_per_bl_unit_white);
        println!("   Black Factor: {:.8}", mw_per_bl_unit_black);
    }
}
