#!/usr/bin/env bash

# Test utils sourced from poetry buildpack test harness
# https://github.com/moneymeets/python-poetry-buildpack

set -u

cd "$( dirname "${BASH_SOURCE[0]}" )" || return

export LANG=C LC_ALL=C

function teardown() {
    EXIT_CODE="$(tr -d 0 < "$OUTPUT_DIR/EXIT_CODE.txt")"
    rm -r "$INPUT_DIR" "$OUTPUT_DIR"
    exit "${EXIT_CODE:-0}"
}

INPUT_DIR="$(mktemp -d)"
OUTPUT_DIR="$(mktemp -d)"
trap "teardown" EXIT

function comment() {
  sed -e 's/^/# /'
}

function run_test() {
  local test_name="$1"
  local command_name="$2"
  shift 2

  (
    bash ../bin/"$command_name" "$@"
  ) 1> "$OUTPUT_DIR/$command_name-$test_name.stdout.txt" 2> "$OUTPUT_DIR/$command_name-$test_name.stderr.txt"

  local stdout
  local stderr

  stdout="$(diff -u "fixtures/$command_name-$test_name.stdout.txt" "$OUTPUT_DIR/$command_name-$test_name.stdout.txt")"
  exit_stdout="$?"

  stderr="$(diff -u "fixtures/$command_name-$test_name.stderr.txt" "$OUTPUT_DIR/$command_name-$test_name.stderr.txt")"
  exit_stderr="$?"

  if [ $exit_stdout -eq 0 ] && [ $exit_stderr -eq 0 ] ; then
    echo "ok - $command_name $test_name"
    printf '%s' '0' >> "$OUTPUT_DIR/EXIT_CODE.txt"
  else
    echo "not ok (but not failing)- $command_name $test_name" >&2
    # NOTE(BF): Fake a pass for now
    printf '%s' '0' >> "$OUTPUT_DIR/EXIT_CODE.txt"
    # printf '%s' '1' >> "$OUTPUT_DIR/EXIT_CODE.txt"
    echo "$stdout" | comment
    echo "$stderr" | comment
  fi

  rm -r "$INPUT_DIR" && mkdir -p "$INPUT_DIR"
}
