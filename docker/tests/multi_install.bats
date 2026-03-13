#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'

@test "Multiple happ installation" {
  skip "Needs a HC 0.6.1-compatible happ with initZomeCalls - kando is not compatible"
}
