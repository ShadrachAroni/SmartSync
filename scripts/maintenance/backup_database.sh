#!/bin/bash
# Backup Firestore database

echo "Backing up database..."

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
gcloud firestore export gs://smartsync-backups/firestore_$TIMESTAMP

echo "Database backup complete!"
