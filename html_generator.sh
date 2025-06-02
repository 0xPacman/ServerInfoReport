#!/bin/bash

# HTML Report Generator for Advanced Server Report
# Generates beautiful HTML reports with charts and styling

generate_html_report() {
    local output_file="$1"
    local timestamp=$(date)
    local hostname=$(hostname)
    local report_id=$(date +%s)
    
    # Get system information
    local os_info=$(uname -srm)
    local uptime_info=$(get_uptime_info 2>/dev/null || echo "N/A")
    local cpu_usage=$(get_cpu_usage)
    local cpu_count=$(get_cpu_count)
    local memory_info=$(get_memory_usage)
    local memory_percent=$(get_memory_percentage 2>/dev/null || echo "0")
    local disk_percent=$(get_disk_percentage 2>/dev/null || echo "0")
    local load_avg=$(get_load_average 2>/dev/null || echo "N/A")
    
    cat > "$output_file" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Advanced Server Report</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: #333;
            line-height: 1.6;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .header {
            background: white;
            border-radius: 15px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
            text-align: center;
        }
        
        .header h1 {
            color: #2c3e50;
            font-size: 2.5em;
            margin-bottom: 10px;
            background: linear-gradient(45deg, #3498db, #2c3e50);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        
        .header-info {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        
        .header-item {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 10px;
            border-left: 4px solid #3498db;
        }
        
        .header-item strong {
            color: #2c3e50;
            display: block;
            margin-bottom: 5px;
        }
        
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 30px;
        }
        
        .card {
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }
        
        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 15px 40px rgba(0,0,0,0.15);
        }
        
        .card-header {
            display: flex;
            align-items: center;
            margin-bottom: 20px;
            padding-bottom: 15px;
            border-bottom: 2px solid #ecf0f1;
        }
        
        .card-icon {
            font-size: 1.8em;
            margin-right: 15px;
            background: linear-gradient(45deg, #3498db, #2980b9);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        
        .card-title {
            font-size: 1.4em;
            color: #2c3e50;
            font-weight: 600;
        }
        
        .metric {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 0;
            border-bottom: 1px solid #ecf0f1;
        }
        
        .metric:last-child {
            border-bottom: none;
        }
        
        .metric-label {
            color: #7f8c8d;
            font-weight: 500;
        }
        
        .metric-value {
            font-weight: 600;
            color: #2c3e50;
        }
        
        .status-good { color: #27ae60; }
        .status-warning { color: #f39c12; }
        .status-error { color: #e74c3c; }
        
        .progress-bar {
            width: 100%;
            height: 20px;
            background: #ecf0f1;
            border-radius: 10px;
            overflow: hidden;
            margin: 10px 0;
        }
        
        .progress-fill {
            height: 100%;
            border-radius: 10px;
            transition: width 0.3s ease;
        }
        
        .progress-low { background: linear-gradient(45deg, #27ae60, #2ecc71); }
        .progress-medium { background: linear-gradient(45deg, #f39c12, #e67e22); }
        .progress-high { background: linear-gradient(45deg, #e74c3c, #c0392b); }
        
        .chart-container {
            position: relative;
            height: 300px;
            margin: 20px 0;
        }
        
        .footer {
            text-align: center;
            color: white;
            margin-top: 30px;
            padding: 20px;
        }
        
        .alert {
            padding: 15px;
            border-radius: 10px;
            margin: 10px 0;
            display: flex;
            align-items: center;
        }
        
        .alert-warning {
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            color: #856404;
        }
        
        .alert-error {
            background: #f8d7da;
            border-left: 4px solid #dc3545;
            color: #721c24;
        }
        
        .alert-success {
            background: #d4edda;
            border-left: 4px solid #28a745;
            color: #155724;
        }
        
        @media (max-width: 768px) {
            .container {
                padding: 10px;
            }
            
            .grid {
                grid-template-columns: 1fr;
            }
            
            .header-info {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🖥️ Advanced Server Report</h1>
            <div class="header-info">
EOF

    # Add dynamic content
    cat >> "$output_file" << EOF
                <div class="header-item">
                    <strong>Generated</strong>
                    $timestamp
                </div>
                <div class="header-item">
                    <strong>Hostname</strong>
                    $hostname
                </div>
                <div class="header-item">
                    <strong>Report ID</strong>
                    $report_id
                </div>
                <div class="header-item">
                    <strong>Warnings</strong>
                    <span class="status-warning">$TOTAL_WARNINGS</span>
                </div>
            </div>
        </div>

        <div class="grid">
            <!-- System Information Card -->
            <div class="card">
                <div class="card-header">
                    <span class="card-icon">📊</span>
                    <span class="card-title">System Information</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Operating System</span>
                    <span class="metric-value">$os_info</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Uptime</span>
                    <span class="metric-value">$uptime_info</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Load Average</span>
                    <span class="metric-value">$load_avg</span>
                </div>
            </div>

            <!-- CPU Information Card -->
            <div class="card">
                <div class="card-header">
                    <span class="card-icon">🖥️</span>
                    <span class="card-title">CPU Information</span>
                </div>
                <div class="metric">
                    <span class="metric-label">CPU Cores</span>
                    <span class="metric-value">$cpu_count</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Current Usage</span>
                    <span class="metric-value">$cpu_usage</span>
                </div>
                <div class="chart-container">
                    <canvas id="cpuChart"></canvas>
                </div>
            </div>

            <!-- Memory Information Card -->
            <div class="card">
                <div class="card-header">
                    <span class="card-icon">💾</span>
                    <span class="card-title">Memory Information</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Memory Usage</span>
                    <span class="metric-value">${memory_percent}%</span>
                </div>
                <div class="progress-bar">
                    <div class="progress-fill progress-$([ ${memory_percent%%.*} -lt 70 ] && echo "low" || ([ ${memory_percent%%.*} -lt 85 ] && echo "medium" || echo "high"))" style="width: ${memory_percent}%"></div>
                </div>
                <div class="metric">
                    <span class="metric-label">Details</span>
                    <span class="metric-value" style="font-size: 0.9em;">$memory_info</span>
                </div>
            </div>

            <!-- Storage Information Card -->
            <div class="card">
                <div class="card-header">
                    <span class="card-icon">💽</span>
                    <span class="card-title">Storage Information</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Root Partition Usage</span>
                    <span class="metric-value">${disk_percent}%</span>
                </div>
                <div class="progress-bar">
                    <div class="progress-fill progress-$([ ${disk_percent} -lt 70 ] && echo "low" || ([ ${disk_percent} -lt 85 ] && echo "medium" || echo "high"))" style="width: ${disk_percent}%"></div>
                </div>
                <div class="chart-container">
                    <canvas id="storageChart"></canvas>
                </div>
            </div>
EOF

    # Add IP addresses
    local ip_addresses=$(get_ip_info | tr '\n' ', ' | sed 's/,$//')
    
    cat >> "$output_file" << EOF
            <!-- Network Information Card -->
            <div class="card">
                <div class="card-header">
                    <span class="card-icon">🌐</span>
                    <span class="card-title">Network Information</span>
                </div>
                <div class="metric">
                    <span class="metric-label">IP Addresses</span>
                    <span class="metric-value" style="font-size: 0.9em;">$ip_addresses</span>
                </div>
            </div>

            <!-- Alerts Card -->
            <div class="card">
                <div class="card-header">
                    <span class="card-icon">⚠️</span>
                    <span class="card-title">System Alerts</span>
                </div>
EOF

    if [ "$TOTAL_WARNINGS" -eq 0 ] && [ "$TOTAL_ERRORS" -eq 0 ]; then
        cat >> "$output_file" << 'EOF'
                <div class="alert alert-success">
                    <span>✅ All systems operating normally</span>
                </div>
EOF
    else
        if [ "$TOTAL_WARNINGS" -gt 0 ]; then
            cat >> "$output_file" << EOF
                <div class="alert alert-warning">
                    <span>⚠️ $TOTAL_WARNINGS warning(s) detected</span>
                </div>
EOF
        fi
        if [ "$TOTAL_ERRORS" -gt 0 ]; then
            cat >> "$output_file" << EOF
                <div class="alert alert-error">
                    <span>❌ $TOTAL_ERRORS error(s) detected</span>
                </div>
EOF
        fi
    fi

    cat >> "$output_file" << EOF
            </div>
        </div>

        <div class="footer">
            <p>Generated by Advanced Server Information Report Tool v2.0</p>
            <p>Report ID: $report_id | $(date)</p>
        </div>
    </div>

    <script>
        // CPU Usage Chart
        const cpuCtx = document.getElementById('cpuChart').getContext('2d');
        new Chart(cpuCtx, {
            type: 'doughnut',
            data: {
                labels: ['Used', 'Available'],
                datasets: [{
                    data: [25, 75], // Sample data
                    backgroundColor: [
                        'rgba(231, 76, 60, 0.8)',
                        'rgba(46, 204, 113, 0.8)'
                    ],
                    borderWidth: 0
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        position: 'bottom'
                    }
                }
            }
        });

        // Storage Usage Chart
        const storageCtx = document.getElementById('storageChart').getContext('2d');
        new Chart(storageCtx, {
            type: 'bar',
            data: {
                labels: ['Root Partition'],
                datasets: [{
                    label: 'Used %',
                    data: [$disk_percent],
                    backgroundColor: '$disk_percent' > 80 ? 'rgba(231, 76, 60, 0.8)' : '$disk_percent' > 70 ? 'rgba(243, 156, 18, 0.8)' : 'rgba(46, 204, 113, 0.8)',
                    borderWidth: 0,
                    borderRadius: 5
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        max: 100,
                        ticks: {
                            callback: function(value) {
                                return value + '%';
                            }
                        }
                    }
                },
                plugins: {
                    legend: {
                        display: false
                    }
                }
            }
        });
    </script>
</body>
</html>
EOF

    echo -e "${GREEN}HTML report generated: $output_file${NC}"
}
