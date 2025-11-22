# SmartSync Mobile App

Flutter-based mobile application for SmartSync IoT Home Automation System, designed specifically for elderly care.

## 📱 Features

### Core Functionality
- **Real-time Device Control**: Control smart home devices via Bluetooth Low Energy (BLE)
- **Environmental Monitoring**: Track temperature, humidity, motion, and proximity sensors
- **Room Management**: Organize devices into rooms with custom themes and icons
- **Analytics Dashboard**: AI-powered insights with overview, insights, and predictions tabs
- **Emergency SOS**: Quick access emergency alert system with caregiver notifications
- **Energy Tracking**: Monitor and optimize energy consumption with daily summaries
- **Activity Logs**: Comprehensive logging system with revert functionality for automation changes
- **Alerts System**: Configurable alerts with severity levels and notification settings
- **Weather Integration**: Real-time weather data and time display on home screen
- **Onboarding**: User-friendly onboarding flow for new users

### AI/ML Features
- **Adaptive Auto Mode**: AI-powered automatic device control that adjusts fan speed and LED brightness based on real-time sensor data and ML predictions
- **Local ML Inference**: On-device TFLite models for schedule prediction (privacy-preserving, fast)
- **Cloud ML Integration**: Server-side ML inference via Firebase Cloud Functions
- **Smart Scheduling**: ML-predicted device schedules based on usage patterns with confidence scores
- **Anomaly Detection**: Automatic detection of unusual activity patterns
- **Usage Analytics**: Comprehensive insights, activity timeline, and usage statistics
- **ML Predictions**: Schedule predictions with device-specific recommendations

### Caregiver Features
- **Caregiver Dashboard**: Dedicated interface for caregivers to monitor patients
- **Remote Control**: Control devices remotely for elderly users
- **Patient Management**: Add and manage multiple patients from caregiver account
- **Activity Monitoring**: Real-time access to patient's sensor data and activity logs
- **Alert Notifications**: Receive push notifications for patient alerts and anomalies

### Automation Features
- **Scheduled Automations**: Create time-based device schedules
- **AI-Suggested Schedules**: ML-powered schedule recommendations
- **Change History**: Track all automation changes with revert capability
- **Context-Aware Automation**: Automations consider temperature, humidity, motion, and time of day

## 🏗️ Architecture

### State Management
- **Riverpod**: Modern reactive state management
- **Providers**: Modular service providers for auth, devices, rooms, and sensors

### Key Services
```
services/
├── auth_service.dart              # Firebase Authentication
├── bluetooth_service.dart         # BLE device communication
├── firebase_service.dart          # Firestore operations
├── ml_service.dart                # ML inference via Cloud Functions
├── tflite_service.dart            # Local TFLite model inference
├── adaptive_auto_service.dart     # AI-powered adaptive automation
├── weather_service.dart           # Weather data integration
├── notification_service.dart      # Push notifications
├── logging_service.dart           # Activity logging
├── appliance_state_service.dart   # Appliance state management
└── voice_service.dart             # Voice command support (future)
```

### Screens
```
screens/
├── auth/                     # Login, signup, password reset, email verification
├── home/                     # Main dashboard with sensor grid
├── devices/                  # Device scanning, control, and settings
├── rooms/                    # Room management (add, edit, detail views)
├── analytics/                # AI-powered analytics (overview, insights, predictions)
├── alerts/                   # Alert management and settings
├── schedules/                # Schedule management and AI suggestions
├── automations/              # Automation creation and management
├── caregiver/                # Caregiver dashboard and patient management
├── logs/                     # Activity logs with revert functionality
├── settings/                 # App settings (profile, security, notifications, privacy)
└── onboarding/               # User onboarding flow
```

## 🚀 Getting Started

### Prerequisites
- Flutter SDK 3.0.0 or higher
- Android Studio / Xcode
- Firebase project configured
- SmartSync hardware device (ESP32-based)

### Installation

1. **Clone the repository**
```bash
git clone <repository-url>
cd app
```

2. **Install dependencies**
```bash
flutter pub get
```

3. **Configure Firebase**
```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Configure Firebase for your project
flutterfire configure
```

4. **Set up environment variables**
Create a `.env` file in the app root:
```env
FIREBASE_API_KEY=your_firebase_api_key
```

5. **Run the app**
```bash
# Debug mode
flutter run

# Release mode
flutter run --release
```

## 📦 Dependencies

### Core
- `firebase_core`: Firebase initialization
- `firebase_auth`: User authentication
- `cloud_firestore`: Database operations
- `cloud_functions`: Cloud Functions integration
- `flutter_riverpod`: State management
- `flutter_blue_plus`: Bluetooth communication
- `tflite_flutter`: Local ML model inference

### UI/UX
- `syncfusion_flutter_charts`: Analytics charts
- `smooth_page_indicator`: Onboarding indicators
- `lottie`: Animations
- `flutter_svg`: Vector graphics

### Utilities
- `permission_handler`: Runtime permissions
- `shared_preferences`: Local storage
- `flutter_secure_storage`: Secure credential storage
- `intl`: Date/time formatting
- `geolocator`: Location services for weather
- `geocoding`: Address geocoding
- `connectivity_plus`: Network connectivity monitoring

## 🔧 Configuration

### Android Setup
1. **Minimum SDK**: API 21 (Android 5.0)
2. **Target SDK**: API 34

**Required Permissions** (AndroidManifest.xml):
```xml
<!-- Bluetooth -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />

<!-- Location (required for BLE on Android 10-11) -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

<!-- Network -->
<uses-permission android:name="android.permission.INTERNET"/>
```

### iOS Setup
1. **Minimum iOS**: 12.0
2. **Info.plist** additions:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>SmartSync needs Bluetooth to control your smart devices</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Required for Bluetooth device scanning</string>
```

## 🎨 Theming

The app uses a custom theme optimized for elderly users:

### Design Principles
- **Large Touch Targets**: Minimum 56px buttons
- **High Contrast**: WCAG AA compliant
- **Large Text**: Base font size 18sp
- **Simple Navigation**: Clear, intuitive flows

### Color Palette
```dart
Primary: #00BFA5 (Teal)
Accent: #4CAF50 (Green)
Error: #F44336 (Red)
Warning: #FFA726 (Orange)
```

## 📡 BLE Communication

### Device Discovery
```dart
final devices = await BluetoothService().scanForDevices();
```

### Connection
```dart
await BluetoothService().connectToDevice(device);
```

### Data Format
```json
{
  "type": "sensor_data",
  "temperature": 24.5,
  "humidity": 55.0,
  "fan_speed": 128,
  "led_brightness": 200,
  "motion": true,
  "distance": 45.2
}
```

### Commands
```json
{
  "cmd": "SET_FAN",
  "value": 128
}
```

## 🔥 Firebase Structure

### Collections
```
users/{userId}
  - name, email, phoneNumber
  - createdAt, preferences
  
  /rooms/{roomId}
    - name, icon, deviceIds
    
devices/{deviceId}
  - userId, name, type, roomId
  - isOn, value, isOnline
  
sensor_logs/{logId}
  - deviceId, userId
  - temperature, humidity, motion
  - timestamp
  
alerts/{alertId}
  - userId, type, severity
  - message, timestamp
  
automations/{automationId}
  - userId, roomId, deviceId
  - enabled, schedule, actions
```

## 🧪 Testing

### Run Tests
```bash
# Unit tests
flutter test

# Integration tests
flutter test integration_test/

# Widget tests
flutter test test/widget_test.dart
```

### Test Coverage
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
```

## 📱 Building for Release

### Android
```bash
# Build APK
flutter build apk --release

# Build App Bundle
flutter build appbundle --release
```

### iOS
```bash
# Build IPA
flutter build ipa --release
```

## 🐛 Debugging

### Enable Debug Logging
```dart
// In main.dart
Logger.debug('Debug message');
Logger.info('Info message');
Logger.error('Error message');
```

### BLE Debugging
```bash
# Android
adb logcat | grep "BluetoothService"

# iOS
# Use Xcode Console
```

## 🔒 Security

### Best Practices
- API keys stored in `.env` (not in version control)
- Sensitive data encrypted with `flutter_secure_storage`
- Firebase security rules enforced
- Input validation on all forms
- Secure BLE communication

### Firebase Security Rules
See `/firebase/firestore.rules` for database rules

## 🌍 Localization

Currently supports:
- English (en)

To add languages:
1. Add translations in `lib/l10n/`
2. Update `pubspec.yaml`
3. Run `flutter gen-l10n`

## 📊 Performance

### Optimization Tips
- Use `const` constructors where possible
- Implement lazy loading for lists
- Optimize images (use WebP)
- Cache network responses
- Use `RepaintBoundary` for complex widgets

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Commit changes
4. Push to branch
5. Create Pull Request

### Code Style
- Follow [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)
- Use `flutter analyze` before committing
- Format code with `flutter format .`

## 📝 License

This project is licensed under the MIT License - see LICENSE file for details.

## 🆘 Support

For issues and questions:
- GitHub Issues: [Create an issue]
- Email: support@smartsync.com
- Documentation: [View docs]

## 🔄 Version History

### v1.0.0 (Current)
- Initial release
- BLE device control
- Room management
- Analytics dashboard
- ML predictions

## 📚 Additional Resources

- [Flutter Documentation](https://docs.flutter.dev)
- [Firebase for Flutter](https://firebase.google.com/docs/flutter/setup)
- [Riverpod Documentation](https://riverpod.dev)
- [BLE Plugin Guide](https://pub.dev/packages/flutter_blue_plus)

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- Firebase team for backend services
- flutter_blue_plus contributors
- Syncfusion for charts library
- Open source community

---

**Built with ❤️ for elderly care**