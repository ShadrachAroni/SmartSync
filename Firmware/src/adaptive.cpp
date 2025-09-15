#include "adaptive.h"
#include "ble_server.h"
#include "preferences.h" // we'll use Preferences for persistence
#include <algorithm>

AdaptiveLog adaptiveLogs[ADAPTIVE_APPLIANCES];

void saveAdaptiveLog(int applianceId) {
  // simplified in-memory for Week1; persist later with Preferences
  // TODO: implement actual prefs storage
}

void log_manual_toggle(uint8_t applianceId, uint16_t minuteOfDay){
  if(applianceId >= ADAPTIVE_APPLIANCES) return;
  AdaptiveLog &L = adaptiveLogs[applianceId];
  L.times[L.head] = minuteOfDay;
  L.head = (L.head + 1) % ADAPTIVE_SAMPLES;
  if(L.count < ADAPTIVE_SAMPLES) L.count++;
  saveAdaptiveLog(applianceId);
  evaluateAdaptive(applianceId);
}

int compute_median(AdaptiveLog &L) {
  if(L.count == 0) return -1;
  int tmp[ADAPTIVE_SAMPLES];
  for(int i=0;i<L.count;i++) tmp[i] = L.times[i];
  std::sort(tmp, tmp + L.count);
  if(L.count % 2) return tmp[L.count/2];
  return (tmp[L.count/2 -1] + tmp[L.count/2]) / 2;
}

void evaluateAdaptive(uint8_t applianceId){
  AdaptiveLog &L = adaptiveLogs[applianceId];
  if(L.count < 4) return; // threshold for demo
  int candidate = compute_median(L);
  // compute range
  int mn = 1440, mx = 0;
  for(int i=0;i<L.count;i++){ if(L.times[i] < mn) mn = L.times[i]; if(L.times[i] > mx) mx = L.times[i]; }
  int range = mx - mn;
  if(range < 60){ // tight cluster -> suggest
    // send suggestion: format SUGGEST:<APPL_ID>:<minute>
    String msg = "SUGGEST:" + String(applianceId) + ":" + String(candidate);
    ble_notify(msg);
  }
}

void handleSimLog(const String &cmd){
  // format: SIMLOG:APPL:HH:MM,HH:MM,...
  // Example: SIMLOG:0:19:05,19:06,19:04
  int p1 = cmd.indexOf(':');
  int p2 = cmd.indexOf(':', p1 + 1);
  if(p1 < 0 || p2 < 0) return;
  String applStr = cmd.substring(p1+1, p2);
  int appl = applStr.toInt();
  String rest = cmd.substring(p2+1);
  int start = 0;
  while(start < rest.length()){
    int comma = rest.indexOf(',', start);
    String token;
    if(comma == -1){ token = rest.substring(start); start = rest.length(); }
    else { token = rest.substring(start, comma); start = comma + 1; }
    token.trim();
    // token format HH:MM
    int colon = token.indexOf(':');
    if(colon > 0){
      int hh = token.substring(0, colon).toInt();
      int mm = token.substring(colon+1).toInt();
      int minute = hh*60 + mm;
      log_manual_toggle(appl, minute);
    }
  }
}

void handleSuggestAccept(const String &applStr){
  // For Week1, just acknowledge
  ble_notify("SUGGEST_ACCEPTED:" + applStr);
  // Later: write schedule to Preferences / EEPROM
}
