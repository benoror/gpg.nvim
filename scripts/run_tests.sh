#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
INIT_FILE=${1:-"$ROOT_DIR/tests/init.lua"}

if [ ! -f "$INIT_FILE" ]; then
  echo "Init file not found: $INIT_FILE" >&2
  exit 1
fi

TMP_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

export XDG_DATA_HOME="$TMP_DIR/nvim-data"
export XDG_STATE_HOME="$TMP_DIR/nvim-state"
export XDG_CACHE_HOME="$TMP_DIR/nvim-cache"
export NVIM_APPNAME="gpg-nvim-test"
mkdir -p "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"

export GNUPGHOME="$TMP_DIR/gnupg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"

PLAINTEXT_FILE="$TMP_DIR/plain.txt"
EXPECTED_FILE="$TMP_DIR/expected.txt"
FIXTURE_FILE="$ROOT_DIR/tests/fixture.txt"
GPG_FILE="$TMP_DIR/fixture.gpg"

if [ ! -f "$FIXTURE_FILE" ]; then
  echo "Fixture file not found: $FIXTURE_FILE" >&2
  exit 1
fi
cp "$FIXTURE_FILE" "$PLAINTEXT_FILE"

GPG_APPEND_LINE="appended line"
awk -v append="$GPG_APPEND_LINE" '{print $0} END{printf "%s", append}' \
  "$PLAINTEXT_FILE" > "$EXPECTED_FILE"

gpg --batch --pinentry-mode loopback --passphrase '' \
  --quick-generate-key "Test User <test@example.com>" default default never
gpg --batch --yes --trust-model always \
  --default-recipient-self -ae -o "$GPG_FILE" "$PLAINTEXT_FILE"

export GPG_TEST_FILE="$GPG_FILE"
export GPG_TEST_PLAINTEXT_FILE="$PLAINTEXT_FILE"
export GPG_TEST_EXPECTED_FILE="$EXPECTED_FILE"
export GPG_TEST_APPEND="$GPG_APPEND_LINE"

nvim --headless -u "$INIT_FILE" +"lua require('tests.test').run()" +qa

gpg --batch --decrypt "$GPG_FILE" > "$TMP_DIR/decrypted.txt"
if ! diff -u "$EXPECTED_FILE" "$TMP_DIR/decrypted.txt" >/dev/null; then
  echo "Decrypted content does not match expected output" >&2
  exit 1
fi

echo "All tests passed for init: $INIT_FILE"
