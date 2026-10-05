#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Reuse the fixture helpers without making updater state transitions a hidden
# subset of the broad portability run.
SILERE_TEST_LIB_ONLY=1 source "$ROOT/dev/test-portability.sh"

if ! command -v git >/dev/null 2>&1 || ! command -v ssh-keygen >/dev/null 2>&1; then
    if [ "${SILERE_REQUIRE_GIT_TESTS:-0}" = 1 ]; then
        fail "git and ssh-keygen are required for updater state-machine tests"
    fi
    printf 'SKIP: updater state-machine tests (git or ssh-keygen unavailable)\n'
    exit 0
fi

test_atomic_update_cache
test_update_lock_survives_orphaned_child
test_installation_mode_detection
test_candidate_runtime_isolation
test_update_refuses_dirty_apply
test_interrupted_update_recovery
test_fresh_install_pins_release
test_update_rejects_broken_stage
test_update_reporting
test_update_apply_binds_to_confirmed_release

printf 'updater state-machine tests passed\n'
