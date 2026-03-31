#!/bin/bash
# Tests that all expected binaries are present and minimally functional.
# Run inside the container with the entrypoint overridden:
#   docker run --rm --entrypoint bash -v "$PWD/test-container.sh:/test.sh" <image> /test.sh

PASS=0
FAIL=0

green='\033[0;32m'
red='\033[0;31m'
bold='\033[1m'
reset='\033[0m'

ok()   { echo -e "  ${green}✓${reset} $1"; ((PASS++)); }
fail() { echo -e "  ${red}✗${reset} $1"; ((FAIL++)); }

check_version() {
  local label="$1"; shift
  if out=$("$@" 2>&1); then
    ok "$label: $(echo "$out" | head -1)"
  else
    fail "$label: command failed — $out"
  fi
}

# ── Downloads & archives ───────────────────────────────────────────────────────
echo -e "\n${bold}Downloads & archives${reset}"
check_version "wget"    wget --version
check_version "curl"    curl --version
check_version "unzip"   unzip -v
check_version "zip"     zip --version
check_version "xz"      xz --version
check_version "bzip2"   bzip2 --version

# ── Text & data processing ────────────────────────────────────────────────────
echo -e "\n${bold}Text & data processing${reset}"

# jq: actually parse JSON
if echo '{"ok":true}' | jq -e '.ok' >/dev/null 2>&1; then
  ok "jq: parsed JSON successfully"
else
  fail "jq: failed to parse JSON"
fi

check_version "rg (ripgrep)"  rg --version
check_version "fdfind"        fdfind --version
check_version "patch"         patch --version
check_version "xxd"           xxd --version
check_version "bc"            bc --version

# envsubst: substitute a variable
if result=$(echo 'Hello $NAME' | NAME=world envsubst) && [[ "$result" == "Hello world" ]]; then
  ok "envsubst: substituted variable correctly"
else
  fail "envsubst: substitution failed — got '$result'"
fi

# ── Editors & viewers ─────────────────────────────────────────────────────────
echo -e "\n${bold}Editors & viewers${reset}"
check_version "vim"   vim --version
check_version "less"  less --version
check_version "tree"  tree --version

# ── Build tools ───────────────────────────────────────────────────────────────
echo -e "\n${bold}Build tools${reset}"
check_version "gcc"       gcc --version
check_version "g++"       g++ --version
check_version "make"      make --version
check_version "cmake"     cmake --version
check_version "pkg-config" pkg-config --version

# Actually compile a hello-world C program
TMP=$(mktemp -d)
echo '#include<stdio.h>' > "$TMP/hw.c"
echo 'int main(){puts("hi");return 0;}' >> "$TMP/hw.c"
if gcc "$TMP/hw.c" -o "$TMP/hw" && [[ "$("$TMP/hw")" == "hi" ]]; then
  ok "gcc: compiled and ran a C program"
else
  fail "gcc: failed to compile or run hello-world"
fi
rm -rf "$TMP"

# ── Database ──────────────────────────────────────────────────────────────────
echo -e "\n${bold}Database${reset}"

# sqlite3: create a table, insert, query
if result=$(sqlite3 :memory: "CREATE TABLE t(x); INSERT INTO t VALUES(42); SELECT x FROM t;") \
   && [[ "$result" == "42" ]]; then
  ok "sqlite3: created table, inserted, and queried"
else
  fail "sqlite3: in-memory test failed — got '$result'"
fi

# ── Python ecosystem ──────────────────────────────────────────────────────────
echo -e "\n${bold}Python ecosystem${reset}"
check_version "python3"  python3 --version
check_version "pip3"     pip3 --version

# python3 -m venv: create a venv
TMP=$(mktemp -d)
if python3 -m venv "$TMP/venv" && [[ -x "$TMP/venv/bin/python" ]]; then
  ok "python3-venv: created a virtual environment"
else
  fail "python3-venv: failed to create venv"
fi
rm -rf "$TMP"

check_version "uv"   uv --version
check_version "uvx"  uvx --version

# uv: create a venv, then try to install a package (network may not be available)
TMP=$(mktemp -d)
if ! uv venv "$TMP/uv-venv" --quiet 2>&1; then
  fail "uv: failed to create venv"
else
  if uv pip install --quiet --python "$TMP/uv-venv/bin/python" requests >/dev/null 2>&1; then
    ok "uv: created venv and installed a package"
  else
    ok "uv: created venv (network install skipped)"
  fi
fi
rm -rf "$TMP"

# ── Network & SSH ─────────────────────────────────────────────────────────────
echo -e "\n${bold}Network & SSH${reset}"
check_version "ssh"   ssh -V
check_version "rsync" rsync --version
# nc: just check the binary exists and prints usage (exit 1 is fine)
if nc --help 2>&1 | grep -qi 'netcat\|usage\|openbsd'; then
  ok "nc (netcat-openbsd): present"
else
  fail "nc: not found or unexpected output"
fi
check_version "dig"   dig -v
check_version "ping"  ping -V

# ── Process & system ──────────────────────────────────────────────────────────
echo -e "\n${bold}Process & system${reset}"
check_version "ps"         ps --version
check_version "lsof"       lsof -v
check_version "shellcheck" shellcheck --version
check_version "parallel"   parallel --version

# file: detect a known type (-L to follow symlinks)
if file -L /bin/sh | grep -qi 'ELF\|executable\|script'; then
  ok "file: correctly identified /bin/sh — $(file -L /bin/sh | cut -d: -f2- | xargs)"
else
  fail "file: unexpected output for /bin/sh — $(file -L /bin/sh)"
fi

# entr: just verify it's present (it requires a TTY to do anything useful)
if command -v entr >/dev/null 2>&1; then
  ok "entr: present ($(entr 2>&1 | head -1 || true))"
else
  fail "entr: not found"
fi

# ── VCS ───────────────────────────────────────────────────────────────────────
echo -e "\n${bold}VCS${reset}"
check_version "git" git --version
check_version "gh"  gh --version

# ── Runtime ───────────────────────────────────────────────────────────────────
echo -e "\n${bold}Runtime${reset}"
check_version "node" node --version
check_version "npm"  npm --version

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "────────────────────────────────"
TOTAL=$((PASS + FAIL))
if [[ $FAIL -eq 0 ]]; then
  echo -e "${green}${bold}All $TOTAL tests passed${reset}"
else
  echo -e "${red}${bold}$FAIL/$TOTAL tests FAILED${reset}"
fi
echo ""
[[ $FAIL -eq 0 ]]
