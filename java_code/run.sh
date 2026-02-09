#!/usr/bin/env bash
# Run the Java pipeline web app (Jetty on port 8080).
# Java and Maven are downloaded automatically if missing (Linux x64/aarch64).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load .env if present (export DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME, etc.)
if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

# Maven
MAVEN_VERSION="3.9.6"
MAVEN_CACHE="${MAVEN_CACHE:-$SCRIPT_DIR/.mvn-cache}"
MAVEN_HOME="$MAVEN_CACHE/apache-maven-$MAVEN_VERSION"
MAVEN_ZIP="apache-maven-$MAVEN_VERSION-bin.zip"
MAVEN_URL="https://archive.apache.org/dist/maven/maven-3/$MAVEN_VERSION/binaries/$MAVEN_ZIP"

# Eclipse Temurin 17 (used when Java not on PATH)
JDK_VERSION="17.0.13+11"
JDK_CACHE="${JDK_CACHE:-$SCRIPT_DIR/.jdk-cache}"
# GitHub release artifact names
JDK_X64_TAR="OpenJDK17U-jdk_x64_linux_hotspot_17.0.13_11.tar.gz"
JDK_AARCH64_TAR="OpenJDK17U-jdk_aarch64_linux_hotspot_17.0.13_11.tar.gz"
JDK_BASE_URL="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-${JDK_VERSION/+/%2B}"

ensure_java() {
  if command -v java &>/dev/null; then
    return
  fi
  if [[ -n "$JAVA_HOME" && -x "$JAVA_HOME/bin/java" ]]; then
    export PATH="$JAVA_HOME/bin:$PATH"
    return
  fi
  # Use cached JDK if present
  local jdk_dir
  jdk_dir=$(find "$JDK_CACHE" -maxdepth 1 -type d -name 'jdk*' 2>/dev/null | head -1)
  if [[ -n "$jdk_dir" && -x "$jdk_dir/bin/java" ]]; then
    export JAVA_HOME="$jdk_dir"
    export PATH="$JAVA_HOME/bin:$PATH"
    return
  fi
  # Auto-download JDK on Linux
  local os arch tarball url
  os=$(uname -s)
  arch=$(uname -m)
  if [[ "$os" != "Linux" ]]; then
    echo "Error: Java not found. On this OS please install Java 11+ (e.g. OpenJDK) and add it to PATH."
    exit 1
  fi
  if [[ "$arch" == "x86_64" ]]; then
    tarball="$JDK_X64_TAR"
  elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
    tarball="$JDK_AARCH64_TAR"
  else
    echo "Error: Java not found. Unsupported arch: $arch. Install Java 11+ and set PATH or JAVA_HOME."
    exit 1
  fi
  url="$JDK_BASE_URL/$tarball"
  echo "Java not found. Downloading Eclipse Temurin 17 to $JDK_CACHE ..."
  mkdir -p "$JDK_CACHE"
  if command -v curl &>/dev/null; then
    curl -sL "$url" -o "$JDK_CACHE/$tarball"
  elif command -v wget &>/dev/null; then
    wget -q -O "$JDK_CACHE/$tarball" "$url"
  else
    echo "Error: need curl or wget to download the JDK."
    exit 1
  fi
  echo "Extracting JDK ..."
  tar -xzf "$JDK_CACHE/$tarball" -C "$JDK_CACHE"
  rm -f "$JDK_CACHE/$tarball"
  jdk_dir=$(find "$JDK_CACHE" -maxdepth 1 -type d -name 'jdk*' | head -1)
  if [[ -z "$jdk_dir" || ! -x "$jdk_dir/bin/java" ]]; then
    echo "Error: JDK extraction failed."
    exit 1
  fi
  export JAVA_HOME="$jdk_dir"
  export PATH="$JAVA_HOME/bin:$PATH"
  echo "Java ready."
}

ensure_maven() {
  if command -v mvn &>/dev/null; then
    return
  fi
  if [[ -x "$MAVEN_HOME/bin/mvn" ]]; then
    export PATH="$MAVEN_HOME/bin:$PATH"
    return
  fi
  echo "Maven not found. Downloading Maven $MAVEN_VERSION to $MAVEN_CACHE ..."
  mkdir -p "$MAVEN_CACHE"
  if command -v curl &>/dev/null; then
    curl -sL "$MAVEN_URL" -o "$MAVEN_CACHE/$MAVEN_ZIP"
  elif command -v wget &>/dev/null; then
    wget -q -O "$MAVEN_CACHE/$MAVEN_ZIP" "$MAVEN_URL"
  else
    echo "Error: need curl or wget to download Maven."
    exit 1
  fi
  if ! command -v unzip &>/dev/null; then
    echo "Error: unzip required to unpack Maven. Install unzip or install Maven manually."
    exit 1
  fi
  unzip -q -o "$MAVEN_CACHE/$MAVEN_ZIP" -d "$MAVEN_CACHE"
  export PATH="$MAVEN_HOME/bin:$PATH"
  echo "Maven ready."
}

ensure_java
ensure_maven

echo "Starting pipeline at http://localhost:8080/"
echo "Press Ctrl+C to stop."
exec mvn jetty:run
