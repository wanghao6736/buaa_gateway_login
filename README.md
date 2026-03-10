# 北航校园网登录脚本

北航校园网登录网址gw.buaa.edu.cn采用了SRun深澜认证计费系统，本项目buaa_gateway_login.py提供了最小化登录脚本，直接运行即可在控制台模拟Web端的登录。

# 配置凭据

登录凭据通过环境变量传入，也可以在交互模式下手动输入：

```bash
export BUAA_USERNAME="by1234567"
export BUAA_PASSWORD="your_password"
python3 buaa_gateway_login.py
```

如果不设置环境变量，脚本会提示手动输入用户名和密码。

# 自动重连

项目提供了 `auto_reconnect.sh`（Linux）和 `auto_reconnect.ps1`（Windows）两个自动重连脚本。  
脚本通过访问百度检测网络连接——若被重定向到 `gw.buaa.edu.cn`，说明需要登录，脚本会自动调用登录程序。

## Linux

### 手动运行

```bash
# 单次检测
./auto_reconnect.sh

# 循环模式，默认每 600 秒检测一次
./auto_reconnect.sh --loop

# 自定义间隔（秒）
./auto_reconnect.sh --loop 300
```

### 通过 systemd 配置定时任务

1. 将项目文件复制到 `/usr/local/bin/`：

```bash
sudo cp buaa_gateway_login.py auto_reconnect.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/auto_reconnect.sh
```

2. 创建 systemd 服务 `/etc/systemd/system/buaa_gateway_login.service`：

```ini
[Unit]
Description=BUAA gateway auto-reconnect

[Service]
Type=oneshot
ExecStart=/usr/local/bin/auto_reconnect.sh
Environment="BUAA_USERNAME=by1234567"
Environment="BUAA_PASSWORD=your_password"
```

3. 创建定时器 `/etc/systemd/system/buaa_gateway_login.timer`（每 10 分钟执行一次）：

```ini
[Unit]
Description=BUAA gateway auto-reconnect timer

[Timer]
OnCalendar=*-*-* *:0/10:0
Persistent=true

[Install]
WantedBy=timers.target
```

4. 启动定时器：

```bash
sudo systemctl enable --now buaa_gateway_login.timer
```

为保证安全，以上文件属主建议设为 root。

## Windows

### 手动运行

```powershell
# 单次检测
.\auto_reconnect.ps1

# 循环模式，默认每 600 秒检测一次
.\auto_reconnect.ps1 -Loop

# 自定义间隔（秒）
.\auto_reconnect.ps1 -Loop -Interval 300
```

### 通过任务计划程序配置定时任务

1. 设置环境变量（管理员 PowerShell）：

```powershell
[System.Environment]::SetEnvironmentVariable("BUAA_USERNAME", "by1234567", "User")
[System.Environment]::SetEnvironmentVariable("BUAA_PASSWORD", "your_password", "User")
```

2. 创建计划任务（每 10 分钟执行一次）：

```powershell
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -File C:\path\to\auto_reconnect.ps1 *>> C:\path\to\auto_reconnect.log"

$trigger = New-ScheduledTaskTrigger `
    -RepetitionInterval (New-TimeSpan -Minutes 10) `
    -Once -At (Get-Date)

Register-ScheduledTask `
    -TaskName "BUAA Gateway Auto-Reconnect" `
    -Action $action -Trigger $trigger `
    -Description "Automatically re-login BUAA campus network gateway"
```

