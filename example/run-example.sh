#!/bin/bash

# before running, make sure to set the HONEYCOMB_API_KEY environment variable.
export HONEYCOMB_API_KEY=

# Run the example app
flutter run \
  -d chrome \
  --dart-define=OTEL_SERVICE_NAME=flutterrific_example_app \
  --dart-define=OTEL_SERVICE_VERSION=1.0.0 \
  --dart-define=OTEL_EXPORTER_OTLP_ENDPOINT=https://api.honeycomb.io \
  --dart-define=OTEL_EXPORTER_OTLP_PROTOCOL=grpc \
  --dart-define=OTEL_EXPORTER_OTLP_HEADERS="x-honeycomb-team=$HONEYCOMB_API_KEY"