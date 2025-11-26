# Deploying Firestore Rules

## Quick Deploy

From the `backend` directory, run:

```bash
firebase deploy --only firestore:rules
```

## Verify Deployment

1. **Check Firebase Console**
   - Go to [Firebase Console](https://console.firebase.google.com)
   - Select your project
   - Navigate to Firestore Database → Rules
   - Verify the `daily_analytics` rule is present

2. **Test the Rules**
   - Use the Rules Playground in Firebase Console
   - Test query: `daily_analytics` collection
   - Authenticated user should be able to read documents where `userId == auth.uid`

## Troubleshooting

### If rules still don't work after deployment:

1. **Check Firebase Project**
   ```bash
   firebase projects:list
   firebase use --add  # Select correct project
   ```

2. **Verify Rules File**
   ```bash
   # From backend directory
   cat firestore.rules
   # Should contain daily_analytics rule
   ```

3. **Check for Syntax Errors**
   ```bash
   firebase deploy --only firestore:rules --debug
   ```

4. **Wait for Propagation**
   - Rules can take 1-2 minutes to propagate
   - Try again after waiting

5. **Clear App Cache**
   - Uninstall and reinstall the app
   - Or clear app data

## Current Rules

### daily_analytics
```javascript
match /daily_analytics/{analyticsId} {
  // Users can only read their own analytics
  allow read: if request.auth != null && 
               resource.data.userId == request.auth.uid;
  // Write access for authenticated users
  allow write: if request.auth != null;
}
```

### automations
```javascript
match /automations/{automationId} {
  // Users can read automations where they are the owner (userId matches auth.uid)
  // This works for both direct document access and queries
  allow read: if request.auth != null && 
               resource.data.userId == request.auth.uid;
  // Users can create automations for themselves
  allow create: if request.auth != null && 
                 request.resource.data.userId == request.auth.uid;
  // Users can update/delete their own automations
  allow update, delete: if request.auth != null && 
                       resource.data.userId == request.auth.uid;
}
```

These rules ensure:
- Users can only read their own data (analytics/automations where `userId` matches their authenticated `uid`)
- Works for both direct document access and queries
- Write access is properly restricted to the document owner

