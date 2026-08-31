#!/usr/bin/env bash
# Tests for py-test-matrix.sh. Runs a throwaway git repo with a known tree so
# the changed-dir logic is exercised without touching the real repo.
#
# Run: .github/scripts/tests/test_py_test_matrix.sh

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/py-test-matrix.sh"
fails=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        printf 'ok   - %s\n' "$name"
    else
        printf 'FAIL - %s\n      expected: %s\n      actual:   %s\n' "$name" "$expected" "$actual"
        fails=$((fails + 1))
    fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

git init -q
git config user.email t@t.t
git config user.name t

mkdir -p cli/alpha/tests cli/beta/tests cli/no-tests apps/gamma/tests apps/swift-app
echo 'print(1)' > cli/alpha/alpha.py
echo 'def test_a(): pass' > cli/alpha/tests/test_alpha.py
echo 'print(2)' > cli/beta/beta.py
echo 'def test_b(): pass' > cli/beta/tests/test_beta.py
echo 'print(3)' > cli/no-tests/thing.py
echo 'print(4)' > apps/gamma/gamma.py
echo 'def test_g(): pass' > apps/gamma/tests/test_gamma.py
echo 'let x = 1' > apps/swift-app/Project.swift
git add -A
git commit -qm init

# 1. No refs -> every testable Python leaf, sorted, no-tests and swift excluded.
check "all testable, no refs" \
    '["apps/gamma","cli/alpha","cli/beta"]' \
    "$("$SCRIPT")"

# 2. BASE == HEAD -> same as no refs.
check "BASE==HEAD is all" \
    '["apps/gamma","cli/alpha","cli/beta"]' \
    "$("$SCRIPT" HEAD HEAD)"

# 3. Change one leaf -> only that leaf.
echo '# touch' >> cli/beta/beta.py
git add -A
git commit -qm "touch beta"
check "one changed leaf" \
    '["cli/beta"]' \
    "$("$SCRIPT" HEAD~1 HEAD)"

# 4. Change only a non-test leaf -> empty matrix.
echo '# touch' >> cli/no-tests/thing.py
git add -A
git commit -qm "touch no-tests"
check "changed leaf without tests -> empty" \
    '[]' \
    "$("$SCRIPT" HEAD~1 HEAD)"

# 5. Change the swift app -> empty matrix.
echo '// touch' >> apps/swift-app/Project.swift
git add -A
git commit -qm "touch swift"
check "changed swift app -> empty" \
    '[]' \
    "$("$SCRIPT" HEAD~1 HEAD)"

# 6. Change two leaves in one range -> both, sorted.
echo '# t' >> cli/alpha/alpha.py
echo '# t' >> apps/gamma/gamma.py
git add -A
git commit -qm "touch two"
check "two changed leaves" \
    '["apps/gamma","cli/alpha"]' \
    "$("$SCRIPT" HEAD~1 HEAD)"

if [ "$fails" -ne 0 ]; then
    printf '\n%d test(s) failed\n' "$fails"
    exit 1
fi
printf '\nall tests passed\n'
