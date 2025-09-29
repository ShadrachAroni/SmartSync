# SmartSync — IoT Smart Home Prototype

## Overview

SmartSync is a Flutter-based IoT prototype that enables users to:

* Control a bulb’s brightness and a fan’s speed.
* View live temperature readings from an IoT sensor.
* Monitor security alerts (motion/distance sensors).
* See logs of device actions and security events, which will be used in machine learning for adaptive scheduling.
* Manage schedules, settings, and profiles.

The mobile app connects to an **ESP32 (BLE)** or **Arduino UNO + HC-05 (Classic Bluetooth)** controller, which interfaces with relays, sensors, and actuators.

## File Structure

```
SmartSync/
├── assets/ # Project assets: images, icons, lottie animations, room photos
│ ├── icons/ # UI icons
│ │ ├── avatar.png
│ │ ├── bluetooth.png
│ │ ├── bulb.png
│ │ ├── devices.png
│ │ ├── device_placeholder.png
│ │ ├── fan.png
│ │ ├── home.png
│ │ ├── menu.png
│ │ ├── sensor.png
│ │ ├── Temperature.png
│ │ └── tv.png
│ ├── images/ # Onboarding and other images
│ │ ├── onboarding1.png
│ │ ├── onboarding2.png
│ │ └── onboarding3.png
│ ├── lottie/ # Lottie animation files
│ │ ├── fan.json
│ │ └── onboarding_lively.json
│ └── rooms/ # Room images
│ ├── bathroom.jpg
│ ├── bedroom.jpg
│ ├── dining_room.jpg
│ ├── kitchen.jpg
│ ├── living_room.jpg
│ └── office.jpg
├── lib/ # Dart source code
│ ├── app_theme.dart # Theme configuration
│ ├── main.dart # App entry point
│ ├── routes.dart # App routes configuration
│ ├── models/ # Data models
│ │ └── device.dart
│ ├── providers/ # Riverpod providers for state management
│ │ ├── auth_provider.dart
│ │ ├── device_provider.dart
│ │ └── theme_mode_provider.dart
│ ├── screens/ # UI screens
│ │ ├── device_connection_screen.dart
│ │ ├── device_detail_screen.dart
│ │ ├── home_screen.dart
│ │ ├── logs_screen.dart
│ │ ├── onboarding_screen.dart
│ │ ├── room_detail_screen.dart
│ │ ├── security_screen.dart
│ │ └── settings_screen.dart
│ ├── services/ # Services like Bluetooth, temperature, Supabase
│ │ ├── bluetooth_service.dart
│ │ ├── supabase_service.dart
│ │ └── temperature_service.dart
│ └── widgets/ # Reusable widgets
│ ├── animated_fan.dart
│ ├── animated_temperature_gauge.dart
│ ├── bottom_nav.dart
│ ├── device_connection_card.dart
│ ├── device_tile.dart
│ ├── micro_interactions.dart
│ ├── room_card.dart
│ └── temperature_card.dart
├── pubspec.yaml # Flutter project configuration
└── README.md # Project documentation
```

## Hardware Requirements

* **Option A (Recommended):** ESP32 DevKit V1 (built-in BLE)
* **Option B:** Arduino UNO/Nano + HC-05 Bluetooth module
* 2-channel relay module (for bulb + fan)
* DHT22 or DS18B20 (temperature sensor)
* PIR motion sensor (HC-SR501)
* Ultrasonic distance sensor (HC-SR04)
* Active buzzer (for alerts)
* Power supply (5V DC, ≥2A)
* (Optional) DS3231 RTC module for offline scheduling
* Jumper wires, breadboard, enclosure

⚠️ **Safety Note:** For AC appliances, use relays/SSRs rated for mains loads and consult an electrician.

## Software Requirements

* **Arduino IDE** (with ESP32 board manager URL: `https://dl.espressif.com/dl/package_esp32_index.json`)
* **Flutter SDK** (stable)
* **Supabase account** (for logs, profiles, and schedules)
* **VS Code / Android Studio**

### Flutter Dependencies

* `flutter_blue_plus` or `flutter_reactive_ble` (BLE)
* `flutter_bluetooth_serial` (HC-05 classic)
* `supabase_flutter`
* `flutter_riverpod`
* `go_router`
* `percent_indicator`, `lottie`

Run:

```bash
flutter pub get
```

## MCU Firmware Setup

1. Open Arduino IDE.
2. For ESP32: Install ESP32 board definitions, select “ESP32 Dev Module.”
3. For Arduino UNO + HC-05: Select “Arduino UNO,” connect via COM port.
4. Upload the provided firmware (`esp32_ble_firmware.ino` or `uno_hc05_firmware.ino`).
5. Ensure BLE UUIDs match those in `lib/services/bluetooth_service.dart`:

   ```dart
   static const serviceUuid = "12345678-1234-5678-1234-56789abcdef0";
   static const cmdCharUuid = "12345678-1234-5678-1234-56789abcdef1";
   static const telemetryCharUuid = "12345678-1234-5678-1234-56789abcdef2";
   ```

## Connecting Arduino IDE to Flutter

* **ESP32 (BLE):** Flutter app scans for devices advertising the service UUID and subscribes to telemetry notifications.
* **HC-05 (Classic):** Pair via phone settings, then connect using `flutter_bluetooth_serial`.

## Supabase Setup

1. Create a Supabase project.
2. Obtain `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
3. Replace credentials in `lib/services/supabase_service.dart`.
4. Enable Row-Level Security (RLS) for privacy.

### Database Schema Example

```sql
create table logs (
  id bigserial primary key,
  created_at timestamptz default now(),
  device_id uuid,
  event_type text,
  event text,
  value jsonb,
  source text
);

create table schedules (
  id bigserial primary key,
  device_id uuid,
  user_id uuid,
  time_of_day time,
  repeat_days int[],
  enabled boolean default true,
  mode text,
  created_at timestamptz default now()
);
```

## Adaptive Scheduling

* Logs are analyzed to detect recurring device usage times.
* A Supabase Edge Function or external script suggests schedules (e.g., turning on bulb at 18:00 on weekdays).
* Suggested schedules are stored with `mode='suggested'` and displayed in the app for user approval.

## Running the App

```bash
flutter run
```

Ensure your phone has Bluetooth enabled and is paired (for HC-05) or in range (for ESP32 BLE).

## Testing

* Toggle bulb/fan from app → check relay action.
* View live temperature in app → confirm sensor reading.
* Trigger PIR motion → buzzer alert + log event.
* Check Supabase `logs` table for entries.

## Next Steps

* Move prototype wiring to a secure enclosure.
* Add user authentication with Supabase.
* Expand adaptive scheduling with ML clustering.
* Add offline persistence (EEPROM/Preferences + RTC).

---

**Note:** This is a prototype system for academic/learning purposes. For production, ensure compliance with electrical safety standards and data privacy best practices.
