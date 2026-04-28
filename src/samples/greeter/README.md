# Greeter Sample

This sample exercises the repo's shared gRPC, Kotlin, Android, desktop, iOS,
Python, web, deploy, and generated backend endpoint config rules.

## Build And Test

Build every greeter target:

```bash
bazel build //src/samples/greeter/...
```

Run every greeter test:

```bash
bazel test //src/samples/greeter/...
```

## Local Backend

Run the Kotlin gRPC backend locally:

```bash
bazel run //src/samples/greeter/backend:backend
```

The backend listens on `http://localhost:8080` by default. To use a different port:

```bash
PORT=9090 bazel run //src/samples/greeter/backend:backend
```

## Local Clients

Run the Python client against the local backend:

```bash
bazel run //src/samples/greeter/python_client:python_client -- Ada
```

Run the Compose Desktop app against the local backend:

```bash
bazel run //src/samples/greeter/desktop:desktop
```

Run the React/Vite web app against the local backend. Keep the backend running
in another terminal first; the Vite dev server proxies `/grpc` to
`http://localhost:8080`.

```bash
bazel run //src/samples/greeter/web:dev
```

For faster Android edit/install cycles on a connected emulator or device, use
incremental mobile install:

```bash
bazel mobile-install --incremental //src/samples/greeter/android:app
```

Or build the Android APK:

```bash
bazel build //src/samples/greeter/android:app
```

Then install and start it on a connected emulator or device:

```bash
adb install -r bazel-bin/src/samples/greeter/android/app.apk
adb shell am start -n victor.greeter.android/.MainActivity
```

To let a connected Android device or emulator reach the backend running on your
development machine at `localhost:8080`, forward the device port back to the
host:

```bash
adb reverse tcp:8080 tcp:8080
```

For an Android emulator calling a backend running on the host machine, build the
APK with the emulator host alias:

```bash
bazel build \
  --//build/rules/backend:backend_service_url_profile=deploy \
  --//src/samples/greeter/backend:backend_config_deploy_service_url=http://10.0.2.2:8080 \
  //src/samples/greeter/android:app
```

Build or run the iOS app and run the iOS unit test:

```bash
bazel build //src/samples/greeter/ios:app
bazel run //src/samples/greeter/ios:app
bazel test //src/samples/greeter/ios:app_test
```

The iOS app currently points at `127.0.0.1:8080` in Swift code.

## Deploy

Dry-run each deploy target to inspect the generated deploy plan:

```bash
bazel run //src/samples/greeter/backend:deploy -- --dry-run
bazel run //src/samples/greeter/web:deploy -- --dry-run
bazel run //src/samples/greeter/android:deploy -- --dry-run
```

Deploy the backend to Cloud Run:

```bash
bazel run //src/samples/greeter/backend:deploy
```

Deploy the web app to Firebase Hosting:

```bash
bazel run //src/samples/greeter/web:deploy
```

Deploy the Android app to Firebase App Distribution:

```bash
bazel run //src/samples/greeter/android:deploy
```

The deployed Android build discovers
`//src/samples/greeter/backend:backend_config` from the Android app dependency
graph, queries the Cloud Run URL for `greeter-backend-dev`, and builds the APK
with that URL baked into the generated Kotlin `BackendConfig`.

## Local clients Against The Deployed Backend

Fetch the deployed Cloud Run URL:

```bash
CLOUD_RUN_URL="$(gcloud run services describe greeter-backend-dev \
  --project victor-dev-493319 \
  --region europe-west1 \
  --platform managed \
  --format='value(status.url)')"
```

Run the Compose Desktop app against the deployed backend:

```bash
bazel run \
  --//build/rules/backend:backend_service_url_profile=deploy \
  --//src/samples/greeter/backend:backend_config_deploy_service_url="${CLOUD_RUN_URL}" \
  //src/samples/greeter/desktop:desktop
```

Build and run the Android APK against the deployed backend:

```bash
bazel mobile-install --incremental \
  --//build/rules/backend:backend_service_url_profile=deploy \
  --//src/samples/greeter/backend:backend_config_deploy_service_url="${CLOUD_RUN_URL}" \
  //src/samples/greeter/android:app
```

The Python client currently uses an insecure local gRPC channel, so use it with
the local backend unless you update it to create a TLS channel for Cloud Run.
