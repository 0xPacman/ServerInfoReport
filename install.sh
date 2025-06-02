#!/bin/bash

# ServerInfoReport Installation Script
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/0xPacman/ServerInfoReport/main/install.sh) [OPTIONS]

set -e

# Color codes
NC="\033[0m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
BOLD="\033[1m"

# Default values
INSTALL_DIR="$HOME/ServerInfoReport"
RUN_AFTER_INSTALL=false
RUN_OPTIONS=""
BRANCH="main"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --run)
            RUN_AFTER_INSTALL=true
            shift
            ;;
        --options)
            RUN_OPTIONS="$2"
            shift 2
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --help|-h)
            cat << EOF
${BOLD}ServerInfoReport Installation Script${NC}

${BOLD}Usage:${NC}
    bash <(curl -fsSL https://raw.githubusercontent.com/0xPacman/ServerInfoReport/main/install.sh) [OPTIONS]

${BOLD}Options:${NC}
    --dir DIR          Install directory (default: ~/ServerInfoReport)
    --run              Run the script after installation
    --options "OPTS"   Options to pass when running (requires --run)
    --branch BRANCH    Git branch to install (default: main)
    --help, -h         Show this help message

${BOLD}Examples:${NC}
    # Basic installation
    bash <(curl -fsSL https://raw.githubusercontent.com/0xPacman/ServerInfoReport/main/install.sh)
    
    # Install and run with detailed mode
    bash <(curl -fsSL https://raw.githubusercontent.com/0xPacman/ServerInfoReport/main/install.sh) --run --options "--detailed"
    
    # Install to custom directory
    bash <(curl -fsSL https://raw.githubusercontent.com/0xPacman/ServerInfoReport/main/install.sh) --dir /opt/ServerInfoReport
    
    # Install and run security scan
    bash <(curl -fsSL https://raw.githubusercontent.com/0xPacman/ServerInfoReport/main/install.sh) --run --options "--security-scan --detailed"

EOF
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}${BOLD}🚀 Installing ServerInfoReport...${NC}"

# Check requirements
echo -e "${YELLOW}📋 Checking requirements...${NC}"

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${RED}❌ Git is required but not installed${NC}"
    exit 1
fi

# Check if bash version is adequate
bash_version=$(bash --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
if [[ $(echo "$bash_version < 4.0" | bc -l 2>/dev/null || echo "1") == "1" ]]; then
    echo -e "${YELLOW}⚠️  Warning: Bash 4.0+ recommended (current: $bash_version)${NC}"
fi

echo -e "${GREEN}✅ Requirements check passed${NC}"

# Create installation directory
echo -e "${YELLOW}📁 Creating installation directory: $INSTALL_DIR${NC}"
mkdir -p "$INSTALL_DIR"

# Clone repository
echo -e "${YELLOW}📥 Downloading ServerInfoReport from GitHub...${NC}"
if [ -d "$INSTALL_DIR/.git" ]; then
    echo -e "${YELLOW}📦 Updating existing installation...${NC}"
    cd "$INSTALL_DIR"
    git fetch origin
    git reset --hard origin/$BRANCH
else
    git clone -b "$BRANCH" https://github.com/0xPacman/ServerInfoReport.git "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# Make scripts executable
echo -e "${YELLOW}🔧 Setting up permissions...${NC}"
chmod +x *.sh

# Check optional dependencies
echo -e "${YELLOW}🔍 Checking optional dependencies...${NC}"
dependencies=("bc" "smartctl" "sensors" "docker")
missing_deps=()

for dep in "${dependencies[@]}"; do
    if command -v "$dep" &> /dev/null; then
        echo -e "${GREEN}✅ $dep: Available${NC}"
    else
        echo -e "${YELLOW}⚠️  $dep: Not available (optional)${NC}"
        missing_deps+=("$dep")
    fi
done

if [ ${#missing_deps[@]} -gt 0 ]; then
    echo -e "${YELLOW}💡 To install missing optional dependencies:${NC}"
    echo -e "${CYAN}   Ubuntu/Debian: sudo apt-get install bc smartmontools lm-sensors docker.io${NC}"
    echo -e "${CYAN}   CentOS/RHEL:   sudo yum install bc smartmontools lm_sensors docker${NC}"
    echo -e "${CYAN}   macOS:         brew install smartmontools${NC}"
fi

echo -e "${GREEN}🎉 Installation completed successfully!${NC}"
echo -e "${BLUE}📍 Installed to: $INSTALL_DIR${NC}"

# Display usage information
echo -e "\n${BOLD}🚀 Quick Start:${NC}"
echo -e "${CYAN}   cd $INSTALL_DIR${NC}"
echo -e "${CYAN}   ./InfoRaport.sh --help${NC}"
echo -e "${CYAN}   ./InfoRaport.sh --detailed${NC}"

# Add to PATH suggestion
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo -e "\n${BOLD}💡 To add to PATH (optional):${NC}"
    echo -e "${CYAN}   echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.bashrc${NC}"
    echo -e "${CYAN}   source ~/.bashrc${NC}"
fi

# Run the script if requested
if [ "$RUN_AFTER_INSTALL" = true ]; then
    echo -e "\n${BLUE}🏃 Running ServerInfoReport with options: $RUN_OPTIONS${NC}"
    echo -e "${YELLOW}----------------------------------------${NC}"
    ./InfoRaport.sh $RUN_OPTIONS
fi

echo -e "\n${GREEN}${BOLD}✨ All done! Enjoy using ServerInfoReport!${NC}"
