# 系统监控脚本 - Windows 版本 (PowerShell)
# 需要管理员权限运行以获取完整信息

param(
    [string]$HistoryDir = "$env:USERPROFILE\.openclaw\skills\skill-system-monitor\history"
)

$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$Date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$Hostname = $env:COMPUTERNAME
$Uptime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
$UptimeSpan = (Get-Date) - $Uptime
$UptimeStr = "$($UptimeSpan.Days)天 $($UptimeSpan.Hours)小时 $($UptimeSpan.Minutes)分钟"

# 硬盘信息
$Disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" | Select-Object @{N='Total';E={[math]::Round($_.Size/1GB,1)}}, @{N='Free';E={[math]::Round($_.FreeSpace/1GB,1)}}, @{N='Used';E={[math]::Round(($_.Size - $_.FreeSpace)/1GB,1)}}
$DiskTotal = "$($Disk.Total)G"
$DiskUsed = "$($Disk.Used)G"
$DiskFree = "$($Disk.Free)G"
$DiskPercent = [math]::Round((($Disk.Total - $Disk.Free) / $Disk.Total) * 100)

# 内存信息
$OS = Get-CimInstance -ClassName Win32_OperatingSystem
$MemTotal = [math]::Round($OS.TotalVisibleMemorySize / 1MB, 1)
$MemFree = [math]::Round($OS.FreePhysicalMemory / 1MB, 1)
$MemUsed = [math]::Round($MemTotal - $MemFree, 1)
$MemPercent = [math]::Round(($MemUsed / $MemTotal) * 100)

# CPU 信息
$CPU = Get-CimInstance -ClassName Win32_Processor
$CPUCores = $CPU.NumberOfLogicalProcessors
$CPULoad = $CPU.LoadPercentage

# 网络流量
$Network = Get-CimInstance -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface | Where-Object { $_.Name -notlike "*Loopback*" } | Select-Object -First 1
$NetRx = [math]::Round($Network.BytesReceivedPersec / 1MB, 1)
$NetTx = [math]::Round($Network.BytesSentPersec / 1MB, 1)

# 进程 TOP 5 (内存)
$TopProcesses = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 | ForEach-Object {
    "{0,-25} {1,8} ({2}%)" -f $_.ProcessName.Substring(0, [Math]::Min(25, $_.ProcessName.Length)), "$([math]::Round($_.WorkingSet64/1MB,1))M", [math]::Round($_.WorkingSet64 / $OS.TotalVisibleMemorySize * 100, 1)
}

# 判断状态函数
function Get-DiskStatus {
    param([int]$Percent)
    if ($Percent -lt 70) { return "✅正常" }
    elseif ($Percent -lt 85) { return "⚠️警告" }
    else { return "🔴危险" }
}

function Get-MemStatus {
    param([int]$Percent)
    if ($Percent -lt 70) { return "✅正常" }
    elseif ($Percent -lt 85) { return "⚠️警告" }
    else { return "🔴危险" }
}

function Get-CPUStatus {
    param([int]$Load)
    if ($Load -lt 70) { return "✅正常" }
    elseif ($Load -lt 90) { return "⚠️警告" }
    else { return "🔴危险" }
}

$DiskStatus = Get-DiskStatus -Percent $DiskPercent
$MemStatus = Get-MemStatus -Percent $MemPercent
$CPUStatus = Get-CPUStatus -Load $CPULoad

# 关键服务状态
function Check-Service {
    param([string]$Name)
    try {
        $Service = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($Service.Status -eq "Running") { return "✅" }
        else { return "❌" }
    }
    catch {
        return "❓"
    }
}

$Services = @{
    "MSSQL`$SQLEXPRESS" = "SQL Server"
    "mysql" = "MySQL"
    "postgresql*" = "PostgreSQL"
    "Docker*" = "Docker"
    "nginx" = "Nginx"
    "wuauserv" = "Windows Update"
}

$ServicesStatus = ""
foreach ($svc in $Services.GetEnumerator()) {
    $status = Check-Service -Name $svc.Key
    $ServicesStatus += "$($svc.Value): $status | "
}
$ServicesStatus = $ServicesStatus.TrimEnd(" | ")

# 预警信息
$Warnings = @()
if ($DiskPercent -ge 85) {
    $Warnings += "🔴 硬盘使用率过高 ($DiskPercent%)"
} elseif ($DiskPercent -ge 70) {
    $Warnings += "⚠️ 硬盘使用率偏高 ($DiskPercent%)"
}

if ($MemPercent -ge 85) {
    $Warnings += "🔴 内存使用率过高 ($MemPercent%)"
} elseif ($MemPercent -ge 70) {
    $Warnings += "⚠️ 内存使用率偏高 ($MemPercent%)"
}

if ($CPULoad -ge 90) {
    $Warnings += "🔴 CPU 使用率过高 ($CPULoad%)"
}

# 生成报告
$Report = @"
📊 系统监控报告 (Windows)
==================
主机: $Hostname
时间: $Date
运行时间: $UptimeStr

💾 硬盘状态
总容量: $DiskTotal | 已用: $DiskUsed ($DiskPercent%) | 可用: $DiskFree
状态: $DiskStatus

🧠 内存状态
总内存: ${MemTotal}G | 已用: ${MemUsed}G ($MemPercent%) | 可用: ${MemFree}G
状态: $MemStatus

⚙️ CPU 负载 ($CPUCores 核)
使用率: $CPULoad%
状态: $CPUStatus

🌐 网络流量
接收: $NetRx MB/s | 发送: $NetTx MB/s

🔧 关键服务
$ServicesStatus

🔴 资源占用 TOP 5 (内存)
$($TopProcesses -join "`n")
"@

if ($Warnings.Count -gt 0) {
    $Report += @"

⚠️ 预警信息
$($Warnings -join "`n")
"@
}

# 保存历史记录
New-Item -ItemType Directory -Force -Path $HistoryDir | Out-Null
$Report | Out-File -FilePath "$HistoryDir\$Timestamp.log" -Encoding UTF8

# 保存 JSON 格式
$JsonData = @{
    timestamp = $Date
    system = "windows"
    uptime = $UptimeStr
    disk = @{
        total = $DiskTotal
        used = $DiskUsed
        available = $DiskFree
        percent = $DiskPercent
    }
    memory = @{
        total_gb = $MemTotal
        used_gb = $MemUsed
        available_gb = $MemFree
        percent = $MemPercent
    }
    cpu = @{
        load_percent = $CPULoad
        cores = $CPUCores
    }
    network = @{
        rx_mbps = $NetRx
        tx_mbps = $NetTx
    }
}

$JsonData | ConvertTo-Json | Out-File -FilePath "$HistoryDir\$Timestamp.json" -Encoding UTF8

Write-Output $Report
