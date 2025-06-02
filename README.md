# Advanced Server Information Report Tool 🚀

A comprehensive, feature-rich bash script for monitoring and reporting server health, performance, and security status.

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
- **Security Analysis**: Port scanning, file permissions, SSH configuration analysis
- **Performance Benchmarks**: CPU, memory, disk I/O, and network performance tests
- **Health Checker**: System health scoring with actionable recommendations
- **Process Information**: Top CPU and memory consuming processes
- **System Updates**: Check for available package updates
- **Continuous Monitoring**: Real-time monitoring mode with auto-refresh
- **Multiple Export Formats**: TXT, JSON, HTML output formats
- **Email Notifications**: SMTP-based alerts with HTML reports
- **Detailed Logging**: Comprehensive logging with timestamps
- **Command Line Interface**: Rich CLI with 15+ options

### Performance & Reliability
- **Cross-platform**: Linux and macOS support
- **Error Handling**: Robust error handling and graceful degradation
- **Configuration**: INI-based configuration file
- **Daemon Mode**: Background monitoring with start/stop/restart controls

## 📋 Requirements

### Essential
- Bash 4.0+
- Basic Unix utilities (ps, df, free, etc.)

### Optional (for enhanced features)
- `bc` - For mathematical calculations
- `smartctl` - For disk health monitoring
- `sensors` - For CPU temperature monitoring
- `docker` - For container monitoring
- `systemctl` - For service management (Linux)

## 🚀 Quick Start

### Basic Usage
```bash
# Simple report
./InfoRaport.sh

# Detailed report with all information
./InfoRaport.sh --detailed

# Quiet mode (minimal output)
./InfoRaport.sh --quiet
```

### Advanced Usage
```bash
# Export to JSON format
./InfoRaport.sh --detailed --output report.json --format json

# Export to HTML format
./InfoRaport.sh --detailed --output report.html --format html

# Custom alert thresholds
./InfoRaport.sh --cpu-threshold 90 --mem-threshold 80 --disk-threshold 95

# Security analysis
./InfoRaport.sh --security-scan --detailed

# Performance benchmarks
./InfoRaport.sh --performance-test --detailed

# System health check with recommendations
./InfoRaport.sh --health-check --recommendations

# Continuous monitoring mode
./InfoRaport.sh --monitor

# Generate report without display (for automation)
./InfoRaport.sh --report-only --output status.json --format json

# Test email notifications
./InfoRaport.sh --email-test
```

### Daemon Mode
```bash
# Start background monitoring
./monitor_daemon.sh start

# Check daemon status
./monitor_daemon.sh status

# Stop daemon
./monitor_daemon.sh stop

# Restart daemon
./monitor_daemon.sh restart
```

## ⚙️ Configuration

The script uses `config.ini` for configuration. Key settings include:

```ini
[Alerts]
cpu_threshold=80
memory_threshold=85
disk_threshold=90

[Monitoring]
services=ssh,firewall,apache2,nginx,mysql,postgresql
monitor_interval=30

[Export]
default_format=txt
export_dir=./reports
```

## 📊 Command Line Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-d, --detailed` | Enable detailed mode |
| `-q, --quiet` | Run in quiet mode |
| `-o, --output FILE` | Export report to file |
| `-f, --format FORMAT` | Export format (txt, json, html) |
| `-c, --config FILE` | Use custom configuration file |
| `--no-log` | Disable logging |
| `--no-alerts` | Disable alert checking |
| `--cpu-threshold N` | Set CPU alert threshold |
| `--mem-threshold N` | Set memory alert threshold |
| `--disk-threshold N` | Set disk alert threshold |
| `--check-services` | Check additional services |
| `--monitor` | Continuous monitoring mode |
| `--report-only` | Generate report without display |
| `--security-scan` | Run comprehensive security scan |
| `--performance-test` | Run performance benchmarks |
| `--health-check` | Run system health check |
| `--email-test` | Test email notification configuration |
| `--recommendations` | Show system optimization recommendations |

## 📈 Example Outputs

### Standard Report
```
==================================================
           ADVANCED SERVER MONITOR REPORT         
==================================================
Time: Mon Jun  2 10:30:45 UTC 2025
Hostname: server01
Report ID: 1717315845

📊 System Information:
OS & Kernel: Linux server01 5.15.0-72-generic x86_64
Uptime: up 5 days, 14 hours, 23 minutes
Load Average: 0.45, 0.52, 0.48

🖥️ CPU Information:
Total Cores: 4
Usage: 15.2% us, 2.1% sy, 0.0% ni, 82.1% id
Temperature: 45°C

💾 Memory Information:
Total: 8192 MB | Used: 3456 MB | Free: 2134 MB | Available: 4736 MB
Memory Usage: 42.2%

💽 Storage Information:
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1        20G  12G  7.1G  63% /
```

### JSON Export
```json
{
    "timestamp": "2025-06-02T10:30:45Z",
    "hostname": "server01",
    "system": {
        "os": "Linux server01 5.15.0-72-generic x86_64",
        "uptime": "up 5 days, 14 hours, 23 minutes",
        "load_average": "0.45, 0.52, 0.48"
    },
    "cpu": {
        "cores": 4,
        "usage_percent": 15.2,
        "temperature": "45°C"
    },
    "memory": {
        "usage_percent": 42.2
    },
    "storage": {
        "root_usage_percent": 63
    },
    "alerts": {
        "warnings": 0,
        "errors": 0
    }
}
```

## 🔧 Installation

### One-liner Installation

#### Basic Installation
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/0xPacman/ServerInfoReport/main/install.sh)
```

#### Install and Run with Arguments
```bash
# Install and run detailed report
bash <(curl -fsSL https://raw.githubusercontent.com/0xPacman/ServerInfoReport/main/install.sh) --run --options "--detailed"

# Install and run security scan
bash <(curl -fsSL https://raw.githubusercontent.com/0xPacman/ServerInfoReport/main/install.sh) --run --options "--security-scan --detailed"

# Install and run performance test
bash <(curl -fsSL https://raw.githubusercontent.com/0xPacman/ServerInfoReport/main/install.sh) --run --options "--performance-test"

# Install to custom directory
bash <(curl -fsSL https://raw.githubusercontent.com/0xPacman/ServerInfoReport/main/install.sh) --dir /opt/ServerInfoReport
```

#### Installation Script Options
```bash
--dir DIR          # Install directory (default: ~/ServerInfoReport)
--run              # Run the script after installation
--options "OPTS"   # Options to pass when running (requires --run)
--branch BRANCH    # Git branch to install (default: main)
--help, -h         # Show help message
```

### Manual Installation
```bash
git clone https://github.com/0xPacman/ServerInfoReport.git
cd ServerInfoReport
chmod +x *.sh
./InfoRaport.sh --help
```

## 🛠️ Customization

### Adding Custom Services
Edit the `check_service` function or modify the `config.ini` file:

```bash
# In the script, add your service
check_service custom_service_name
```

### Custom Alert Actions
Modify the `check_threshold` function to add custom actions when thresholds are exceeded.

## 🔒 Security Considerations

- The script requires appropriate permissions to access system information
- When running as root, be cautious about log file permissions
- Review the script before running in production environments
- Consider restricting access to configuration files

## 🐛 Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure the script has execute permissions
   ```bash
   chmod +x InfoRaport.sh
   ```

2. **Command Not Found**: Install missing dependencies
   ```bash
   # Ubuntu/Debian
   sudo apt-get install bc smartmontools lm-sensors
   
   # CentOS/RHEL
   sudo yum install bc smartmontools lm_sensors
   ```

3. **SMART Data Unavailable**: Run with sudo for disk health checks
   ```bash
   sudo ./InfoRaport.sh --detailed
   ```

## 📝 Logging

Logs are written to `server_report.log` in the script directory. Log format:
```
[2025-06-02 10:30:45] [INFO] Starting server report generation
[2025-06-02 10:30:46] [WARN] WARNING: CPU usage is above threshold (85% > 80%)
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

### Completed ✅
- [x] HTML report generation with charts and responsive design
- [x] Email alerting with SMTP support
- [x] Security scanning (port scans, file permissions, SSH analysis)
- [x] Performance benchmarking (CPU, memory, disk I/O, network)
- [x] Health checking with scoring system
- [x] Modular architecture with separate specialized modules
- [x] Daemon monitoring with background service controls
- [x] Enhanced CLI with 15+ options

### In Progress 🚧
- [ ] Web dashboard with real-time monitoring
- [ ] Database integration for historical data storage
- [ ] Remote monitoring capabilities

### Planned 📋
- [ ] Custom plugin system for extensibility
- [ ] Mobile-responsive web interface
- [ ] Automated remediation actions
- [ ] Integration with popular monitoring platforms
- [ ] Docker containerization
- [ ] Kubernetes monitoring support
- [ ] Cloud provider integrations (AWS, Azure, GCP)
