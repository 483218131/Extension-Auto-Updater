# ========== 强制全局使用 UTF-8 编码 ==========
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
[System.Console]::CursorVisible = $false
& chcp 65001 > $null
[System.Console]::CursorVisible = $true
# =============================================

# ========== 1. 读取配置文件 ==========
# 获取当前脚本所在的目录
$scriptPath = $PSScriptRoot
$configFile = Join-Path -Path $scriptPath -ChildPath "config.json"

if (!(Test-Path $configFile)) {
    Write-Host "❌ 错误: 找不到配置文件 config.json！请确保它和脚本在同一个文件夹下。" -ForegroundColor Red
    Pause
    Exit
}

Write-Host "加载配置文件: $configFile" -ForegroundColor DarkGray
# 指定以 UTF8 读取，防止 JSON 里的中文路径乱码
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
            Set-Location $path
            git pull
            
            Write-Host "⏳ 正在安装依赖 (npm install)..." -ForegroundColor Yellow
            npm install --legacy-peer-deps | Out-Null
            
            Write-Host "⏳ 正在编译打包 (npm run build)..." -ForegroundColor Yellow
            npm run build | Out-Null
            
            Write-Host "OK: 构建完成" -ForegroundColor Green
        } else {
            Write-Host "警告: 找不到路径 $path" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "没有配置需要构建的扩展，跳过。" -ForegroundColor DarkGray
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
            Write-Host "跳过: 已是最新版本、API限制或网络问题" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "没有配置需要下载 Release 的扩展，跳过。" -ForegroundColor DarkGray
}

# ========== FINISH ==========
Write-Host "`n=== 所有任务执行完毕 ===" -ForegroundColor Green
Write-Host "请在 edge://extensions/ 或 chrome://extensions/ 中重新加载扩展" -ForegroundColor White
Write-Host "`n按任意键退出..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")