# Test Cases

## Requirements

### 1. Header Documentation

Every test script must have a header comment:

```bash
#!/bin/bash
# Test Name
# =========
#
# Summary: One-line description of what the test verifies.
#
# Background
# ----------
# Why this test is needed and relevant technical background.
#
# Method
# ------
# 1. Specific step 1
# 2. Specific step 2
#
# Expected Results
# ----------------
# - Expected output pattern 1
# - Expected output pattern 2
#
# Environment
# -----------
# - Required tools and dependencies
#
# Usage
# -----
#     ./tests/xxx.sh              # Build and run
#     ./tests/xxx.sh --no-build   # Run without rebuilding
#
# Exit Status
# -----------
# - Returns 0 on success
# - Returns 1 on failure
```

### 2. Path Convention

**No absolute paths allowed.** Use `$(pwd)` instead:

```bash
# Wrong
DIR=~/iexpos

# Correct
DIR=$(pwd)
```

### 3. Temporary Files

**Use `mktemp` to generate unique temp file names.** Fixed names cause
conflicts when multiple tests run in parallel.

```bash
# Wrong: fixed name, conflicts with other tests
TMP_OUT=/tmp/vm-test-output.txt

# Correct: unique name per test run
TMP_OUT=$(mktemp /tmp/vm-test-XXXXXX.txt)
```

Clean up after test completes:

```bash
rm -f $TMP_OUT
```

Always clean up in trap:

```bash
cleanup() {
    rm -f $TMP_OUT
}
trap cleanup EXIT
```

### 4. QEMU Mode

Serial output tests use `-nographic` + `-serial file:`:

```bash
qemu-system-x86_64 \
    -enable-kvm -m 2G -nographic -smp 2 -vga std \
    -drive file=$DISK,format=raw \
    -net none \
    -serial file:$TMP_OUT \
    -monitor none
```

GDB tests use `-serial tcp::`:

```bash
qemu-system-x86_64 \
    -enable-kvm -m 2G -nographic -smp 2 -vga std \
    -drive file=$DISK,format=raw \
    -net none \
    -serial tcp::"$PORT",server,nowait
```

### 5. Check Function

Use a unified `check` function:

```bash
check() {
    local label="$1"
    local pattern="$2"
    if grep -q "$pattern" $TMP_OUT; then
        echo "  PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $label (expected '$pattern')"
        FAIL=$((FAIL + 1))
    fi
}
```

### 6. Avoid Hardcoded Output Strings

Test cases should **not depend on specific serial output text**.
Output strings change frequently during development, causing tests to break.

**Preferred approach**: Test mechanisms, not content.

```bash
# Wrong: depends on specific text
check "Graphics init OK" "Graphics init OK"

# Correct: test that serial works and receives valid output
check "Serial has output" '[^[:space:]]'
```

**Examples of good tests**:
- Serial port can send/receive data
- We receive ANY valid output (not specific text)
- Output matches expected format (timestamp, protocol)
- Kernel symbols exist in ELF (`nm kernel.elf | grep xxx`)
- Memory layout is valid (BSS address ranges)

**Examples of bad tests**:
- Specific strings like "Graphics init OK"
- Specific error messages
- Output that may change between versions

When testing serial output, use Python to extract **structural information**:

```python
def check_serial_output(path):
    """Validate serial output structure, not content."""
    with open(path) as f:
        lines = f.readlines()
    
    checks = {
        'has_output': len(lines) > 0,
        'non_empty_lines': any(l.strip() for l in lines),
        'has_timestamp': any(re.match(r'\d{2}:\d{2}:\d{2}', l) for l in lines),
    }
    return checks
```

For kernel functionality, prefer testing via:
- Symbol table: `nm kernel.elf | grep xxx`
- Memory layout: `nm -n kernel.elf` address ranges
- Protocol responses (GDB, serial read/write)

### 6. Output Format

- Start: `=== Test Name ===`
- Check: `  PASS: description` or `  FAIL: description`
- Summary: `=== Results: X passed, Y failed ===`
- Result: `=== TEST PASSED ===` or `=== TEST FAILED ===`

### 7. Exit Code

```bash
if [ "$PASS" -gt 0 ] && [ "$FAIL" -eq 0 ]; then
    echo "=== TEST PASSED ==="
    exit 0
else
    echo "=== TEST FAILED ==="
    exit 1
fi
```

### 8. --no-build Parameter

Support `--no-build` to skip build:

```bash
if [ "$1" != "--no-build" ]; then
    echo "=== Building ==="
    make -C $DIR clean all 2>&1 | tail -3
fi
```

### 9. Cleanup Function

Use trap to ensure cleanup:

```bash
cleanup() {
    kill $QEMU_PID 2>/dev/null || true
    rm -f $TMP_OUT
    fuser -k "$PORT"/tcp 2>/dev/null || true
}
trap cleanup EXIT
```

### 10. Python Utility Scripts

Python utilities in `tests/` directory should:
- Have a module-level docstring
- Define a `main()` function
- Include `if __name__ == "__main__": main()`

## Running Tests

```bash
# Run all tests
./test.sh

# Run single test
./tests/serial.sh

# Run without rebuild
./tests/serial.sh --no-build
```
