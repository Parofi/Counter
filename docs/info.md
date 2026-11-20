<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the name of the image must contain ONLY alphanumeric characters.

-->

## How it works

This project implements a bidirectional event/object counter (ranging from `000` to `255`) controlled by two external sensors (`sensor_ext` and `sensor_int`) and outputs the result to three multiplexed 7-segment displays.

### 1. Directional Set/Reset Sensing (Finite State Machine)
To prevent false triggers and determine travel direction, a 5-state Finite State Machine (FSM) monitors the activation sequence of both synchronized sensors:
* **Increment (`+1`):** Triggered when `sensor_ext` activates first (acting as **Set**), followed by `sensor_int`. Once the object clears both sensors (`sensor_int` releases as **Reset**), the counter increments by 1 (saturating at `255`).
* **Decrement (`-1`):** Triggered when `sensor_int` activates first (acting as **Set**), followed by `sensor_ext`. Once the object clears both sensors (`sensor_ext` releases as **Reset**), the counter decrements by 1 (saturating at `0`).
* **False-Trigger Rejection:** If an object triggers the first sensor and backs out without crossing the second sensor, the FSM safely returns to the idle state without modifying the count.

### 2. Binary-to-BCD & Multiplexed Display Driver
* **BCD Conversion:** The 8-bit binary count is converted into hundreds, tens, and units digits.
* **Multiplexing:** Driven by a `10 MHz` system clock, an internal timer switches the active digit every `10,000` clock cycles (`1 ms` per digit, resulting in a `~333 Hz` full refresh rate).
* **7-Segment Decoding:** Each BCD digit is decoded to drive common-cathode 7-segment display lines (`a` through `g`) on `uo_out[6:0]`, while `uio_out[2:0]` sequentially enables each corresponding digit.

## How to test

1. **Clock & Reset:** Apply a `10 MHz` clock to `clk` and pulse `rst_n` low (`0`) to initialize the internal state machine and reset the counter to `000`.
2. **Simulate an Increment Sequence:**
   * Set `ui_in` (`sensor_ext`) = `1`, keep `ui_in` (`sensor_int`) = `0`.
   * Set `ui_in` (`sensor_int`) = `1` (both active).
   * Set `ui_in` (`sensor_ext`) = `0`.
   * Set `ui_in` (`sensor_int`) = `0`. Verify that the counter increments to `001`.
3. **Simulate a Decrement Sequence:**
   * Set `ui_in` (`sensor_int`) = `1`, keep `ui_in` (`sensor_ext`) = `0`.
   * Set `ui_in` (`sensor_ext`) = `1` (both active).
   * Set `ui_in` (`sensor_int`) = `0`.
   * Set `ui_in` (`sensor_ext`) = `0`. Verify that the counter decrements back to `000`.
4. **Verify Multiplexing:** Monitor `uio_out[2:0]` (`001` → `010` → `100`) every `1 ms` (`10,000` clock cycles) and confirm that `uo_out[6:0]` outputs the matching 7-segment pattern for units, tens, and hundreds respectively.

## External hardware

* **Two Digital Sensors (`sensor_ext` and `sensor_int`):** Active-high digital sensors (e.g., infrared break-beam modules, photoelectric sensors, or debounced limit switches) connected to `ui_in` and `ui_in`. Ensure voltage levels match the Tiny Tapeout I/O standard (`1.8V` or `3.3V` depending on the carrier board).
* **Three 7-Segment Displays (Common-Cathode):**
  * Connect segments `a` through `g` in parallel across all three displays to `uo_out` through current-limiting resistors (`220 Ω` – `330 Ω`).
  * Connect the common cathodes of Display 0 (Units), Display 1 (Tens), and Display 2 (Hundreds) to `uio_out`, `uio_out`, and `uio_out` respectively via NPN low-side transistor drivers (e.g., `2N2222` or `BC547` with base resistors) to avoid exceeding the chip's per-pin current limit.
