# ========== 强制全局使用 UTF-8 编码 ==========
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
# =============================================

Write-Host "=== 正在配置 Windows 计划任务 ===" -ForegroundColor Cyan

# 1. 检查管理员权限 (创建计划任务需要管理员权限)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "⚠️ 需要管理员权限来创建计划任务。" -ForegroundColor Yellow
    Write-Host "正在请求提权，请在弹出的窗口中点击'是'..." -ForegroundColor White
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

# 2. 定义任务参数
$taskName = "Extension-Auto-Updater"
$taskDescription = "每天自动拉取并编译最新的浏览器扩展程序。"
$scriptPath = Join-Path -Path $PSScriptRoot -ChildPath "update_extensions.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Host "❌ 错误: 找不到核心脚本 update_extensions.ps1" -ForegroundColor Red
    Pause
    Exit
}

# 3. 配置触发器和操作
# 触发器：每天中午 12:00 运行
$trigger = New-ScheduledTaskTrigger -Daily -At 12:00PM
# 操作：使用 PowerShell 隐式运行更新脚本 (-WindowStyle Hidden 表示后台静默运行，不弹黑框)
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`""
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# 4. 注册计划任务 (如果已存在则覆盖)
try {
    Register-ScheduledTask -TaskName $taskName -Description $taskDescription -Trigger $trigger -Action $action -Settings $settings -Force | Out-Null
    Write-Host "✅ 成功！计划任务 [$taskName] 已创建。" -ForegroundColor Green
    Write-Host "👉 触发时间: 每天 12:00 (后台静默运行)" -ForegroundColor DarkGray
    Write-Host "👉 目标脚本: $scriptPath" -ForegroundColor DarkGray
    Write-Host "`n(如果需要修改时间或删除任务，请在 Windows 搜索栏输入'任务计划程序'进行管理)" -ForegroundColor Yellow
} catch {
    Write-Host "❌ 创建计划任务失败: $_" -ForegroundColor Red
}

Write-Host "`n按任意键退出..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")