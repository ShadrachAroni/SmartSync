# SmartSync Serial Command Reference

The ESP32 firmware now exposes a plain-text command console over the primary USB serial port (115200 baud, 8N1). Any terminal works:

- Arduino Serial Monitor / PlatformIO Monitor
- `screen`, `picocom`, etc.
- Android **Serial Bluetooth Terminal** when paired through a USB‑OTG cable or an HC‑05/HC‑06 Bluetooth‑to‑UART bridge that is wired to the ESP32 UART.

Send commands as ASCII text terminated with `Enter`. Commands are case-insensitive.

| Command | Argument | Purpose |
| --- | --- | --- |
| `HELP` | – | Print the list of supported commands. |
| `INFO` | – | Dump the latest sensor snapshot to the console. |
| `STATUS` | – | Push the current telemetry packet over BLE immediately (mirrors what the mobile app would receive). |
| `FAN <0-255>` | Raw PWM value | Sets the fan speed directly (0 = off, 255 = full). |
| `FANP <0-100>` | Percent | Sets fan speed using a human-friendly percentage. |
| `LED <0-255>` | Raw PWM value | Sets ambient LED brightness directly. |
| `LEDP <0-100>` | Percent | Sets ambient LED brightness via percentage. |
| `AUTO <ON|OFF>` | State flag | Enables or disables adaptive automatic mode. |
| `SECURITY <ON|OFF>` | State flag | Arms/disarms the security subsystem. |
| `BUZZER <ON|OFF>` | State flag | Latches the buzzer in a smoke-detector pattern until you turn it off. |
| `SOS <milliseconds>` | Duration | Fires the buzzer/alarm for the specified time (200–60000 ms). `ALARM` is an alias. |

Every setter command persists to flash (via `Preferences`) and immediately mirrors the change back to any connected BLE client, which allows quick validation from the Serial Bluetooth Terminal app: send the command via serial and observe the status JSON streaming to the app within the next heartbeat.

`BUZZER ON` keeps the active buzzer in the same 3-chirp smoke-detector cadence the security system uses during intrusions; it will continue until you send `BUZZER OFF` or power-cycle the MCU. `SOS`/`ALARM` remain one-shot pulses that automatically time out after the requested duration.

If you need to reprint the guide at any time, just type `help` and press Enter.

## RGB Status LED Legend

The tri-color status LED near the ESP32 provides a quick health check without opening the serial console:

- **Pulsing red (breathing)** – Device is scanning/advertising on BLE and waiting for a client.
- **Solid green** – BLE connection established; system is healthy.
- **Solid amber** – Security system is disarmed (manual override via serial/BLE).
- **Blinking red (250 ms cadence)** – Alarm condition is active (motion/distance threshold or manual SOS command).

If the LED appears off, the RGB driver likely hasn’t been initialised yet (during the first few hundred milliseconds of boot) or the device is powering down.

