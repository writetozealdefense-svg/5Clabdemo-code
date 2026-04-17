#!/bin/bash
# =============================================================================
# 5C Security Lab - One-Shot Tool Installer (Ubuntu/Debian)
#
# Installs ALL security testing tools needed for the 11 labs in one run.
# Tested on: Ubuntu 22.04 LTS, 24.04 LTS, Kali Linux
#
# Usage:
#   chmod +x scripts/install-tools.sh
#   sudo ./scripts/install-tools.sh
#
# Total install size: ~2-3 GB
# Time: ~5-10 minutes (depending on internet speed)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()      { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()    { echo -e "${RED}[FAIL]${NC} $*"; }
section() { echo -e "\n${CYAN}========================================${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}========================================${NC}"; }

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[ERROR] Run with sudo: sudo ./scripts/install-tools.sh${NC}"
    exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
TOOLS_DIR="$REAL_HOME/security-tools"
mkdir -p "$TOOLS_DIR"

export DEBIAN_FRONTEND=noninteractive

section "1/8: System Update + Base Packages"
apt-get update -qq
apt-get install -y -qq \
    curl wget git jq unzip python3 python3-pip python3-venv \
    build-essential golang-go npm nodejs \
    nmap netcat-openbsd dnsutils iproute2 net-tools \
    nikto dirb hydra tcpdump whois \
    apt-transport-https ca-certificates gnupg lsb-release \
    libffi-dev libssl-dev 2>/dev/null
ok "Base packages installed"

# Ensure Go paths are set
export GOPATH="$REAL_HOME/go"
export PATH="$PATH:$GOPATH/bin:/usr/local/go/bin:$REAL_HOME/.local/bin"

section "2/8: Code Layer Tools (Web App Security)"

# sqlmap
if ! command -v sqlmap &>/dev/null; then
    apt-get install -y -qq sqlmap 2>/dev/null || pip3 install --break-system-packages sqlmap 2>/dev/null || pip3 install sqlmap
    ok "sqlmap installed"
else
    ok "sqlmap already present"
fi

# commix
if [ ! -d "$TOOLS_DIR/commix" ]; then
    git clone --depth=1 https://github.com/commixproject/commix.git "$TOOLS_DIR/commix" 2>/dev/null
    ln -sf "$TOOLS_DIR/commix/commix.py" /usr/local/bin/commix 2>/dev/null || true
    ok "commix installed"
else
    ok "commix already present"
fi

# ffuf (Go-based web fuzzer)
if ! command -v ffuf &>/dev/null; then
    su - "$REAL_USER" -c "go install github.com/ffuf/ffuf/v2@latest 2>/dev/null" || warn "ffuf install failed (Go issue)"
    [ -f "$GOPATH/bin/ffuf" ] && ln -sf "$GOPATH/bin/ffuf" /usr/local/bin/ffuf
    ok "ffuf installed"
else
    ok "ffuf already present"
fi

# nuclei (template scanner)
if ! command -v nuclei &>/dev/null; then
    su - "$REAL_USER" -c "go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest 2>/dev/null" || warn "nuclei install failed"
    [ -f "$GOPATH/bin/nuclei" ] && ln -sf "$GOPATH/bin/nuclei" /usr/local/bin/nuclei
    ok "nuclei installed"
else
    ok "nuclei already present"
fi

# XSStrike
if [ ! -d "$TOOLS_DIR/XSStrike" ]; then
    git clone --depth=1 https://github.com/s0md3v/XSStrike.git "$TOOLS_DIR/XSStrike" 2>/dev/null
    pip3 install --break-system-packages -r "$TOOLS_DIR/XSStrike/requirements.txt" 2>/dev/null || pip3 install -r "$TOOLS_DIR/XSStrike/requirements.txt" 2>/dev/null || true
    ok "XSStrike installed"
else
    ok "XSStrike already present"
fi

# SSRFmap
if [ ! -d "$TOOLS_DIR/SSRFmap" ]; then
    git clone --depth=1 https://github.com/swisskyrepo/SSRFmap.git "$TOOLS_DIR/SSRFmap" 2>/dev/null
    pip3 install --break-system-packages -r "$TOOLS_DIR/SSRFmap/requirements.txt" 2>/dev/null || true
    ok "SSRFmap installed"
else
    ok "SSRFmap already present"
fi

# dotdotpwn (path traversal fuzzer)
if [ ! -d "$TOOLS_DIR/dotdotpwn" ]; then
    git clone --depth=1 https://github.com/wireghoul/dotdotpwn.git "$TOOLS_DIR/dotdotpwn" 2>/dev/null
    apt-get install -y -qq libnet-http-perl libswitch-perl 2>/dev/null || true
    ok "dotdotpwn installed"
else
    ok "dotdotpwn already present"
fi

# SecLists (wordlists)
if [ ! -d "/usr/share/seclists" ] && [ ! -d "$TOOLS_DIR/SecLists" ]; then
    apt-get install -y -qq seclists 2>/dev/null || {
        git clone --depth=1 https://github.com/danielmiessler/SecLists.git "$TOOLS_DIR/SecLists" 2>/dev/null
        ln -sf "$TOOLS_DIR/SecLists" /usr/share/seclists 2>/dev/null || true
    }
    ok "SecLists installed"
else
    ok "SecLists already present"
fi

section "3/8: Container Layer Tools (Image Scanning)"

# Trivy
if ! command -v trivy &>/dev/null; then
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor -o /usr/share/keyrings/trivy.gpg 2>/dev/null
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" > /etc/apt/sources.list.d/trivy.list
    apt-get update -qq && apt-get install -y -qq trivy 2>/dev/null || warn "Trivy install via apt failed"
    ok "Trivy installed"
else
    ok "Trivy already present"
fi

# Grype
if ! command -v grype &>/dev/null; then
    curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin 2>/dev/null || warn "Grype install failed"
    ok "Grype installed"
else
    ok "Grype already present"
fi

# Syft (SBOM)
if ! command -v syft &>/dev/null; then
    curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin 2>/dev/null || warn "Syft install failed"
    ok "Syft installed"
else
    ok "Syft already present"
fi

# Hadolint (Dockerfile linter)
if ! command -v hadolint &>/dev/null; then
    wget -qO /usr/local/bin/hadolint https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-x86_64 2>/dev/null && \
    chmod +x /usr/local/bin/hadolint || warn "Hadolint install failed"
    ok "Hadolint installed"
else
    ok "Hadolint already present"
fi

section "4/8: Cluster Layer Tools (Kubernetes Security)"

# kube-hunter
pip3 install --break-system-packages kube-hunter 2>/dev/null || pip3 install kube-hunter 2>/dev/null || warn "kube-hunter install failed"
ok "kube-hunter installed"

# KubiScan
if [ ! -d "$TOOLS_DIR/KubiScan" ]; then
    git clone --depth=1 https://github.com/cyberark/KubiScan.git "$TOOLS_DIR/KubiScan" 2>/dev/null
    pip3 install --break-system-packages -r "$TOOLS_DIR/KubiScan/requirements.txt" 2>/dev/null || true
    ok "KubiScan installed"
else
    ok "KubiScan already present"
fi

# kubeaudit
if ! command -v kubeaudit &>/dev/null; then
    KUBEAUDIT_VER=$(curl -s "https://api.github.com/repos/Shopify/kubeaudit/releases/latest" | jq -r .tag_name 2>/dev/null || echo "v0.22.2")
    wget -qO /tmp/kubeaudit.tar.gz "https://github.com/Shopify/kubeaudit/releases/download/${KUBEAUDIT_VER}/kubeaudit_${KUBEAUDIT_VER#v}_linux_amd64.tar.gz" 2>/dev/null && \
    tar -xzf /tmp/kubeaudit.tar.gz -C /usr/local/bin kubeaudit 2>/dev/null && rm -f /tmp/kubeaudit.tar.gz || warn "kubeaudit install failed"
    ok "kubeaudit installed"
else
    ok "kubeaudit already present"
fi

# kubectl krew (plugin manager)
if [ ! -d "$REAL_HOME/.krew" ]; then
    su - "$REAL_USER" -c '
        cd "$(mktemp -d)" &&
        OS="$(uname | tr "[:upper:]" "[:lower:]")" &&
        ARCH="$(uname -m | sed -e "s/x86_64/amd64/" -e "s/aarch64/arm64/")" &&
        KREW="krew-${OS}_${ARCH}" &&
        curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
        tar zxvf "${KREW}.tar.gz" &&
        ./"${KREW}" install krew 2>/dev/null
    ' 2>/dev/null || warn "krew install failed"
    ok "kubectl krew installed"
else
    ok "krew already present"
fi

section "5/8: Cloud Layer Tools (GCP Security)"

# Prowler
pip3 install --break-system-packages prowler 2>/dev/null || pip3 install prowler 2>/dev/null || warn "Prowler install failed"
ok "Prowler installed"

# ScoutSuite
pip3 install --break-system-packages scoutsuite 2>/dev/null || pip3 install scoutsuite 2>/dev/null || warn "ScoutSuite install failed"
ok "ScoutSuite installed"

# GCPBucketBrute
if [ ! -d "$TOOLS_DIR/GCPBucketBrute" ]; then
    git clone --depth=1 https://github.com/RhinoSecurityLabs/GCPBucketBrute.git "$TOOLS_DIR/GCPBucketBrute" 2>/dev/null
    pip3 install --break-system-packages -r "$TOOLS_DIR/GCPBucketBrute/requirements.txt" 2>/dev/null || true
    ok "GCPBucketBrute installed"
else
    ok "GCPBucketBrute already present"
fi

section "6/8: AI Layer Tools (LLM Security)"

# Garak (NVIDIA LLM vuln scanner)
pip3 install --break-system-packages garak 2>/dev/null || pip3 install garak 2>/dev/null || warn "Garak install failed"
ok "Garak installed"

# promptfoo (Node.js-based)
npm install -g promptfoo 2>/dev/null || warn "promptfoo install failed (npm issue)"
ok "promptfoo installed"

# PyRIT (Microsoft)
pip3 install --break-system-packages pyrit-core 2>/dev/null || pip3 install pyrit-core 2>/dev/null || warn "PyRIT install failed"
ok "PyRIT installed"

# LLM Guard
pip3 install --break-system-packages llm-guard 2>/dev/null || pip3 install llm-guard 2>/dev/null || warn "LLM Guard install failed"
ok "LLM Guard installed"

section "7/8: PDF Export Tools"

pip3 install --break-system-packages markdown-pdf 2>/dev/null || pip3 install markdown-pdf 2>/dev/null || true
ok "markdown-pdf installed"

section "8/8: Verification"

echo ""
echo -e "${CYAN}Installed Tools Summary:${NC}"
echo ""

check() {
    local name="$1" cmd="$2"
    if command -v "$cmd" &>/dev/null || [ -d "$TOOLS_DIR/$name" ]; then
        echo -e "  ${GREEN}[OK]${NC}  $name"
    else
        echo -e "  ${YELLOW}[--]${NC}  $name (may need manual install)"
    fi
}

echo -e "${BLUE}--- Code Layer ---${NC}"
check "sqlmap"     "sqlmap"
check "commix"     "commix"
check "ffuf"       "ffuf"
check "nuclei"     "nuclei"
check "XSStrike"   "XSStrike"
check "SSRFmap"    "SSRFmap"
check "dotdotpwn"  "dotdotpwn"
check "nmap"       "nmap"
check "nikto"      "nikto"

echo -e "${BLUE}--- Container Layer ---${NC}"
check "trivy"      "trivy"
check "grype"      "grype"
check "syft"       "syft"
check "hadolint"   "hadolint"

echo -e "${BLUE}--- Cluster Layer ---${NC}"
check "kube-hunter" "kube-hunter"
check "KubiScan"    "KubiScan"
check "kubeaudit"   "kubeaudit"

echo -e "${BLUE}--- Cloud Layer ---${NC}"
check "prowler"        "prowler"
check "scout"          "scout"
check "GCPBucketBrute" "GCPBucketBrute"

echo -e "${BLUE}--- AI Layer ---${NC}"
check "garak"      "garak"
check "promptfoo"  "promptfoo"
check "pyrit"      "pyrit"
check "llm-guard"  "llm-guard"

echo -e "${BLUE}--- Other ---${NC}"
check "markdown-pdf" "markdown-pdf"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Tool Installation Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "  Git-cloned tools are in: $TOOLS_DIR/"
echo "  SecLists wordlists:      /usr/share/seclists/"
echo ""
echo "  Next: generate personalized lab guide:"
echo "    python3 scripts/generate_student_guide.py --url http://YOUR_NODE_IP:30080"
echo ""
