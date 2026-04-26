#!/usr/bin/env bash
# Set up the environment to be used by AI agents (Codex Cloud, Jules, etc).

# Install bazel.
sudo apt install apt-transport-https curl gnupg -y
curl -fsSL https://bazel.build/bazel-release.pub.gpg | gpg --dearmor >bazel-archive-keyring.gpg
sudo mv bazel-archive-keyring.gpg /usr/share/keyrings
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/bazel-archive-keyring.gpg] https://storage.googleapis.com/bazel-apt stable jdk1.8" | sudo tee /etc/apt/sources.list.d/bazel.list
sudo apt update && sudo apt install bazel-9.0.1
sudo ln -s /usr/bin/bazel-9.0.1 /usr/bin/bazel

# Set up BuildBuddy remote caching.
cat >> ~/.bazelrc << EOF
common:ci --disk_cache=
common:ci --bes_results_url=https://app.buildbuddy.io/invocation/
common:ci --bes_backend=grpcs://remote.buildbuddy.io
common:ci --remote_cache=grpcs://remote.buildbuddy.io
common:ci --remote_download_toplevel
common:ci --remote_timeout=3600
common --remote_header=x-buildbuddy-api-key=$BUILDBUDDY_API_KEY
EOF

# Build and test.
./build.sh
./test.sh
