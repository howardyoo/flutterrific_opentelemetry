#!/bin/bash

# Script to run Flutter tests with coverage and generate HTML report

set -e

echo "Running Flutter tests with coverage..."
flutter test --coverage

if [ ! -f "coverage/lcov.info" ]; then
    echo "Error: coverage/lcov.info not found"
    exit 1
fi

echo "Generating HTML coverage report..."
if command -v genhtml >/dev/null 2>&1; then
    genhtml coverage/lcov.info -o coverage/html
    echo "Coverage report generated in coverage/html/index.html"
    echo "Open coverage/html/index.html in your browser to view the report"
else
    echo "Warning: genhtml not found. Install lcov to generate HTML reports:"
    echo "  macOS: brew install lcov"
    echo "  Ubuntu: sudo apt-get install lcov"
    echo "  Raw coverage data is available in coverage/lcov.info"
fi

# Extract coverage percentage
if command -v lcov >/dev/null 2>&1; then
    echo "Coverage summary:"
    lcov --summary coverage/lcov.info
else
    echo "Install lcov for coverage summary"
fi
