# 北航校园网登录脚本

北航校园网登录网址 `gw.buaa.edu.cn` 采用了 `SRun` 深澜认证计费系统，本项目 `buaa_gateway_login.py` 提供了最小化登录脚本，直接运行即可在控制台模拟 Web 端的登录。

# 配置凭据

登录凭据通过环境变量传入，也可以在交互模式下手动输入：

```bash
export BUAA_USERNAME="by1234567"
export BUAA_PASSWORD="your_password"

# Prerequisite: install requests library
python3 -m pip install requests

# Run
python3 buaa_gateway_login.py
```

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
# 单次检测（需要指定Python路径）
.\auto_reconnect.ps1 -PythonExe "path\to\python.exe"
```

### 配置定时任务

**推荐方式：使用SYSTEM账户（完全不显示窗口）**

1. **设置系统级环境变量**（存储登录凭据）：

```powershell
# 使用Machine级别（SYSTEM账户可访问）
[System.Environment]::SetEnvironmentVariable("BUAA_USERNAME", "by1234567", "Machine")
[System.Environment]::SetEnvironmentVariable("BUAA_PASSWORD", "your_password", "Machine")
```

2. **创建定时任务**（每 5 分钟检测一次）：

```powershell
# 删除旧任务（如果存在）
Unregister-ScheduledTask -TaskName "BUAA Gateway Auto-Reconnect" -Confirm:$false -ErrorAction SilentlyContinue

# 创建后台任务（使用SYSTEM账户）
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"path\to\auto_reconnect.ps1`" -PythonExe `"path\to\python.exe`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5)
$settings = New-ScheduledTaskSettingsSet -Hidden -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "BUAA Gateway Auto-Reconnect" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Automatically re-login BUAA campus network gateway" -Force
```

**说明：**
- 使用SYSTEM账户运行，任务在后台 Session 0 执行，**完全不显示窗口**
- 环境变量必须设置为 Machine 级别（ SYSTEM 账户无法访问 User 级别变量）
- 请将命令中的路径修改为你实际的 Python 安装路径和脚本存放路径
- 需要**管理员权限**执行以上命令
