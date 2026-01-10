# Content Brightness Signal Suggestion (Apple Silicon M4)

This document provides the calibrated power thresholds to categorize screen content brightness into three signals (1, 2, 3) for recording and automation purposes.

## 1. Hardware Calibration Data (M4)
- **Brightness Driver (IORegistry):** `IOMobileFramebuffer` / `IOMFBBrightnessLevel`
  - **MIN (0%):** 131,203
  - **MAX (100%):** 20,643,762
- **Power Baseline (Total System PSTR):**
  - **Black Content (Max Brightness):** ~5,000 mW
  - **White Content (Max Brightness):** ~7,100 mW
- **Dynamic Content Range:** ~2,100 mW (at 100% brightness)

## 2. Signal Thresholds (at 100% Brightness)
Use these mW values from the `display_w` field in `kim_temp_bin`:

| Signal | Category | Display mW Range | Description |
| :--- | :--- | :--- | :--- |
| **1** | **Dark** | < 5,700 mW | Dark mode, terminal, black scenes. |
| **2** | **Medium** | 5,700 - 6,400 mW | Standard web browsing, mixed UI. |
| **3** | **Bright** | > 6,400 mW | White backgrounds, "Eye Stabbing". |

## 3. Normalization Logic (for lower brightness settings)
If the user reduces brightness, the thresholds should scale down. 
Let `B` be the current brightness level (0.0 to 1.0).
The **Adjusted Signal 3 Threshold** would be:
`Threshold_3 = Base_Power(B) + (2,100 * B * 0.66)`

## 4. Implementation Note for LLM/Automation
The `display_w` value from `check delta` is the most reliable metric as it subtracts CPU/GPU/RAM noise.
- **Trigger:** If `display_w` > 6,400 mW, record as "High Brightness Event".
- **Trigger:** If `display_w` remains < 5,200 mW, mark as "Dark/Efficient Content".

## 5. Alternative: Visual Signal Classifier (ML/Vision)
If power sensors prove too noisy, use a **Visual Approach** to detect eye-stabbing content directly from the frame buffer.

**Architecture:**
1.  **Capture:** Use `ScreenCaptureKit` (macOS 12.3+) to stream the screen.
2.  **Process:** Hardware-downscale frames to **32x32 pixels**.
3.  **Model:** Compute **Average Luminance (APL)** of the thumbnail.
    - *Optional ML:* Train a tiny classifier (Decision Tree) on color histograms to distinguish "Dark Mode UI" from "Dark Video Scenes".
4.  **Thresholds (Luminance 0.0 - 1.0):**
    - **Signal 1 (Dark):** < 0.2
    - **Signal 2 (Mid):** 0.2 - 0.7
    - **Signal 3 (Bright):** > 0.7

**Pros:** 100% accurate to content, zero noise, <1% CPU usage via Media Engine.
**Cons:** Requires Swift/Rust binary with ScreenCaptureKit entitlement.
