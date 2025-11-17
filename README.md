# SmartSync: IoT Home Automation System for Elderly Care

<div align="center">

![SmartSync Logo](app/assets/images/logo.png)

**Smart Home Automation with AI-Powered Elderly Monitoring**

[![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?logo=flutter)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Latest-FFCA28?logo=firebase)](https://firebase.google.com)
[![ESP32](https://img.shields.io/badge/ESP32-Compatible-E7352C?logo=espressif)](https://www.espressif.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

[Features](#-features) • [Architecture](#-architecture) • [Getting Started](#-getting-started) • [Documentation](#-documentation)

</div>

---

## 📖 Overview

SmartSync is a comprehensive IoT home automation solution designed specifically for elderly care. It combines real-time environmental monitoring, intelligent device control, and AI-powered health analytics to provide peace of mind for families and independence for elderly users.

### Key Highlights
- 🏠 **Smart Home Control**: Bluetooth-based device management
- 📊 **Real-time Monitoring**: Temperature, humidity, motion, and proximity sensors
- 🤖 **AI Analytics**: Machine learning for pattern detection and predictions
- 🚨 **Emergency Alerts**: SOS system with caregiver notifications
- 📱 **Mobile App**: Flutter-based cross-platform application
- ⚡ **Energy Efficient**: ESP32-powered hardware with optimized power consumption

## ✨ Features

### For Elderly Users
- **Simple Controls**: Large buttons and intuitive interface
- **Voice Commands**: (Coming soon) Voice-activated device control
- **Emergency SOS**: One-tap emergency alert to caregivers
- **Automated Schedules**: Devices adjust based on learned routines
- **Fall Detection**: Motion sensor-based activity monitoring

### For Caregivers
- **Remote Monitoring**: Real-time access to sensor data
- **Health Alerts**: Anomaly detection for unusual patterns
- **Activity Reports**: Daily/weekly activity summaries
- **Multi-User Access**: Multiple caregivers can monitor one elderly user
- **Custom Notifications**: Configure alert thresholds

### Smart Features
- **ML Schedule Prediction**: Learns usage patterns and suggests optimal schedules
- **Anomaly Detection**: Identifies unusual activity that may indicate health issues
- **Energy Optimization**: Recommends energy-saving adjustments
- **Predictive Maintenance**: Alerts for device issues before they fail

## 🏗️ Architecture

### System Components

```
SmartSync/
├── app/                    # Flutter mobile application
├── firmware/              # ESP32 device firmware (C++)
├── ml/                    # Machine learning models (Python)
├── backend/               # Firebase Cloud Functions (TypeScript)
└── docs/                  # Documentation
```

### Technology Stack

#### Mobile App
- **Framework**: Flutter 3.0+
- **Language**: Dart
- **State Management**: Riverpod
- **Backend**: Firebase (Auth, Firestore, Storage, Functions)
- **Communication**: Bluetooth Low Energy (BLE)

#### Hardware
- **Microcontroller**: ESP32 (Dual-core, WiFi + BLE)
- **Sensors**: 
  - DHT22 (Temperature & Humidity)
  - PIR (Motion Detection)
  - HC-SR04 (Ultrasonic Distance)
- **Actuators**:
  - DC Fan with PWM control
  - LED strip with brightness control

#### Machine Learning
- **Framework**: TensorFlow 2.x / TFLite
- **Language**: Python 3.9+
- **Models**:
  - LSTM for schedule prediction
  - Autoencoder for anomaly detection
- **Deployment**: Firebase Cloud Functions

#### Backend
- **Platform**: Firebase
- **Functions**: Cloud Functions (Node.js 18)
- **Database**: Cloud Firestore
- **Storage**: Cloud Storage
- **Auth**: Firebase Authentication

### Data Flow

```
┌─────────────┐         BLE          ┌─────────────┐
│   ESP32     │ ◄──────────────────► │  Mobile App │
│  Hardware   │                      │  (Flutter)  │
└─────────────┘                      └─────────────┘
      │                                     │
      │                                     │
      │                                     ▼
      │                              ┌─────────────┐
      │                              │  Firebase   │
      └─────────────────────────────►│  Firestore  │
                                     └─────────────┘
                                            │
                                            ▼
                                     ┌─────────────┐
                                     │   Cloud     │
                                     │  Functions  │
                                     │   (ML)      │
                                     └─────────────┘
```

## 🚀 Getting Started

### Prerequisites

#### For Mobile App Development
- Flutter SDK 3.0+
- Android Studio / Xcode
- Firebase account
- Git

#### For Hardware Development
- ESP32 board (ESP32-WROOM-32)
- Arduino IDE / PlatformIO
- USB cable for programming
- Required sensors (DHT22, PIR, HC-SR04)

#### For ML Development
- Python 3.9+
- TensorFlow 2.x
- Firebase CLI

### Quick Start

#### 1. Clone Repository
```bash
git clone https://github.com/yourusername/smartsync.git
cd smartsync
```

#### 2. Set Up Mobile App
```bash
cd app
flutter pub get
flutterfire configure
flutter run
```

See [app/README.md](app/README.md) for detailed setup.

#### 3. Set Up Hardware
```bash
cd firmware
# Open in Arduino IDE or PlatformIO
# Configure WiFi credentials in config.h
# Upload to ESP32
```

See [firmware/README.md](firmware/README.md) for detailed setup.

#### 4. Set Up ML Models
```bash
cd ml
pip install -r requirements.txt
python scripts/train_models.py
python scripts/deploy_model.py
```

See [ml/README.md](ml/README.md) for detailed setup.

#### 5. Deploy Cloud Functions
```bash
cd backend
npm install
firebase deploy --only functions
```

See [backend/README.md](backend/README.md) for detailed setup.

## 📱 Mobile App Screenshots

<div align="center">

| Home Screen | Room Management | Analytics |
|------------|-----------------|-----------|
| ![Home](docs/screenshots/home.png) | ![Rooms](docs/screenshots/rooms.png) | ![Analytics](docs/screenshots/analytics.png) |

| Device Control | SOS Alert | Settings |
|---------------|-----------|----------|
| ![Control](docs/screenshots/control.png) | ![SOS](docs/screenshots/sos.png) | ![Settings](docs/screenshots/settings.png) |

</div>

## 🔧 Configuration

### Firebase Setup

1. **Create Firebase Project**
   - Go to [Firebase Console](https://console.firebase.google.com)
   - Create new project
   - Enable Authentication, Firestore, Storage, Functions

2. **Configure Firebase Services**
```bash
firebase init
# Select: Firestore, Functions, Storage
firebase deploy
```

3. **Security Rules**
   - Deploy Firestore rules: `firebase deploy --only firestore:rules`
   - Deploy Storage rules: `firebase deploy --only storage`

### Environment Variables

Create `.env` file in app directory:
```env
FIREBASE_API_KEY=your_api_key
FIREBASE_PROJECT_ID=your_project_id
```

## 📊 Database Schema

### Firestore Collections

```
users/
  {userId}/
    - name: string
    - email: string
    - phoneNumber: string
    - createdAt: timestamp
    
    rooms/
      {roomId}/
        - name: string
        - icon: string
        - deviceIds: array

devices/
  {deviceId}/
    - userId: string
    - name: string
    - type: string
    - roomId: string
    - isOn: boolean
    - value: number
    - lastSeen: timestamp

sensor_logs/
  {logId}/
    - deviceId: string
    - userId: string
    - temperature: number
    - humidity: number
    - motion: boolean
    - distance: number
    - timestamp: timestamp

alerts/
  {alertId}/
    - userId: string
    - type: string
    - severity: string
    - message: string
    - timestamp: timestamp
```

## 🤖 Machine Learning Models

### 1. Schedule Predictor
- **Architecture**: LSTM (64 units)
- **Input**: Historical usage data (7 days)
- **Output**: Predicted device schedules
- **Accuracy**: ~85% on test data

### 2. Anomaly Detector
- **Architecture**: Autoencoder
- **Input**: Activity patterns, sensor readings
- **Output**: Anomaly score (0-1)
- **Detection Rate**: 90% for critical anomalies

### Training Pipeline
```bash
# Collect data
python ml/scripts/collect_data.py

# Train models
python ml/scripts/train_schedule.py
python ml/scripts/train_anomaly.py

# Evaluate
python ml/scripts/evaluate.py

# Deploy
python ml/scripts/deploy_model.py
```

## 🔒 Security

### Mobile App Security
- ✅ Firebase App Check enabled
- ✅ Encrypted local storage for credentials
- ✅ Secure BLE communication
- ✅ Input validation on all forms
- ✅ Email verification required

### Backend Security
- ✅ Firestore security rules enforced
- ✅ Cloud Functions authentication required
- ✅ Rate limiting on API endpoints
- ✅ HTTPS-only communication

### Hardware Security
- ✅ BLE pairing with PIN
- ✅ Encrypted data transmission
- ✅ Secure boot (ESP32)

## 📈 Performance Metrics

### Mobile App
- App startup: <2s
- BLE connection: ~3-5s
- Screen transitions: 60fps
- Memory usage: <150MB

### Backend
- API response time: <500ms
- ML inference: <2s per prediction
- Database queries: <100ms average

### Hardware
- Sensor reading interval: 10s
- BLE latency: <50ms
- Power consumption: ~200mA (active)

## 🧪 Testing

### Mobile App Tests
```bash
cd app

# Unit tests
flutter test

# Integration tests
flutter test integration_test/

# Widget tests
flutter test test/widget_test.dart
```

### ML Model Tests
```bash
cd ml

# Run tests
pytest tests/

# With coverage
pytest --cov=src tests/
```

### Hardware Tests
- Use Arduino IDE Serial Monitor
- Automated tests in `firmware/test/`

## 🚀 Deployment

### Mobile App Deployment

#### Android
```bash
cd app
flutter build appbundle --release
# Upload to Google Play Console
```

#### iOS
```bash
cd app
flutter build ipa --release
# Upload to App Store Connect
```

### Backend Deployment
```bash
cd backend
firebase deploy --only functions
firebase deploy --only firestore:rules
firebase deploy --only storage:rules
```

### ML Model Deployment
```bash
cd ml
python scripts/deploy_model.py --environment production
```

## 📚 Documentation

- **Mobile App**: [app/README.md](app/README.md)
- **Hardware**: [firmware/README.md](firmware/README.md)
- **ML Models**: [ml/README.md](ml/README.md)
- **Backend**: [backend/README.md](backend/README.md)
- **API Reference**: [docs/api.md](docs/api.md)
- **User Guide**: [docs/user-guide.md](docs/user-guide.md)

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

### Development Workflow
1. Fork the repository
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open Pull Request

### Code Style Guidelines
- **Flutter/Dart**: Follow [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)
- **Python**: Follow [PEP 8](https://www.python.org/dev/peps/pep-0008/)
- **C++**: Follow [Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html)

## 🐛 Known Issues

- [ ] iOS BLE background scanning limited by iOS
- [ ] ML model retraining requires manual trigger
- [ ] Voice commands not yet implemented
- [ ] Multi-language support in progress

See [Issues](https://github.com/yourusername/smartsync/issues) for full list.

## 🗺️ Roadmap

### Q1 2025
- ✅ Core BLE functionality
- ✅ Firebase integration
- ✅ ML schedule prediction
- ✅ Basic analytics dashboard

### Q2 2025
- [ ] Voice control integration
- [ ] Apple Watch support
- [ ] Advanced fall detection
- [ ] Medication reminders

### Q3 2025
- [ ] Video monitoring integration
- [ ] Multi-home support
- [ ] Third-party device integrations
- [ ] Web dashboard

### Q4 2025
- [ ] AI health insights
- [ ] Doctor consultation integration
- [ ] Insurance integration
- [ ] Enterprise features

## 📄 License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

## 👥 Team

- **Project Lead**: [Your Name]
- **Mobile Development**: [Developer Name]
- **Hardware Engineering**: [Engineer Name]
- **ML Engineering**: [ML Engineer Name]
- **UI/UX Design**: [Designer Name]

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- Firebase team for backend infrastructure
- Espressif for ESP32 platform
- TensorFlow team for ML tools
- Open source community

## 📞 Support

- **Email**: support@smartsync.com
- **Discord**: [Join our community](https://discord.gg/smartsync)
- **Documentation**: [docs.smartsync.com](https://docs.smartsync.com)
- **Issues**: [GitHub Issues](https://github.com/yourusername/smartsync/issues)

## 📊 Project Status

![GitHub last commit](https://img.shields.io/github/last-commit/yourusername/smartsync)
![GitHub issues](https://img.shields.io/github/issues/yourusername/smartsync)
![GitHub pull requests](https://img.shields.io/github/issues-pr/yourusername/smartsync)
![GitHub stars](https://img.shields.io/github/stars/yourusername/smartsync)

## 🌟 Star History

[![Star History Chart](https://api.star-history.com/svg?repos=yourusername/smartsync&type=Date)](https://star-history.com/#yourusername/smartsync&Date)

---

<div align="center">

**Built with ❤️ for elderly care and independent living**

[Website](https://smartsync.com) • [Documentation](https://docs.smartsync.com) • [Community](https://discord.gg/smartsync)

</div>