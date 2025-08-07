# Advanced Server Information Report Tool 🚀

A comprehensive, standalone bash script for monitoring and reporting server health, performance, and security status across all Linux distributions.

## 🌟 Features

### Core Monitoring
- **System Information**: OS, kernel, uptime, load average
- **CPU Monitoring**: Usage, core count, temperature
- **Memory Analysis**: Total, used, free, cached memory with percentage calculations
- **Storage Monitoring**: Disk usage with SMART health checks
- **Network Information**: IP addresses, network configuration, services
- **Service Status**: SSH, firewall, web servers, databases, Docker containers

### Advanced Features
- **Alert System**: Configurable thresholds for CPU, memory, and disk usage
- **Security Analysis**: Failed login attempts, port scanning, firewall status
- **Performance Benchmarks**: CPU, memory, disk I/O performance tests
- **Health Checker**: System health scoring with actionable recommendations
- **Process Information**: Top CPU and memory consuming processes
- **System Updates**: Check for available package updates across distributions
- **Continuous Monitoring**: Real-time monitoring mode with auto-refresh
- **Multiple Export Formats**: TXT, JSON, HTML output formats
- **Detailed Logging**: Comprehensive logging with timestamps
- **Command Line Interface**: Rich CLI with multiple options

### Performance & Reliability
- **Cross-platform**: Linux (all distributions) and macOS support
- **Standalone**: No external dependencies or config files required
- **Error Handling**: Robust error handling and graceful degradation
- **Distribution Detection**: Automatic detection of package managers (apt, yum, dnf)

## 📋 Requirements

### Essential
- Bash 4.0+
- Standard Linux/Unix utilities (ps, df, free, etc.)

### Optional (for enhanced features)
- `bc` - For mathematical calculations (fallback included)
- `smartctl` - For disk health monitoring
- `sensors` - For CPU temperature monitoring
- `docker` - For container monitoring
- `systemctl` or `service` - For service management

## 🐧 Linux Distribution Support

The script automatically detects and supports:

| Distribution | Package Manager | Init System | Status |
|-------------|-----------------|-------------|---------|
| **Ubuntu/Debian** | `apt` | `systemd` | ✅ Full Support |
| **RHEL/CentOS 8+** | `dnf` | `systemd` | ✅ Full Support |
| **RHEL/CentOS 7** | `yum` | `systemd` | ✅ Full Support |
| **RHEL/CentOS 6** | `yum` | `SysV init` | ✅ Full Support |
| **Fedora** | `dnf` | `systemd` | ✅ Full Support |
| **openSUSE** | `zypper` | `systemd` | ✅ Basic Support |
| **Arch Linux** | `pacman` | `systemd` | ✅ Basic Support |
| **Alpine Linux** | `apk` | `OpenRC` | ✅ Basic Support |

## 🚀 Quick Start

### Basic Usage
```bash
# Simple report
./infoReport.sh

# Detailed report with all information
./infoReport.sh --detailed

# Quiet mode (minimal output)
./infoReport.sh --quiet
```

### Advanced Usage
```bash
# Export to JSON format
./infoReport.sh --detailed --output report.json --format json

# Export to HTML format
./infoReport.sh --detailed --output report.html --format html

# Custom alert thresholds
./infoReport.sh --cpu-threshold 90 --mem-threshold 80 --disk-threshold 95

# Security analysis
./infoReport.sh --security-scan --detailed

# Performance benchmarks
./infoReport.sh --performance-test

# System health check
./infoReport.sh --health-check

# Continuous monitoring mode
./infoReport.sh --monitor
```

## ⚙️ Configuration

The script is **completely self-contained** with embedded configuration. No external config files needed!

**Default Settings:**
- CPU Alert Threshold: 80%
- Memory Alert Threshold: 85%
- Disk Alert Threshold: 90%
- Logging: Enabled
- Export Format: TXT

**Runtime Configuration:**
```bash
# Override thresholds
./infoReport.sh --cpu-threshold 90 --mem-threshold 75 --disk-threshold 95

# Disable logging and alerts
./infoReport.sh --no-log --no-alerts
```

## 📊 Command Line Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-d, --detailed` | Enable detailed mode |
| `-q, --quiet` | Run in quiet mode |
| `-o, --output FILE` | Export report to file |
| `-f, --format FORMAT` | Export format (txt, json, html) |
| `--no-log` | Disable logging |
| `--no-alerts` | Disable alert checking |
| `--cpu-threshold N` | Set CPU alert threshold |
| `--mem-threshold N` | Set memory alert threshold |
| `--disk-threshold N` | Set disk alert threshold |
| `--monitor` | Continuous monitoring mode |
| `--security-scan` | Run comprehensive security scan |
| `--performance-test` | Run performance benchmarks |
| `--health-check` | Run system health check |

## 📈 Example Outputs

### Standard Report
```
Advanced Server Information Report
Generated on Thu Aug  7 15:14:21 UTC 2025
----------------------------------------------------------------------------------------------
📊 System Information
Hostname: codespaces-cfedca
OS: Linux 6.8.0-1030-azure x86_64
Uptime: up 48 minutes
Load Average: 0.19, 0.18, 0.30

� CPU Information
CPU Cores: 2
CPU Usage: 0.0%
CPU Temperature: N/A

🧠 Memory Information
Memory Usage: Total: 7943 MB | Used: 2067 MB | Free: 337 MB | Available: 5875 MB

� Storage Information
Filesystem      Size  Used Avail Use% Mounted on
overlay          32G   11G   20G  36% /

🌐 Network Information
Primary IP: 10.0.2.234

📋 Summary
Report Duration: 0 seconds
Total Warnings: 0
Total Errors: 0
✓ System status: OK
```

### JSON Export
```json
{
    "timestamp": "2025-08-07T15:16:24+00:00",
    "hostname": "codespaces-cfedca",
    "system": {
        "os": "Linux 6.8.0-1030-azure x86_64",
        "uptime": "up 50 minutes",
        "load_average": "0.26, 0.24, 0.31"
    },
    "cpu": {
        "cores": 2,
        "usage_percent": 0.0,
        "temperature": "N/A"
    },
    "memory": {
        "usage_percent": 26.5,
        "details": "Total: 7943 MB | Used: 2105 MB | Free: 236 MB | Available: 5838 MB"
    },
    "storage": {
        "root_usage_percent": 36,
        "details": "overlay          32G   11G   20G  36% /"
    },
    "network": {
        "primary_ip": "10.0.2.234"
    },
    "alerts": {
        "warnings": 0,
        "errors": 0
    }
}
```

## 🔧 Installation

### Quick Download & Run
```bash
# Download and run directly
curl -fsSL https://raw.githubusercontent.com/0xPacman/ServerInfoReport/main/infoReport.sh -o infoReport.sh
chmod +x infoReport.sh
./infoReport.sh

# One-liner with basic report
bash <(curl -fsSL https://raw.githubusercontent.com/0xPacman/ServerInfoReport/main/infoReport.sh)

# One-liner with detailed report
bash <(curl -fsSL https://raw.githubusercontent.com/0xPacman/ServerInfoReport/main/infoReport.sh) --detailed
```

### Git Installation
```bash
git clone https://github.com/0xPacman/ServerInfoReport.git
cd ServerInfoReport
chmod +x infoReport.sh
./infoReport.sh --help
```

### Manual Installation
```bash
# Download the script
wget https://raw.githubusercontent.com/0xPacman/ServerInfoReport/main/infoReport.sh
chmod +x infoReport.sh
./infoReport.sh
```

## 🛠️ Customization

### Adding Custom Monitoring
The script can be easily extended. Key functions you can modify:

```bash
# Add custom service checks
check_service your_custom_service

# Add custom thresholds
./infoReport.sh --cpu-threshold 95 --mem-threshold 90

# Add custom export locations
./infoReport.sh -o /var/log/server-report.json -f json
```

## 🔒 Security Considerations

- The script requires appropriate permissions to access system information
- When running as root, be cautious about log file permissions
- Review the script before running in production environments
- Consider restricting access to configuration files

## 🐛 Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure the script has execute permissions
   ```bash
   chmod +x infoReport.sh
   ```

2. **Command Not Found**: The script handles missing commands gracefully
   ```bash
   # For enhanced features, install optional packages:
   # Ubuntu/Debian
   sudo apt-get install bc smartmontools lm-sensors
   
   # CentOS/RHEL
   sudo yum install bc smartmontools lm_sensors
   ```

3. **SMART Data Unavailable**: Run with sudo for disk health checks
   ```bash
   sudo ./infoReport.sh --detailed
   ```

4. **CPU Usage Shows 0%**: This is normal in containers or VMs with low load

## 📝 Logging

Logs are written to `server_report.log` in the script directory. Log format:
```
[2025-08-07 15:14:21] [INFO] Starting server report generation
[2025-08-07 15:14:21] [INFO] Server report completed. Warnings: 0, Errors: 0
```

Disable logging with:
```bash
./infoReport.sh --no-log
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details

## 🔮 Roadmap

### ✅ Current Features (v3.0)
- [x] **Standalone Design**: Single script, no external dependencies
- [x] **Cross-Distribution Support**: Ubuntu, RHEL, CentOS, Fedora, openSUSE, Arch, Alpine
- [x] **Multiple Export Formats**: JSON, HTML, TXT
- [x] **Security Scanning**: Failed logins, port checks, firewall status  
- [x] **Performance Testing**: CPU, memory, disk I/O benchmarks
- [x] **Health Monitoring**: System health checks with thresholds
- [x] **Process Monitoring**: Top CPU/memory consuming processes
- [x] **Continuous Monitoring**: Real-time mode with auto-refresh
- [x] **Smart Error Handling**: Graceful fallbacks for missing tools

### 🚧 In Development
- [ ] Web dashboard with real-time monitoring
- [ ] Enhanced security scanning (vulnerability detection)
- [ ] Network performance testing
- [ ] Container-specific monitoring improvements

### 📋 Future Plans
- [ ] Custom plugin system for extensibility
- [ ] Database integration for historical data
- [ ] Integration with popular monitoring platforms (Prometheus, Grafana)
- [ ] Docker containerization
- [ ] Kubernetes monitoring support
- [ ] Cloud provider integrations (AWS, Azure, GCP)
