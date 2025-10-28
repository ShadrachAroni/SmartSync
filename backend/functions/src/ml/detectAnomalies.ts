import * as functions from 'firebase-functions';

export const detectAnomalies = functions.pubsub.schedule('every 1 hours').onRun(async (context) => {
  // Anomaly detection logic
});
