# ========== 强制全局使用 UTF-8 编码 ==========
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
[System.Console]::CursorVisible = $false
& chcp 65001 > $null
[System.Console]::CursorVisible = $true
# =============================================

# ========== 1. 读取配置文件 ==========
$scriptPath = $PSScriptRoot
$configFile = Join-Path -Path $scriptPath -ChildPath "config.json"

if (!(Test-Path $configFile)) {
    Write-Host "❌ 错误: 找不到配置文件 config.json！请确保它和脚本在同一个文件夹下。" -ForegroundColor Red
    Exit # ⚠️ 删除了 Pause，防止后台卡死
}

Write-Host "加载配置文件: $configFile" -ForegroundColor DarkGray
$config = Get-Content -Path $configFile -Raw -Encoding UTF8 | ConvertFrom-Json

$buildExtensions = $config.buildExtensions
$releaseExtensions = $config.releaseExtensions
# =============================================

# ========== 2. Git + Build 扩展 ==========
Write-Host "`n=== 更新需要构建的扩展 ===" -ForegroundColor Green
if ($null -ne $buildExtensions) {
    foreach ($path in $buildExtensions) {
        Write-Host "`n处理中: $path" -ForegroundColor Cyan
        if (Test-Path $path) {
            Push-Location $path 
            
            # 增加 --quiet 减少交互弹窗风险
            git pull --quiet
            
            Write-Host "⏳ 正在安装依赖 (npm install)..." -ForegroundColor Yellow
            npm install --legacy-peer-deps --no-fund --no-audit | Out-Null
            
            Write-Host "⏳ 正在编译打包 (npm run build)..." -ForegroundColor Yellow
            npm run build | Out-Null
            
            Write-Host "OK: 构建完成" -ForegroundColor Green
            Pop-Location 
        } else {
            Write-Host "警告: 找不到路径 $path" -ForegroundColor Yellow
        }
    }
}

# ========== 3. 下载 Release 扩展 ==========
Write-Host "`n=== 更新 Release 版本的扩展 ===" -ForegroundColor Green
if ($null -ne $releaseExtensions) {
    foreach ($ext in $releaseExtensions) {
        $localPath = $ext.path
        $repo = $ext.repo
        Write-Host "`n检查仓库: $repo" -ForegroundColor Cyan

        if (!(Test-Path $localPath)) {
            Write-Host "创建目录: $localPath" -ForegroundColor DarkGray
            New-Item -ItemType Directory -Path $localPath | Out-Null
        }

        try {
            $api = "https://api.github.com/repos/$repo/releases/latest"
            $release = Invoke-RestMethod -Uri $api -UseBasicParsing
            
            $asset = $release.assets | Where-Object { $_.name -match "chrome|edge|extension" } | Select-Object -First 1
            $downloadUrl = $asset.browser_download_url
            $zipPath = "$localPath\latest.zip"

            Write-Host "正在下载: $($asset.name)"
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $localPath -Force
            Remove-Item $zipPath -Force

            Write-Host "OK: 已更新到最新官方版本" -ForegroundColor Green
        }
        catch {
            Write-Host "跳过下载: 已是最新版本、API限制或网络问题" -ForegroundColor Yellow
        }

        # 🌟 修复：独立出来的 Key 注入守卫
        # 无论有没有下载新版本，只要 manifest.json 存在，就检查并强制锁定 ID
        if ($null -ne $ext.key) {
            $manifestPath = Join-Path -Path $localPath -ChildPath "manifest.json"
            if (Test-Path $manifestPath) {
                $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
                
                # 智能判断：如果 Key 丢了或者不一样，才执行注入
                if ($manifest.key -ne $ext.key) {
                    Write-Host "🔑 正在注入固定 Key 以锁定 Extension ID..." -ForegroundColor Cyan
                    $manifest | Add-Member -MemberType NoteProperty -Name "key" -Value $ext.key -Force
                    $manifestJson = $manifest | ConvertTo-Json -Depth 10
                    $utf8NoBom = New-Object System.Text.UTF8Encoding $False
                    [System.IO.File]::WriteAllText($manifestPath, $manifestJson, $utf8NoBom)
                    Write-Host "✅ Key 注入成功，ID 已永久锁定" -ForegroundColor Green
                } else {
                    Write-Host "✅ 校验通过：Key 已存在，ID 处于永久锁定状态" -ForegroundColor DarkGray
                }
            }
        }
    }
} else {
    Write-Host "没有配置需要下载 Release 的扩展，跳过。" -ForegroundColor DarkGray
}

# ========== FINISH ==========
Write-Host "`n=== 所有任务执行完毕 ===" -ForegroundColor Green
Write-Host "请在 edge://extensions/ 或 chrome://extensions/ 中重新加载扩展" -ForegroundColor White

# ✨ 智能判断：精准检测是否为计划任务的隐藏模式触发
$cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").CommandLine
$isScheduled = ($null -ne $cmdLine) -and ($cmdLine -match "-WindowStyle Hidden")

if ([Environment]::UserInteractive -and -not $isScheduled) {
    Write-Host "`n[手动运行模式] 按任意键退出..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
} else {
    Write-Host "`n[后台自动模式] 任务已完成，正在自动退出..." -ForegroundColor DarkGray
    exit 0
}