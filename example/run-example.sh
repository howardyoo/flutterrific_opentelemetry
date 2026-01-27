#!/usr/bash

# before running, make sure to set the HONEYCOMB_API_KEY environment variable.
# export HONEYCOMB_API_KEY=your-api-key

# Run the example app
flutter run \
  --dart-define=OTEL_SERVICE_NAME=my-flutter-app \
  --dart-define=OTEL_SERVICE_VERSION=1.0.0 \
  --dart-define=OTEL_EXPORTER_OTLP_ENDPOINT=https://api.honeycomb.io \
  --dart-define=OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
  --dart-define=OTEL_EXPORTER_OTLP_HEADERS="x-honeycomb-team=$HONEYCOMB_API_KEY"