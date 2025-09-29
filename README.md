# SmartSync — Smart Home Flutter 

## Setup

1. Clone or create a new Flutter project and copy files into proper structure (`lib/`, `assets/`, etc).
2. Add your assets to `assets/icons/` and `assets/images/`.
3. Update `pubspec.yaml` (already provided) and run:


flutter pub get

4. Replace Supabase credentials in `lib/services/supabase_service.dart`.
5. Platform-specific: On Android add Bluetooth and location permissions in `AndroidManifest.xml`. On iOS add Bluetooth and location entries in `Info.plist`.
6. Build & run:


flutter run


## BLE & PlatformIO

- Example BLE firmware included (ESP32). Update pins and implement sensor reading logic.
- Ensure BLE UUIDs match `lib/services/bluetooth_service.dart`.

## Supabase

- Create tables (run SQL in the Supabase SQL editor).
- Use `SupabaseService` helpers for upsert and logs.

## Adaptive Scheduling / ML

- You can implement an Edge Function or a small serverless Python function that trains on `logs` table and outputs schedules. Then call it from the app or via Supabase RPC.

## Notes

- This project uses Riverpod for state, GoRouter for navigation, percent_indicator and animations for UI polish.
- Replace placeholder icons with proper vector artwork that matches the original mockup.

## Project Structure
  
app/
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