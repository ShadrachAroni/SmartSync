import * as functions from 'firebase-functions';

export const scheduleReminder = functions.pubsub.schedule('every 5 minutes').onRun(async (context) => {
  // Reminder logic
});
