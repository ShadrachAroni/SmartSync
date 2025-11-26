# SmartSync Connection Flow Verification

## Confirmed Connection Flow Logic

### 1. **Scan for Device**
- User opens device scan screen or app automatically scans
- BLE scan discovers devices with SmartSync service UUID or matching device name
- Devices are displayed in scan results

### 2. **Find Device**
- App matches discovered devices by:
  - Service UUID (4fafc201-1fb5-459e-8fcc-c5c9c331914b)
  - Device name starting with "SmartSync"
  - Device ID matching registered hub in Firebase
- Device is identified and ready for connection

### 3. **Connect to Device**
- Connection process:
  - Pre-connection cleanup (disconnect any existing connections)
  - Connect with 30-second timeout (increased for ESP32)
  - Retry logic: 3 attempts with exponential backoff
  - GATT error 133 handling with force disconnect and retry
  - Service discovery (10-second timeout)
  - Characteristic setup (RX/TX)
  - Data stream subscription
  - Connection maintenance timers start (after 2-second stabilization delay)

### 4. **Device Connection Maintained**
- **Connection Stability Features:**
  - Grace period: 10 seconds after connection (no monitoring)
  - Heartbeat timer: 20 seconds (checks connection health)
  - Keepalive timer: 15 seconds (sends lightweight pings)
  - Inactivity watchdog: 120 seconds grace period (prevents premature disconnection)
  - Sensor polling: 20 seconds (requests sensor data)
  - Activity tracking: All commands and data reception restart inactivity watchdog

- **Auto-Reconnection:**
  - Persistent reconnection service: Checks every 30 seconds for disconnected hubs
  - Immediate retry on unexpected disconnect
  - Exponential backoff retry (up to 5 attempts)
  - Scan-based reconnection if direct retry fails
  - Force reconnect button on home screen

### 5. **View Sensor Data from Hub Device on Home Screen**
- Sensor data stream:
  - Data received via BLE TX characteristic
  - Parsed and validated
  - Emitted to `sensorStreamProvider`
  - Home screen displays:
    - Temperature
    - Humidity
    - Motion detection
    - Distance (ultrasonic)
    - Heat index
    - Comfort level
  - Data updates in real-time while connected

### 6. **Control Appliances (Fan and Light) in Room**
- Fan control:
  - Speed control (0-100% mapped to 0-255)
  - Commands sent via BLE RX characteristic
  - Activity recorded (keeps connection alive)
  - State saved locally if offline
  - Real-time feedback from device

- Light control:
  - Brightness control (0-100% mapped to 0-255)
  - Commands sent via BLE RX characteristic
  - Activity recorded (keeps connection alive)
  - State saved locally if offline
  - Real-time feedback from device

- **Connection Maintained During Control:**
  - All commands call `_recordActivity()` which restarts inactivity watchdog
  - Commands have 50ms minimum delay between writes (prevents GATT errors)
  - Connection state verified before each command
  - Grace period prevents false disconnection triggers

### 7. **Control Security Features**
- Security alarm:
  - SOS button triggers security alarm
  - Motion detection toggle
  - Security state sent via BLE
  - Activity recorded (keeps connection alive)
  - All while maintaining active connection

## Connection Retention Mechanisms

### During Active Operations:
1. **Command Execution:**
   - Each command records activity
   - Restarts inactivity watchdog
   - Prevents disconnection during control operations

2. **Data Reception:**
   - Sensor data reception records activity
   - Restarts inactivity watchdog
   - Keeps connection alive during data streaming

3. **Connection Monitoring:**
   - Grace period prevents false positives
   - Connection state verification before disconnect
   - Only disconnects on confirmed disconnection

### Persistent Reconnection:
1. **Automatic:**
   - Checks every 30 seconds for disconnected registered hubs
   - Multiple retry strategies:
     - Direct connection
     - Force disconnect and retry
     - Reset Bluetooth state and rescan
   - Continues until connection established

2. **Manual:**
   - "Reconnect" button on home screen
   - Force reconnect to registered hub
   - Opens device scan if reconnection fails

## Connection Timeout Handling

- **Initial Connection:** 30 seconds (increased for ESP32)
- **Retry Attempts:** 3 attempts with exponential backoff
- **GATT Error 133:** Force disconnect + 2-4 second delay + retry
- **Timeout Recovery:** Force disconnect + 1-2 second delay + retry
- **Service Discovery:** 10 seconds timeout
- **Connection Stabilization:** 2-second delay before starting timers

## Error Recovery

1. **GATT Error 133:**
   - Detected and handled specifically
   - Force disconnect
   - Wait 2-4 seconds
   - Retry connection

2. **Connection Timeout:**
   - Force disconnect
   - Wait 1-2 seconds
   - Retry with shorter timeout

3. **Unexpected Disconnect:**
   - Immediate retry
   - Exponential backoff (up to 5 attempts)
   - Scan-based reconnection
   - Persistent reconnection service takes over

## Summary

✅ **Scan for device** - Working  
✅ **Find device** - Working  
✅ **Connect to device** - Enhanced with retry logic  
✅ **Device connection maintained** - Multiple stability mechanisms  
✅ **View sensor data** - Real-time streaming  
✅ **Control appliances** - Fan and light control with connection retention  
✅ **Control security features** - Security controls with connection retention  

**Connection is maintained throughout all operations via:**
- Activity tracking on commands and data
- Inactivity watchdog with 120-second grace period
- Connection monitoring with verification
- Persistent reconnection service
- Force reconnect functionality

