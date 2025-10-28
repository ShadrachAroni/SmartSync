#!/bin/bash
# Configure Firebase project

echo "Configuring Firebase..."

firebase login
firebase use --add

echo "Firebase configured!"
