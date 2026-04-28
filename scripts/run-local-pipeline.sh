#!/usr/bin/env bash

set -euo pipefail


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' 
BOLD='\033[1m'

IMAGE_NAME="devsecops-demo:local"
PASS=0
FAIL=0

log_stage() { echo -e "\n${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}${BOLD}  $1${NC}"; echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
log_pass() { echo -e "${GREEN}  ✅ PASS: $1${NC}"; PASS=$((PASS+1)); }
log_fail() { echo -e "${RED}  ❌ FAIL: $1${NC}"; FAIL=$((FAIL+1)); }
log_warn() { echo -e "${YELLOW}  ⚠️  WARN: $1${NC}"; }
log_info() { echo -e "     $1"; }

check_command() {
  if ! command -v "$1" &> /dev/null; then
    echo -e "${RED}ERROR: '$1' is not installed. Please install it first.${NC}"
    exit 1
  fi
}

echo -e "\n${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   🔐 DevSecOps Pipeline — Local Demo    ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"


log_stage "0. Checking Prerequisites"
check_command "docker"
check_command "python3"
log_pass "Docker and Python3 available"

log_stage "1. Unit Tests + Coverage"
if python3 -m pip install -q pytest pytest-cov flask 2>/dev/null && \
   python3 -m pytest tests/ --cov=app --cov-report=term-missing -q 2>&1; then
  log_pass "All unit tests passed"
else
  log_fail "Unit tests failed"
fi

log_stage "2. Secret Detection (manual pattern scan)"
log_info "Scanning source code for hardcoded credentials..."

SECRETS_FOUND=0
PATTERNS=("password\s*=\s*[\"'][^\"']{4,}[\"']" "secret\s*=\s*[\"'][^\"']{4,}[\"']" "api_key\s*=\s*[\"'][^\"']{4,}[\"']" "token\s*=\s*[\"'][^\"']{4,}[\"']")

for pattern in "${PATTERNS[@]}"; do
  MATCHES=$(grep -riE "$pattern" app/ 2>/dev/null | grep -v "environ" | grep -v "#" || true)
  if [ -n "$MATCHES" ]; then
    log_warn "Potential secret found matching pattern '$pattern':"
    echo "$MATCHES"
    SECRETS_FOUND=1
  fi
done

if [ $SECRETS_FOUND -eq 0 ]; then
  log_pass "No hardcoded credentials detected in source code"
else
  log_fail "Hardcoded credentials found! Fix before deploying."
fi

log_stage "3. Dockerfile Linting — Hadolint"
if docker run --rm -i hadolint/hadolint:latest < Dockerfile; then
  log_pass "Production Dockerfile passed Hadolint checks"
else
  log_fail "Production Dockerfile has linting issues"
fi

echo ""
log_info "Now scanning VULNERABLE Dockerfile (issues expected for demo):"
docker run --rm -i hadolint/hadolint:latest < docker/Dockerfile.vulnerable || true
log_warn "Vulnerable Dockerfile has expected issues (shown above)"

log_stage "4. Building Docker Image"
if docker build -t "$IMAGE_NAME" . -q; then
  log_pass "Docker image built successfully: $IMAGE_NAME"
else
  log_fail "Docker build failed"
  exit 1
fi

log_stage "5. Container Vulnerability Scan — Trivy"
log_info "Scanning image for ALL vulnerabilities..."
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$HOME/.trivy-cache:/root/.cache/" \
  aquasec/trivy:latest image \
  --severity CRITICAL,HIGH,MEDIUM \
  --format table \
  --exit-code 0 \
  "$IMAGE_NAME" || true

echo ""
log_info "⛔ QUALITY GATE: Checking for CRITICAL vulnerabilities only..."
if docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$HOME/.trivy-cache:/root/.cache/" \
  aquasec/trivy:latest image \
  --severity CRITICAL \
  --exit-code 1 \
  --quiet \
  "$IMAGE_NAME" 2>/dev/null; then
  log_pass "Quality Gate PASSED — No CRITICAL vulnerabilities found!"
else
  log_fail "Quality Gate BLOCKED — CRITICAL vulnerabilities detected! Deploy blocked."
fi

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║              Pipeline Summary            ║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════════╣${NC}"
echo -e "${BOLD}║  ${GREEN}Passed: $PASS${NC}${BOLD}                               ║${NC}"
echo -e "${BOLD}║  ${RED}Failed: $FAIL${NC}${BOLD}                               ║${NC}"
if [ $FAIL -eq 0 ]; then
  echo -e "${BOLD}║  ${GREEN}🚀 ALL GATES PASSED — DEPLOY APPROVED   ${NC}${BOLD}║${NC}"
else
  echo -e "${BOLD}║  ${RED}⛔ GATES FAILED — DEPLOY BLOCKED        ${NC}${BOLD}║${NC}"
fi
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"

exit $FAIL
