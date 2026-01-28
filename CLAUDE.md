# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flutterrific OpenTelemetry is a Flutter SDK for comprehensive observability built on the Dartastic OpenTelemetry SDK. It provides automatic instrumentation for Flutter applications including navigation tracking, app lifecycle monitoring, HTTP request instrumentation, and widget-level observability across all Flutter platforms (Android, iOS, Web, Desktop).

**Key Dependencies:**
- `dartastic_opentelemetry` (^0.9.2): Core OpenTelemetry SDK implementation
- `dartastic_opentelemetry_api` (^0.8.8): OpenTelemetry API definitions
- `go_router` (^14.8.1): Router integration support
- `http` (^1.2.2): HTTP instrumentation base

## Build and Development Commands

### Essential Commands

```bash
# Install dependencies (for both main package and example)
make install

# Run all tests
make test
flutter test

# Run tests with coverage report
make coverage

# Analyze code (fatal on infos)
make analyze
flutter analyze --fatal-infos

# Format code
make format
dart format .

# Run all checks (install, test, coverage, analyze, format, pana)
make all

# Pre-commit checks (format, analyze, test)
make pre-commit
```

### Testing Specific Files

```bash
# Run a single test file
flutter test test/otel_integration_test.dart

# Run tests matching a pattern
flutter test --plain-name "navigation observer"
```

### Building the Example App

```bash
# Build for Android
cd example && flutter build apk --debug

# Build for iOS (no code signing)
cd example && flutter build ios --debug --no-codesign

# Build for Web
cd example && flutter build web

# Run example app with environment variables
export HONEYCOMB_API_KEY=<your-api-key>
cd example && ./run-example.sh
```

### Publishing

```bash
# Dry run publish (always test first)
make publish
flutter pub publish --dry-run

# Actual publish (maintainers only)
flutter pub publish
```

### Local OpenTelemetry Collector for Development

```bash
# Run LGTM stack (Loki, Grafana, Tempo, Mimir) with OTel collector
docker run -p 3000:3000 -p 4317:4317 -p 4318:4318 --rm -ti grafana/otel-lgtm
```

## Architecture

### Core Components

**`lib/src/flutterrific_otel.dart` - Main Entry Point**
- `FlutterOTel` class: Primary API for SDK initialization and usage
- `FlutterOTel.initialize()`: Sets up OpenTelemetry with platform-specific exporters (gRPC for native, HTTP for web)
- Manages lifecycle observers, route observers, and interaction trackers
- Provides convenience methods: `tracer`, `meterProvider`, `meter()`, `reportError()`
- Auto-detects platform and creates appropriate OTLP exporters (gRPC for native, HTTP for web)

**Navigation Instrumentation**
- `lib/src/nav/otel_navigator_observer.dart`: Tracks route changes (push, pop, replace, remove)
- `lib/src/nav/otel_go_router_redirect.dart`: GoRouter-specific integration helpers
- `lib/src/nav/otel_route_data.dart`: Route metadata tracking
- Automatically creates spans for navigation events with semantic conventions

**Tracing Layer (lib/src/trace/)**
- `ui_tracer_provider.dart` & `ui_tracer.dart`: Flutter-specific tracer implementations wrapping Dartastic SDK
- `ui_span.dart`: Enhanced span implementation with Flutter context
- `http_instrumentation.dart`: Automatic HTTP client instrumentation via `InstrumentedHttpClient`
  - Creates child spans for HTTP requests following OpenTelemetry HTTP semantic conventions
  - Usage: `final client = InstrumentedHttpClient()` or use `InstrumentedHttp.get/post/etc()`
- `interaction_tracker.dart`: User interaction tracking (button clicks, text input, gestures)

**Metrics Layer (lib/src/metrics/)**
- `ui_meter_provider.dart` & `ui_meter.dart`: Flutter-specific meter implementations
- `otel_metrics_bridge.dart`: Bridges Flutter metrics to OpenTelemetry
- `metric_collector.dart`: Collects and aggregates metrics
- Trackers: `apdex_tracker`, `error_tracker`, `page_tracker`, `paint_tracker`, `user_input_tracker`
- `flutter_metric_reporter.dart`: Reports metrics to OpenTelemetry backend

**Lifecycle & Common**
- `lib/src/common/otel_lifecycle_observer.dart`: Monitors app lifecycle (foreground, background, paused, resumed)
- `lib/src/factory/otel_flutter_factory.dart`: Factory for creating Flutter-specific OTel components
- `lib/src/util/otel_config.dart`: Configuration handling including environment variable support
- `lib/src/util/platform_detection.dart`: Platform-specific detection utilities

### Key Architecture Patterns

**Two-Layer SDK Design:**
1. **Dartastic Layer**: Pure Dart OpenTelemetry implementation (platform-agnostic)
2. **Flutterrific Layer**: Flutter-specific wrappers (UITracer, UIMeter, UISpan) that add widget context and Flutter lifecycle awareness

**Automatic vs Manual Instrumentation:**
- Automatic: Navigation observers, lifecycle observers, error boundaries
- Manual: Custom spans via `FlutterOTel.tracer.startSpan()`, widget extensions (`.withOTelButtonTracking()`, `.withOTelTextFieldTracking()`)

**Context Propagation:**
- Uses OpenTelemetry Context API for automatic parent-child span relationships
- HTTP instrumentation automatically creates child spans of the active span (e.g., `fetch_data` → `HTTP GET`)
- No need to manually pass parent spans; the SDK manages context propagation

**Platform-Specific Exporters:**
- Web platform: Uses OTLP/HTTP (browser limitation)
- Native platforms (Android, iOS, Desktop): Uses OTLP/gRPC
- Auto-detection happens in `FlutterOTel.initialize()` based on `kIsWeb`

**Environment Variables:**
- Supports standard OpenTelemetry environment variables (OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_SERVICE_NAME, etc.)
- Signal-specific variables take precedence (OTEL_EXPORTER_OTLP_TRACES_ENDPOINT over OTEL_EXPORTER_OTLP_ENDPOINT)
- Pass via `--dart-define=VAR_NAME=value` when running Flutter apps

### Testing Infrastructure

**Test Utilities (test/testing_utils/):**
- Mock implementations for testing instrumentation
- Test helpers for async span verification
- Located in `test/testing_utils/`

**Key Test Files:**
- `otel_integration_test.dart`: End-to-end integration tests
- `navigation_observer_test.dart`: Navigation tracking tests
- `lifecycle_observer_test.dart`: App lifecycle tests
- `mock_tracer_test.dart`: Mock implementation tests

### Widget Extensions

The SDK provides convenient widget extensions for easy instrumentation:
- `.withOTelButtonTracking('button_name')`: Track button interactions
- `.withOTelTextFieldTracking('field_name')`: Track text field interactions
- `.withOTelErrorBoundary('context')`: Wrap widgets with error tracking
- `.withOTelPerformanceTracking('widget_name')`: Monitor widget performance

## Important Implementation Notes

### HTTP Instrumentation Context Propagation

When instrumenting HTTP requests, **never** manually pass a `parentSpan` parameter to `startSpan()`. The SDK automatically uses the current active span as the parent through OpenTelemetry's Context API. This ensures HTTP spans are properly nested under operation spans like `fetch_data`.

**Correct:**
```dart
final span = tracer.startSpan('fetch_data', kind: SpanKind.client);
// HTTP client will automatically create child spans under fetch_data
final response = await InstrumentedHttpClient().get(uri);
```

**Incorrect:**
```dart
// Don't do this - breaks context propagation
final span = tracer.startSpan('HTTP GET', parentSpan: someSpan);
```

### Platform Detection

Always use `kIsWeb` from `package:flutter/foundation.dart` to detect web platform. Desktop platforms (Windows, macOS, Linux) should use gRPC exporters like mobile platforms.

### Error Handling

Always call `FlutterOTel.reportError()` for errors to ensure they're tracked in spans and metrics. The SDK records both a span with exception details and increments error counters.

### Resource Attributes vs Trace Attributes

- **Resource Attributes**: Set once at initialization, don't change (service name, version, deployment environment)
- **Trace Attributes**: Can change per-span via `commonAttributesFunction` (user ID, session ID)
- Use `commonAttributesFunction` for dynamic values like `UserSemantics.userId`

### GoRouter Integration

The SDK has special support for GoRouter. Set route observers in GoRouter config:
```dart
GoRouter(
  observers: [FlutterOTel.routeObserver],
  // ... routes
)
```

For MaterialApp without GoRouter, add to `navigatorObservers`:
```dart
MaterialApp(
  navigatorObservers: [FlutterOTel.routeObserver],
  // ...
)
```

## Code Style and Standards

- Follows official Dart style guide and uses `dart format`
- All public APIs must have dartdoc comments
- Apache 2.0 license headers required on all source files
- Must pass `flutter analyze --fatal-infos` (zero warnings/infos allowed)
- OpenTelemetry specification compliance is mandatory
- All new features require tests
- Platform compatibility must be considered (Android, iOS, Web, Desktop)

## Release Process

1. Update version in `pubspec.yaml`
2. Update `CHANGELOG.md` with all changes
3. Run `make all` to verify all checks pass
4. Create release commit and git tag (e.g., `v0.3.4`)
5. Run `make publish` (dry run) to verify package
6. Publish with `flutter pub publish`

## Related Documentation

- Main README.md: User-facing documentation and quick start
- CONTRIBUTING.md: Contribution guidelines and workflow
- DEVELOPMENT.md: Development setup instructions
- ROADMAP.md: Planned features and improvements
- VERSIONING.md: Versioning strategy
- GOVERNANCE.md: Project governance model
- SECURITY.md: Security vulnerability reporting

## External References

- [Wondrous OpenTelemetry Demo](https://github.com/MindfulSoftwareLLC/wondrous_opentelemetry): Full production example
- [OpenTelemetry Specification](https://opentelemetry.io/docs/specs/otel/): Authoritative spec
- [Dartastic OpenTelemetry SDK](https://pub.dev/packages/dartastic_opentelemetry): Underlying SDK
