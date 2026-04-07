# cboot 安装脚本
# 将示例配置复制到 ~/.claude/ 目录

$ErrorActionPreference = "Stop"

$claudeDir = Join-Path $env:USERPROFILE ".claude"

# 检查 .claude 目录是否存在
if (-not (Test-Path $claudeDir)) {
    Write-Host "创建 .claude 目录: $claudeDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

# 复制启动器配置
$exampleConfig = Join-Path $PSScriptRoot "config\claude-config.example.json"
$targetConfig = Join-Path $claudeDir "claude-config.json"

if (Test-Path $targetConfig) {
    Write-Host "配置文件已存在: $targetConfig" -ForegroundColor Yellow
    Write-Host "跳过覆盖，请手动合并配置。" -ForegroundColor Yellow
} else {
    Copy-Item $exampleConfig $targetConfig
    Write-Host "已复制启动器配置: claude-config.json" -ForegroundColor Green
}

# 复制 settings 文件
$settingsDir = Join-Path $PSScriptRoot "config\settings"
$settingsFiles = Get-ChildItem -Path $settingsDir -Filter "*.example.json"

foreach ($file in $settingsFiles) {
    # 去掉 .example 后缀
    $targetName = $file.Name -replace '\.example\.json$', '.json'
    $targetPath = Join-Path $claudeDir $targetName

    if (Test-Path $targetPath) {
        Write-Host "配置文件已存在: $targetName - 跳过" -ForegroundColor Yellow
    } else {
        Copy-Item $file.FullName $targetPath
        Write-Host "已复制模型配置: $targetName" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=== 安装完成 ===" -ForegroundColor Green
Write-Host ""
Write-Host "请编辑以下文件，填入你的 API Key:" -ForegroundColor Yellow
Write-Host "  $claudeDir\claude-config.json" -ForegroundColor White
Write-Host ""
Write-Host "请编辑每个 settings-*.json 文件，替换 YOUR_API_KEY_HERE 为你的 API Key" -ForegroundColor Yellow
Write-Host ""
Write-Host "然后运行 cboot.ps1 启动 Claude Code!" -ForegroundColor Cyan
