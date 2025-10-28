import * as functions from 'firebase-functions';

export const aggregateData = functions.pubsub.schedule('every 24 hours').onRun(async (context) => {
  // Data aggregation logic
});
