import * as functions from 'firebase-functions';

export const sendAlert = functions.firestore.document('alerts/{alertId}').onCreate(async (snap, context) => {
  // Send notification logic
});
