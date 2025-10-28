#!/bin/bash
# Clean old logs

echo "Cleaning logs..."

find . -name "*.log" -mtime +30 -delete

echo "Logs cleaned!"
