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
- **Security Analysis**: Failed login attempts, open ports, security status
- **Process Information**: Top CPU and memory consuming processes
- **System Updates**: Check for available package updates
- **Continuous Monitoring**: Real-time monitoring mode with auto-refresh
- **Multiple Export Formats**: TXT, JSON output formats
- **Detailed Logging**: Comprehensive logging with timestamps
- **Command Line Interface**: Rich CLI with multiple options

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

# Custom alert thresholds
./InfoRaport.sh --cpu-threshold 90 --mem-threshold 80 --disk-threshold 95

# Continuous monitoring mode
./InfoRaport.sh --monitor

# Generate report without display (for automation)
./InfoRaport.sh --report-only --output status.json --format json
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
| `-f, --format FORMAT` | Export format (txt, json) |
| `--no-log` | Disable logging |
| `--no-alerts` | Disable alert checking |
| `--cpu-threshold N` | Set CPU alert threshold |
| `--mem-threshold N` | Set memory alert threshold |
| `--disk-threshold N` | Set disk alert threshold |
| `--monitor` | Continuous monitoring mode |
| `--report-only` | Generate report without display |

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
```bash
bash -c "$(curl -fsSL https://is.gd/swKQZM)"
```

### Manual Installation
```bash
git clone <repository-url>
cd ServerInfoReport
chmod +x InfoRaport.sh monitor_daemon.sh
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

- [ ] HTML report generation
- [ ] Email alerting
- [ ] Database integration
- [ ] Web dashboard
- [ ] Custom plugin system
- [ ] Remote monitoring capabilities
