# ============================================
# 🔧 可配置项 - 在这里修改你的配置路径
# ============================================
# 默认使用用户目录下的 .claude 目录
# 如需使用其他路径，修改下面的值：
$CUSTOM_CONFIG_DIR = "$env:USERPROFILE\.claude"
# ============================================

# 确定配置目录
$CONFIG_DIR = $CUSTOM_CONFIG_DIR

$configPath = Join-Path $CONFIG_DIR "claude-config.json"

# CLI 参数直启（-Model/-Project/-Permission 跳过菜单；cboot.cmd 的 %* 经 $args 端到端透传）
$script:DirectLaunchArgs = $null
if ($args.Count -gt 0) {
    $dl = @{ model = $null; project = $null; permission = $null }
    for ($i = 0; $i -lt $args.Count; $i++) {
        $a = [string]$args[$i]
        if ($a -ieq '-Model') { $i++; if ($i -lt $args.Count) { $dl.model = [string]$args[$i] } }
        elseif ($a -ieq '-Project') { $i++; if ($i -lt $args.Count) { $dl.project = [string]$args[$i] } }
        elseif ($a -ieq '-Permission') { $i++; if ($i -lt $args.Count) { $dl.permission = [string]$args[$i] } }
        else { Write-Warning "未知参数: $a（支持 -Model/-Project/-Permission）" }
    }
    $script:DirectLaunchArgs = $dl
}

# 格式化 JSON：2 空格缩进，冒号后单空格
function Format-Json {
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline=$true)][string]$Json)
    process {
        $Json = $Json -replace ':  +', ': '
        $indent = 0
        $result = @()
        foreach ($line in ($Json -split "`r?`n")) {
            $t = $line.Trim()
            if ($t.Length -eq 0) { continue }
            if ($t -match '^[}\]]') { $indent = [Math]::Max(0, $indent - 1) }
            $result += ('  ' * $indent) + $t
            if ($t -match '[{\[]\s*$' -and $t -notmatch '[}\]]') { $indent++ }
        }
        ($result -join "`r`n") + "`r`n"
    }
}

# 读取键盘输入的函数（支持循环选择）
function Read-KeyInput {
    param(
        [int]$selectedIndex,
        [int]$maxIndex
    )

    while ($true) {
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        switch ($key.VirtualKeyCode) {
            38 { # 向上箭头
                if ($selectedIndex -gt 0) {
                    $selectedIndex--
                } else {
                    $selectedIndex = $maxIndex
                }
                return $selectedIndex, $false
            }
            40 { # 向下箭头
                if ($selectedIndex -lt $maxIndex) {
                    $selectedIndex++
                } else {
                    $selectedIndex = 0
                }
                return $selectedIndex, $false
            }
            13 { # 回车键
                return $selectedIndex, $true
            }
            27 { # ESC键
                return -1, $true
            }
            72 { # H键
                return -2, $true
            }
        }
    }
}

# 读取配置
function Get-Config {
    try {
        $configContent = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
        return ConvertFrom-Json $configContent
    } catch {
        return $null
    }
}

# 保存配置
function Save-Config {
    param($config)
    try {
        $configJson = $config | ConvertTo-Json -Depth 10 | Format-Json
        Set-Content -LiteralPath $configPath -Value $configJson -Encoding UTF8
    } catch {
        # 静默失败
    }
}

# 删除配置文件及关联的 settings 文件
function Remove-ConfigAndSettings {
    param([string]$configFilePath)
    $cfg = $null
    try {
        $cfg = Get-Content -LiteralPath $configFilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {}
    if ($cfg -and $cfg.models) {
        foreach ($m in $cfg.models) {
            if ($m.configFile) {
                $settingsPath = Join-Path $CONFIG_DIR $m.configFile
                Remove-Item -LiteralPath $settingsPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Remove-Item -LiteralPath $configFilePath -Force -ErrorAction SilentlyContinue
}

# 自定义输入函数：支持空行取消（返回 $null 表示取消）
function Read-HostWithCancel {
    param(
        [string]$prompt,
        [string]$defaultValue = $null
    )

    Write-Host $prompt -NoNewline -ForegroundColor Yellow
    if ($defaultValue) {
        Write-Host " [默认: $defaultValue]" -NoNewline -ForegroundColor DarkGray
    }
    Write-Host ": "

    $userInput = Read-Host

    # 空行处理
    if ([string]::IsNullOrWhiteSpace($userInput)) {
        if ($defaultValue) {
            return $defaultValue
        }
        # 无默认值时，空行表示取消
        return $null
    }

    return $userInput
}

# 确认取消操作
function Confirm-Cancel {
    $selectedIndex = 0
    $selected = $false

    while (-not $selected) {
        Clear-Host
        Write-Host "确认取消?" -ForegroundColor Yellow
        Write-Host ""
        if ($selectedIndex -eq 0) {
            Write-Host "  是，取消操作" -ForegroundColor Green -BackgroundColor Black
            Write-Host "  否，继续输入" -ForegroundColor White
        } else {
            Write-Host "  是，取消操作" -ForegroundColor Red
            Write-Host "  否，继续输入" -ForegroundColor Green -BackgroundColor Black
        }
        Write-Host ""
        Write-Host "使用方向键导航，回车选择" -ForegroundColor Gray

        $selectedIndex, $selected = Read-KeyInput -selectedIndex $selectedIndex -maxIndex 1
        if ($selected -and $selectedIndex -eq -1) { return $false }
    }

    return ($selectedIndex -eq 0)
}

# 解析上下文窗口大小
function Parse-ContextWindow {
    param([string]$ContextInput)

    if ([string]::IsNullOrWhiteSpace($ContextInput)) {
        return @{ size = 1000000; original = "1M" }
    }

    $ContextInput = $ContextInput.Trim().ToUpper()

    if ($ContextInput -match '^(\d+(?:\.\d+)?)\s*K$') {
        $value = [double]$Matches[1]
        return @{ size = [math]::Floor($value * 1000); original = "$($value)K" }
    }

    if ($ContextInput -match '^(\d+(?:\.\d+)?)\s*M$') {
        $value = [double]$Matches[1]
        return @{ size = [math]::Floor($value * 1000000); original = "$($value)M" }
    }

    return $null
}

# 按上下文窗口大小设置/移除 1M 相关 env 字段（兼容 hashtable 与 PSCustomObject）
# 语义（2026-10-28 验证记录，见 docs/reports）：
#   - CLAUDE_CODE_DISABLE_1M_CONTEXT=1 会把 1M 原生模型的有效窗口压回 200K，并与 AUTO_COMPACT_WINDOW 组合出「窗口 200K 而压缩阈值 500K」的矛盾配置
#   - 仅当用户显式选择 200K 时写 DISABLE_1M_CONTEXT 并清除 AUTO_COMPACT_WINDOW（压缩阈值交回默认逻辑）
#   - 其余窗口只写 AUTO_COMPACT_WINDOW=size（压缩阈值=窗口大小，1M 能力保留）
function Set-ContextWindowEnv {
    param(
        [object]$EnvObject,
        [int]$ContextWindowSize
    )

    if ($EnvObject -is [hashtable]) {
        # hashtable 类型：通过 key 索引赋值，Remove 移除
        if ($ContextWindowSize -eq 200000) {
            $EnvObject['CLAUDE_CODE_DISABLE_1M_CONTEXT'] = "1"
            $EnvObject.Remove('CLAUDE_CODE_AUTO_COMPACT_WINDOW') | Out-Null
        } else {
            $EnvObject.Remove('CLAUDE_CODE_DISABLE_1M_CONTEXT') | Out-Null
            $EnvObject['CLAUDE_CODE_AUTO_COMPACT_WINDOW'] = "$ContextWindowSize"
        }
    } else {
        # PSCustomObject 类型：Add-Member -Force 覆盖属性，PSObject.Properties 判存在后 Remove
        if ($ContextWindowSize -eq 200000) {
            $EnvObject | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_DISABLE_1M_CONTEXT' -Value "1" -Force
            if ($EnvObject.PSObject.Properties['CLAUDE_CODE_AUTO_COMPACT_WINDOW']) {
                $EnvObject.PSObject.Properties.Remove('CLAUDE_CODE_AUTO_COMPACT_WINDOW')
            }
        } else {
            if ($EnvObject.PSObject.Properties['CLAUDE_CODE_DISABLE_1M_CONTEXT']) {
                $EnvObject.PSObject.Properties.Remove('CLAUDE_CODE_DISABLE_1M_CONTEXT')
            }
            $EnvObject | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_AUTO_COMPACT_WINDOW' -Value "$ContextWindowSize" -Force
        }
    }
}

# 生成 settings 模板文件
function New-SettingsTemplate {
    param(
        [string]$modelId,
        [string]$configFile,
        [string]$authToken,
        [string]$baseUrl,
        [string]$opusModel,
        [string]$sonnetModel,
        [string]$haikuModel,
        [string]$subagentModel = $null,
        [int]$contextWindowSize = 1000000
    )

    $settingsPath = Join-Path $CONFIG_DIR $configFile

    # 1. 查找已有 settings 文件作为模板
    $templatePath = $null
    $templateFiles = Get-ChildItem -Path $CONFIG_DIR -Filter "settings-*.json" -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -ne $configFile }

    if ($templateFiles) {
        $templatePath = $templateFiles[0].FullName
    }

    # 2. 读取模板或使用硬编码模板
    if ($templatePath -and (Test-Path -LiteralPath $templatePath)) {
        try {
            $templateContent = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
            $template = $templateContent | ConvertFrom-Json
        } catch {
            # 模板读取失败，fallback 到硬编码
            $template = $null
        }
    }

    # 3. 无模板时 fallback 到硬编码模板
    if (-not $template) {
        $template = @{
            hooks = @{
                PostToolUse = @(
                    @{
                        matcher = "Agent|TeamCreate|TaskCreate|TaskUpdate"
                        hooks = @(
                            @{
                                type = "command"
                                command = "ccstatusline"
                                async = $true
                                timeout = 5000
                            }
                        )
                    }
                )
            }
            env = @{
                API_TIMEOUT_MS = "3000000"
                CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1"
                CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1"
                CLAUDE_CODE_ATTRIBUTION_HEADER = "0"
                ENABLE_TOOL_SEARCH = "false"
                # 防止 refusal 时静默切换到官方模型（Claude Code ≥2.1.312 行为，网关用户建议开启）
                CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK = "1"
                CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS = "1"
            }
            permissions = @{
                allow = @(
                    "Bash(ls *)", "Bash(ls)", "Bash(cat *)", "Bash(grep *)",
                    "Bash(find *)", "Bash(mkdir *)", "Bash(cp *)", "Bash(mv *)",
                    "Bash(rm *)", "Bash(touch *)", "Bash(echo *)", "Bash(pwd)",
                    "Bash(which *)", "Bash(git status)", "Bash(git status *)",
                    "Bash(git add *)", "Bash(git commit *)", "Bash(git pull)",
                    "Bash(git push)", "Bash(git branch *)", "Bash(git checkout *)",
                    "Bash(git log *)", "Bash(git diff *)", "Bash(git remote *)",
                    "Bash(mvn *)", "Bash(npm *)", "Bash(node *)", "Bash(curl *)",
                    "Bash(head *)", "Bash(tail *)", "Bash(wc *)", "Bash(sort *)",
                    "Bash(uniq *)", "Bash(sed *)", "Bash(awk *)", "Bash(xargs *)",
                    "Bash(chmod *)", "Bash(java -version)", "Bash(java *)",
                    "Bash(* --help)", "Bash(* --version)", "Bash(* -h)", "Bash(* -v)"
                )
                deny = @(
                    "Bash(rm -rf /*)", "Bash(rm -rf /)", "Bash(dd if=*)",
                    "Bash(> /dev/sda*)", "Bash(mkfs *)"
                )
            }
            enabledPlugins = @{
                "document-skills@anthropic-agent-skills" = $true
                "example-skills@anthropic-agent-skills" = $true
            }
            language = "中文"
            autoUpdatesChannel = "latest"
            skipDangerousModePermissionPrompt = $true
            autoDreamEnabled = $true
            statusLine = @{
                type = "command"
                command = "ccstatusline"
                refreshInterval = 10
            }
        }
    }

    # 4. 替换关键 env 字段
    if (-not $template.env) {
        $template | Add-Member -MemberType NoteProperty -Name "env" -Value @{} -Force
    }

    if ($template.env -is [hashtable]) {
        $template.env['ANTHROPIC_AUTH_TOKEN'] = $authToken
        $template.env['ANTHROPIC_BASE_URL'] = $baseUrl
        $template.env['ANTHROPIC_DEFAULT_OPUS_MODEL'] = $opusModel
        $template.env['ANTHROPIC_DEFAULT_SONNET_MODEL'] = $sonnetModel
        $template.env['ANTHROPIC_DEFAULT_HAIKU_MODEL'] = $haikuModel
    } else {
        $template.env | Add-Member -MemberType NoteProperty -Name 'ANTHROPIC_AUTH_TOKEN' -Value $authToken -Force
        $template.env | Add-Member -MemberType NoteProperty -Name 'ANTHROPIC_BASE_URL' -Value $baseUrl -Force
        $template.env | Add-Member -MemberType NoteProperty -Name 'ANTHROPIC_DEFAULT_OPUS_MODEL' -Value $opusModel -Force
        $template.env | Add-Member -MemberType NoteProperty -Name 'ANTHROPIC_DEFAULT_SONNET_MODEL' -Value $sonnetModel -Force
        $template.env | Add-Member -MemberType NoteProperty -Name 'ANTHROPIC_DEFAULT_HAIKU_MODEL' -Value $haikuModel -Force
    }

    # 套餐标记：statusline 的 custom-command widget 读取此变量显示当前窗口的配置身份
    if ($template.env -is [hashtable]) {
        $template.env['CLAUDE_PROFILE'] = $modelId
    } else {
        $template.env | Add-Member -MemberType NoteProperty -Name 'CLAUDE_PROFILE' -Value $modelId -Force
    }

    # 上下文窗口设置（>=1M 时清除模板可能遗留的字段）
    Set-ContextWindowEnv -EnvObject $template.env -ContextWindowSize $contextWindowSize

    # 子代理模型手动定制通道（Claude Code ≥2.1.257 支持覆盖子代理模型）
    # 值尾加 ! 表示严格生效，同时写入 CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1
    if (-not [string]::IsNullOrWhiteSpace($subagentModel)) {
        $subForce = $subagentModel.EndsWith('!')
        $subValue = if ($subForce) { $subagentModel.TrimEnd('!') } else { $subagentModel }
        if ($template.env -is [hashtable]) {
            $template.env['CLAUDE_CODE_SUBAGENT_MODEL'] = $subValue
            if ($subForce) { $template.env['CLAUDE_CODE_SUBAGENT_MODEL_FORCE'] = "1" }
        } else {
            $template.env | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_SUBAGENT_MODEL' -Value $subValue -Force
            if ($subForce) {
                $template.env | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_SUBAGENT_MODEL_FORCE' -Value "1" -Force
            }
        }
    }

    if ($template -is [hashtable]) {
        $template['model'] = $modelId
    } else {
        $template | Add-Member -MemberType NoteProperty -Name 'model' -Value $modelId -Force
    }

    # 5. 写入文件
    try {
        $templateJson = $template | ConvertTo-Json -Depth 10 | Format-Json
        Set-Content -LiteralPath $settingsPath -Value $templateJson -Encoding UTF8
        return $true
    } catch {
        return $false
    }
}

# 初始化配置文件（交互式引导）
function Initialize-Config {
    while ($true) {
    Clear-Host
    Write-Host "=== 欢迎使用 cboot ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "未找到配置文件，即将引导您完成初始配置。" -ForegroundColor Yellow
    Write-Host "提示: 在输入步骤按回车（空行）可取消，项目路径步骤空行跳过" -ForegroundColor DarkGray
    Write-Host ""

    # 步骤 1/6: 配置模型基础信息
    Write-Host "步骤 1/6: 配置模型基础信息" -ForegroundColor Cyan
    Write-Host ""

    $modelId = Read-HostWithCancel "请输入模型 ID（如 glm-5.2[1m]）"
    if ([string]::IsNullOrWhiteSpace($modelId)) {
        if (Confirm-Cancel) { return }
        while ([string]::IsNullOrWhiteSpace($modelId)) {
            $modelId = Read-Host "请输入模型 ID（如 glm-5.2[1m]）"
            if ([string]::IsNullOrWhiteSpace($modelId)) {
                Write-Host "模型 ID 不能为空!" -ForegroundColor Red
            }
        }
    }

    $modelName = Read-HostWithCancel "请输入模型显示名称（如 glm-5.2[1m]）"
    if ([string]::IsNullOrWhiteSpace($modelName)) {
        if (Confirm-Cancel) { return }
        while ([string]::IsNullOrWhiteSpace($modelName)) {
            $modelName = Read-Host "请输入模型显示名称（如 glm-5.2[1m]）"
            if ([string]::IsNullOrWhiteSpace($modelName)) {
                Write-Host "模型显示名称不能为空!" -ForegroundColor Red
            }
        }
    }

    $configFile = "settings-$modelId.json"
    Write-Host "配置文件名: $configFile" -ForegroundColor Gray
    Write-Host ""

    # 步骤 2/6: 配置 API 参数
    Write-Host "步骤 2/6: 配置 API 参数" -ForegroundColor Cyan
    Write-Host ""

    $authToken = Read-HostWithCancel "请输入 ANTHROPIC_AUTH_TOKEN（API 密钥）"
    if ([string]::IsNullOrWhiteSpace($authToken)) {
        if (Confirm-Cancel) { return }
        while ([string]::IsNullOrWhiteSpace($authToken)) {
            $authToken = Read-Host "请输入 ANTHROPIC_AUTH_TOKEN（API 密钥）"
            if ([string]::IsNullOrWhiteSpace($authToken)) {
                Write-Host "API 密钥不能为空!" -ForegroundColor Red
            }
        }
    }

    $defaultBaseUrl = "https://open.bigmodel.cn/api/anthropic"
    $baseUrl = Read-HostWithCancel "请输入 ANTHROPIC_BASE_URL" -defaultValue $defaultBaseUrl
    if ([string]::IsNullOrWhiteSpace($baseUrl)) { $baseUrl = $defaultBaseUrl }

    $opusModel = Read-HostWithCancel "请输入 ANTHROPIC_DEFAULT_OPUS_MODEL" -defaultValue $modelId
    if ([string]::IsNullOrWhiteSpace($opusModel)) { $opusModel = $modelId }

    $sonnetModel = Read-HostWithCancel "请输入 ANTHROPIC_DEFAULT_SONNET_MODEL" -defaultValue $modelId
    if ([string]::IsNullOrWhiteSpace($sonnetModel)) { $sonnetModel = $modelId }

    $haikuModel = Read-HostWithCancel "请输入 ANTHROPIC_DEFAULT_HAIKU_MODEL（此槽跑后台任务，建议 flash 级模型）" -defaultValue "glm-5.3-flash[1m]"
    if ([string]::IsNullOrWhiteSpace($haikuModel)) { $haikuModel = "glm-5.3-flash[1m]" }

    Write-Host ""

    # 步骤 3/6: 上下文窗口设置
    Write-Host "步骤 3/6: 上下文窗口设置" -ForegroundColor Cyan
    Write-Host ""

    $contextWindowSize = 0
    $contextWindowOriginal = ""

    while ($contextWindowSize -eq 0) {
        $windowInput = Read-Host "请输入上下文窗口大小（如 200K、500K、1M，默认 1M）"

        if ([string]::IsNullOrWhiteSpace($windowInput)) {
            $contextWindowSize = 1000000
            $contextWindowOriginal = "1M"
        } else {
            $parsed = Parse-ContextWindow -ContextInput $windowInput
            if ($parsed) {
                $contextWindowSize = $parsed.size
                $contextWindowOriginal = $parsed.original
            } else {
                Write-Host "无效输入，请重新输入（格式：200K、500K、1M）" -ForegroundColor Red
            }
        }
    }

    Write-Host ""

    # 步骤 4/6: 默认权限
    Write-Host "步骤 4/6: 默认权限" -ForegroundColor Cyan
    Write-Host ""

    $defaultPermission = ""
    while ($defaultPermission -notin @("yes", "no")) {
        $permInput = Read-Host "默认权限模式（Y = bypassPermissions 跳过 Permission 检查 / n = default 手动确认）(Y/n)"
        if ([string]::IsNullOrWhiteSpace($permInput) -or $permInput -eq "y" -or $permInput -eq "Y") {
            $defaultPermission = "yes"
        } elseif ($permInput -eq "n" -or $permInput -eq "N") {
            $defaultPermission = "no"
        } else {
            Write-Host "请输入 Y 或 n" -ForegroundColor Red
        }
    }
    Write-Host ""

    # 步骤 5/6: 项目目录
    Write-Host "步骤 5/6: 项目目录" -ForegroundColor Cyan
    Write-Host ""

    $projectPath = Read-HostWithCancel "请输入项目目录路径（留空跳过）"
    Write-Host ""

    # 确认配置信息
    $confirmIndex = 0
    $confirmSelected = $false

    while (-not $confirmSelected) {
        Clear-Host
        Write-Host "=== 请确认配置信息 ===" -ForegroundColor Green
        Write-Host ""
        Write-Host "  模型 ID:      $modelId" -ForegroundColor White
        Write-Host "  模型名称:     $modelName" -ForegroundColor White
        Write-Host "  配置文件:     $configFile" -ForegroundColor White
        Write-Host ""
        Write-Host "  API 密钥:     $($authToken.Substring(0, [Math]::Min(8, $authToken.Length)))..." -ForegroundColor White
        Write-Host "  Base URL:     $baseUrl" -ForegroundColor White
        Write-Host "  Opus 模型:    $opusModel" -ForegroundColor White
        Write-Host "  Sonnet 模型:  $sonnetModel" -ForegroundColor White
        Write-Host "  Haiku 模型:   $haikuModel" -ForegroundColor White
        Write-Host "  上下文窗口:   $contextWindowOriginal" -ForegroundColor White
        Write-Host ""
        Write-Host "  默认权限:     $(if ($defaultPermission -eq 'yes') { '允许所有操作' } else { '需要确认' })" -ForegroundColor White
        Write-Host "  项目目录:     $(if ([string]::IsNullOrWhiteSpace($projectPath)) { '（未设置）' } else { $projectPath })" -ForegroundColor White
        Write-Host ""
        if ($confirmIndex -eq 0) {
            Write-Host "  确认并保存" -ForegroundColor Green -BackgroundColor Black
            Write-Host "  重新输入" -ForegroundColor White
        } else {
            Write-Host "  确认并保存" -ForegroundColor Yellow
            Write-Host "  重新输入" -ForegroundColor Green -BackgroundColor Black
        }
        Write-Host ""
        Write-Host "使用方向键选择，回车确认" -ForegroundColor Gray

        $confirmIndex, $confirmSelected = Read-KeyInput -selectedIndex $confirmIndex -maxIndex 1
        if ($confirmSelected -and $confirmIndex -eq -1) { $confirmIndex = 1; $confirmSelected = $true }
    }

    if ($confirmIndex -eq 0) { break }
    } # end while

    # 创建配置对象
    $newConfig = @{
        models = @(
            @{
                id = $modelId
                name = $modelName
                configFile = $configFile
                contextWindow = $contextWindowOriginal
                usageCount = 0
            }
        )
        defaultModel = $modelId
        defaultPermission = $defaultPermission
        projects = @()
    }

    # 如果提供了项目路径，添加到配置
    if (-not [string]::IsNullOrWhiteSpace($projectPath)) {
        if (Test-Path -LiteralPath $projectPath -PathType Container) {
            $newConfig.projects += @{
                path = $projectPath
                usageCount = 0
            }
        } else {
            Write-Host "警告: 项目目录不存在，已跳过" -ForegroundColor Yellow
        }
    }

    # 步骤 6/6: 保存配置并生成模板
    Write-Host "步骤 6/6: 保存配置" -ForegroundColor Cyan
    Write-Host ""

    # 保存配置文件
    try {
        $configJson = $newConfig | ConvertTo-Json -Depth 10 | Format-Json
        Set-Content -LiteralPath $configPath -Value $configJson -Encoding UTF8
    } catch {
        Clear-Host
        Write-Host "=== 配置错误 ===" -ForegroundColor Red
        Write-Host ""
        Write-Host "配置文件保存失败: $_" -ForegroundColor Red
        Write-Host ""
        Write-Host "按任意键退出..." -ForegroundColor Yellow
        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit
    }

    # 生成 settings 模板
    $templateCreated = New-SettingsTemplate -modelId $modelId -configFile $configFile `
                                             -authToken $authToken -baseUrl $baseUrl `
                                             -opusModel $opusModel -sonnetModel $sonnetModel -haikuModel $haikuModel `
                                             -contextWindowSize $contextWindowSize

    # 显示完成信息
    Clear-Host
    Write-Host "✅ 配置文件已生成！" -ForegroundColor Green
    Write-Host ""
    if ($templateCreated) {
        Write-Host "已生成 $configFile 模板，API 配置已填入。" -ForegroundColor Green
        Write-Host "配置文件位置: $CONFIG_DIR\$configFile" -ForegroundColor Gray
    } else {
        Write-Host "settings 模板生成失败，请手动创建" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "按任意键继续..." -ForegroundColor Yellow
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Bootstrap：配置加载与验证（缺失字段可逐项修复）+ projects/usageCount 归一化；返回标准化后的配置
function Bootstrap {
    while ($true) {
    if (-not (Test-Path -LiteralPath $configPath)) {
        Initialize-Config
    }

    $config = Get-Config

    # 无法读取 → 只能重新初始化
    if (-not $config) {
        $si = 0
        $siSelected = $false
        while (-not $siSelected) {
            Clear-Host
            Write-Host "=== 配置错误 ===" -ForegroundColor Red
            Write-Host ""
            Write-Host "配置文件读取失败或为空" -ForegroundColor Red
            Write-Host ""
            if ($si -eq 0) {
                Write-Host "  重新初始化配置" -ForegroundColor Green -BackgroundColor Black
                Write-Host "  退出程序" -ForegroundColor White
            } else {
                Write-Host "  重新初始化配置" -ForegroundColor Yellow
                Write-Host "  退出程序" -ForegroundColor Green -BackgroundColor Black
            }
            Write-Host ""
            Write-Host "使用方向键选择，回车确认" -ForegroundColor Gray
            $si, $siSelected = Read-KeyInput -selectedIndex $si -maxIndex 1
            if ($siSelected -and $si -eq -1) { $si = 0; $siSelected = $true }
        }
        if ($si -eq 0) { Remove-ConfigAndSettings $configPath; continue }
        exit
    }

    # 检测所有问题
    $problems = @()
    $unrecoverable = $false

    if (-not $config.models -or $config.models -isnot [array] -or $config.models.Count -eq 0) {
        $problems += "models 为空或不存在"
        $unrecoverable = $true
    }

    if (-not $unrecoverable) {
        for ($i = 0; $i -lt $config.models.Count; $i++) {
            $m = $config.models[$i]
            if (-not $m.id) { $problems += "models[$i] 缺少 id" }
            if (-not $m.name) { $problems += "models[$i] 缺少 name" }
            if (-not $m.configFile) { $problems += "models[$i] 缺少 configFile" }
        }
        $validModelIds = @($config.models | ForEach-Object { $_.id })
        if (-not $config.defaultModel) {
            $problems += "缺少 defaultModel"
        } elseif ($config.defaultModel -notin $validModelIds) {
            $problems += "defaultModel '$($config.defaultModel)' 不存在于 models 中"
        }
        if ($config.defaultPermission -notin @("yes", "no")) {
            $problems += "defaultPermission 无效或缺失"
        }
    }

    # 无问题 → 确保补全 usageCount 后通过
    if ($problems.Count -eq 0) {
        $needsSave = $false
        for ($i = 0; $i -lt $config.models.Count; $i++) {
            if ($null -eq $config.models[$i].usageCount) {
                $config.models[$i] | Add-Member -MemberType NoteProperty -Name "usageCount" -Value 0 -Force
                $needsSave = $true
            }
        }
        if ($needsSave) { Save-Config $config }
        break
    }

    # 显示问题摘要并选择操作
    if ($unrecoverable) {
        $si = 0
        $siSelected = $false
        while (-not $siSelected) {
            Clear-Host
            Write-Host "=== 配置错误 ===" -ForegroundColor Red
            Write-Host ""
            foreach ($p in $problems) {
                Write-Host "  - $p" -ForegroundColor Red
            }
            Write-Host ""
            if ($si -eq 0) {
                Write-Host "  重新初始化配置" -ForegroundColor Green -BackgroundColor Black
                Write-Host "  退出程序" -ForegroundColor White
            } else {
                Write-Host "  重新初始化配置" -ForegroundColor Yellow
                Write-Host "  退出程序" -ForegroundColor Green -BackgroundColor Black
            }
            Write-Host ""
            Write-Host "使用方向键选择，回车确认" -ForegroundColor Gray
            $si, $siSelected = Read-KeyInput -selectedIndex $si -maxIndex 1
            if ($siSelected -and $si -eq -1) { $si = 0; $siSelected = $true }
        }
        if ($si -eq 0) { Remove-ConfigAndSettings $configPath; continue }
        exit
    }

    # 可恢复错误
    $si = 0
    $siSelected = $false
    while (-not $siSelected) {
        Clear-Host
        Write-Host "=== 配置错误 ===" -ForegroundColor Red
        Write-Host ""
        foreach ($p in $problems) {
            Write-Host "  - $p" -ForegroundColor Red
        }
        Write-Host ""
        $fixOptions = @("逐项修复", "重新初始化配置", "退出程序")
        for ($fi = 0; $fi -lt $fixOptions.Count; $fi++) {
            if ($fi -eq $si) {
                Write-Host "  $($fixOptions[$fi])" -ForegroundColor Green -BackgroundColor Black
            } else {
                $color = if ($fi -eq 0) { "Yellow" } else { "White" }
                Write-Host "  $($fixOptions[$fi])" -ForegroundColor $color
            }
        }
        Write-Host ""
        Write-Host "使用方向键选择，回车确认" -ForegroundColor Gray
        $si, $siSelected = Read-KeyInput -selectedIndex $si -maxIndex 2
        if ($siSelected -and $si -eq -1) { $si = 0; $siSelected = $true }
    }
    if ($si -eq 1) { Remove-ConfigAndSettings $configPath; continue }
    if ($si -eq 2) { exit }

    # --- 逐项修复 ---
    for ($i = 0; $i -lt $config.models.Count; $i++) {
        $m = $config.models[$i]

        if (-not $m.id) {
            Clear-Host
            Write-Host "=== 修复配置 ===" -ForegroundColor Yellow
            Write-Host "models[$i] 缺少 id" -ForegroundColor Red
            Write-Host ""
            $v = ""
            while ([string]::IsNullOrWhiteSpace($v)) {
                $v = Read-Host "请输入模型 ID"
                if ([string]::IsNullOrWhiteSpace($v)) { Write-Host "模型 ID 不能为空!" -ForegroundColor Red }
            }
            $config.models[$i] | Add-Member -MemberType NoteProperty -Name "id" -Value $v -Force
        }

        if (-not $m.name) {
            Clear-Host
            Write-Host "=== 修复配置 ===" -ForegroundColor Yellow
            Write-Host "models[$i] ($($config.models[$i].id)) 缺少 name" -ForegroundColor Red
            Write-Host ""
            $v = ""
            while ([string]::IsNullOrWhiteSpace($v)) {
                $v = Read-Host "请输入模型显示名称"
                if ([string]::IsNullOrWhiteSpace($v)) { Write-Host "显示名称不能为空!" -ForegroundColor Red }
            }
            $config.models[$i] | Add-Member -MemberType NoteProperty -Name "name" -Value $v -Force
        }

        if (-not $m.configFile) {
            Clear-Host
            Write-Host "=== 修复配置 ===" -ForegroundColor Yellow
            Write-Host "models[$i] ($($config.models[$i].id)) 缺少 configFile" -ForegroundColor Red
            Write-Host ""
            $v = ""
            while ([string]::IsNullOrWhiteSpace($v)) {
                $v = Read-Host "请输入配置文件名（如 settings-model.json）"
                if ([string]::IsNullOrWhiteSpace($v)) { Write-Host "配置文件名不能为空!" -ForegroundColor Red }
            }
            # 验证文件存在性
            $vPath = Join-Path $CONFIG_DIR $v
            if (-not (Test-Path -LiteralPath $vPath -PathType Leaf)) {
                $vi = 0
                $viSelected = $false
                while (-not $viSelected) {
                    Clear-Host
                    Write-Host "=== 修复配置 ===" -ForegroundColor Yellow
                    Write-Host "models[$i] ($($config.models[$i].id)) 缺少 configFile" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "警告: 文件 '$v' 不存在于 $CONFIG_DIR" -ForegroundColor Yellow
                    Write-Host "后续启动 Claude 时可能会报错。" -ForegroundColor Yellow
                    Write-Host ""
                    if ($vi -eq 0) {
                        Write-Host "  重新输入文件名" -ForegroundColor Green -BackgroundColor Black
                        Write-Host "  继续使用此文件名" -ForegroundColor White
                    } else {
                        Write-Host "  重新输入文件名" -ForegroundColor Yellow
                        Write-Host "  继续使用此文件名" -ForegroundColor Green -BackgroundColor Black
                    }
                    Write-Host ""
                    Write-Host "使用方向键选择，回车确认" -ForegroundColor Gray
                    $vi, $viSelected = Read-KeyInput -selectedIndex $vi -maxIndex 1
                    if ($viSelected -and $vi -eq -1) { $vi = 0; $viSelected = $true }
                }
                if ($vi -eq 0) {
                    $v = ""
                    while ([string]::IsNullOrWhiteSpace($v)) {
                        $v = Read-Host "请输入配置文件名（如 settings-model.json）"
                        if ([string]::IsNullOrWhiteSpace($v)) { Write-Host "配置文件名不能为空!" -ForegroundColor Red }
                    }
                }
            }
            $config.models[$i] | Add-Member -MemberType NoteProperty -Name "configFile" -Value $v -Force
        }
    }

    # 修复 defaultModel
    $validModelIds = @($config.models | ForEach-Object { $_.id })
    if (-not $config.defaultModel -or $config.defaultModel -notin $validModelIds) {
        Clear-Host
        Write-Host "=== 修复配置 ===" -ForegroundColor Yellow
        if (-not $config.defaultModel) {
            Write-Host "缺少 defaultModel" -ForegroundColor Red
        } else {
            Write-Host "defaultModel '$($config.defaultModel)' 不存在于 models 中" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "可用模型:" -ForegroundColor Cyan
        for ($j = 0; $j -lt $validModelIds.Count; $j++) {
            Write-Host "  $($j+1). $($validModelIds[$j])" -ForegroundColor White
        }
        Write-Host ""
        $selected = $null
        while (-not $selected) {
            $input = Read-Host "请选择默认模型（输入序号或模型 ID）"
            $num = 0
            if ([int]::TryParse($input, [ref]$num) -and $num -ge 1 -and $num -le $validModelIds.Count) {
                $selected = $validModelIds[$num - 1]
            } elseif ($input -in $validModelIds) {
                $selected = $input
            } else {
                Write-Host "无效选择，请重新输入" -ForegroundColor Red
            }
        }
        $config | Add-Member -MemberType NoteProperty -Name "defaultModel" -Value $selected -Force
    }

    # 修复 defaultPermission
    if ($config.defaultPermission -notin @("yes", "no")) {
        Clear-Host
        Write-Host "=== 修复配置 ===" -ForegroundColor Yellow
        Write-Host "defaultPermission 无效或缺失" -ForegroundColor Red
        Write-Host ""
        $permValue = ""
        while ($permValue -notin @("yes", "no")) {
            $permInput = Read-Host "默认权限模式（Y = bypassPermissions 跳过权限检查 / n = default 手动确认）(Y/n)"
            if ([string]::IsNullOrWhiteSpace($permInput) -or $permInput -eq "y" -or $permInput -eq "Y") {
                $permValue = "yes"
            } elseif ($permInput -eq "n" -or $permInput -eq "N") {
                $permValue = "no"
            } else {
                Write-Host "请输入 Y 或 n" -ForegroundColor Red
            }
        }
        $config | Add-Member -MemberType NoteProperty -Name "defaultPermission" -Value $permValue -Force
    }

    Save-Config $config
    continue
}

    # 确保 projects 是数组
    if ($null -eq $config.projects) {
        $config.projects = @()
    } elseif ($config.projects -isnot [array]) {
        $config.projects = @($config.projects)
    }

    # 确保每个项目都有 usageCount
    for ($i = 0; $i -lt $config.projects.Count; $i++) {
        $project = $config.projects[$i]

        # 兼容旧格式（纯字符串路径）
        if ($project -is [string]) {
            $config.projects[$i] = @{
                path = $project
                usageCount = 0
            }
        } elseif ($null -eq $project.usageCount) {
            $config.projects[$i] | Add-Member -MemberType NoteProperty -Name "usageCount" -Value 0 -Force
        }
    }

    # 保存初始化后的配置
    Save-Config $config
    return $config
}

# 更新模型使用次数
function Update-ModelUsage {
    param(
        [string]$modelId,
        [int]$delta
    )

    $config = Get-Config
    for ($i = 0; $i -lt $config.models.Count; $i++) {
        if ($config.models[$i].id -eq $modelId) {
            $currentCount = if ($config.models[$i].usageCount) { $config.models[$i].usageCount } else { 0 }
            $config.models[$i] | Add-Member -MemberType NoteProperty -Name "usageCount" -Value ([Math]::Max(0, $currentCount + $delta)) -Force
            Save-Config $config
            break
        }
    }
}

# 更新项目使用次数
function Update-ProjectUsage {
    param(
        [string]$projectPath,
        [int]$delta
    )

    $config = Get-Config
    for ($i = 0; $i -lt $config.projects.Count; $i++) {
        $p = $config.projects[$i]
        $path = if ($p -is [string]) { $p } else { $p.path }
        if ($path -eq $projectPath) {
            $currentCount = if ($p.usageCount) { $p.usageCount } else { 0 }
            $config.projects[$i] | Add-Member -MemberType NoteProperty -Name "usageCount" -Value ([Math]::Max(0, $currentCount + $delta)) -Force
            Save-Config $config
            break
        }
    }
}

# 获取按使用次数排序的模型列表（return ,@(...) 防止单元素被 PowerShell 解包，保证调用方始终拿到数组）
function Get-SortedModels {
    $config = Get-Config
    return ,@($config.models | Sort-Object -Property usageCount -Descending)
}

# 记录被清理的目录数量
$script:removedProjectsCount = 0

# 获取按使用次数排序的项目列表（同时清理无效目录）
function Get-SortedProjects {
    $config = Get-Config
    $validProjects = @()
    $removedCount = 0

    foreach ($p in $config.projects) {
        $path = if ($p -is [string]) { $p } else { $p.path }
        # 缺/空 path 的畸形条目显式按无效目录清理：直接 Test-Path -LiteralPath $null 时
        # PS7 终止单条语句静默改写配置、PS5.1 终止迭代体静默吞条目，两运行时行为分歧
        if ([string]::IsNullOrEmpty($path)) {
            $removedCount++
            continue
        }
        if (Test-Path -LiteralPath $path -PathType Container) {
            if ($p -is [string]) {
                $validProjects += @{ path = $p; usageCount = 0 }
            } else {
                $validProjects += $p
            }
        } else {
            $removedCount++
        }
    }

    if ($removedCount -gt 0) {
        $config.projects = $validProjects
        Save-Config $config
    }

    $script:removedProjectsCount = $removedCount
    return ,@($validProjects | Sort-Object -Property usageCount -Descending)
}

# 显示带选择的菜单函数
function Show-MenuWithSelection {
    param(
        [string]$title,
        [array]$items,
        [int]$selectedIndex,
        [string]$footer = ""
    )

    Clear-Host
    Write-Host "=== Claude 启动器 ===" -ForegroundColor Green
    Write-Host ""

    Write-Host $title -ForegroundColor Yellow
    Write-Host ""

    for ($i = 0; $i -lt $items.Count; $i++) {
        if ($i -eq $selectedIndex) {
            Write-Host "  $($items[$i])" -ForegroundColor Green -BackgroundColor Black
        } else {
            Write-Host "  $($items[$i])" -ForegroundColor White
        }
    }

    Write-Host ""
    if ($footer) {
        Write-Host $footer -ForegroundColor Cyan
    }
    Write-Host "使用方向键导航，回车选择，ESC取消，H获取帮助" -ForegroundColor Gray
}

# 显示状态摘要的函数
function Show-SelectionSummary {
    param(
        [string]$modelName = "",
        [string]$projectPath = ""
    )

    Write-Host "── 已选择 ──" -ForegroundColor DarkGray
    if ($modelName) {
        Write-Host "  模型: " -NoNewline -ForegroundColor Gray
        Write-Host $modelName -ForegroundColor Cyan
    } else {
        Write-Host "  模型: " -NoNewline -ForegroundColor Gray
        Write-Host "(未选择)" -ForegroundColor DarkGray
    }
    if ($projectPath) {
        $shortPath = if ($projectPath.Length -gt 50) { "..." + $projectPath.Substring($projectPath.Length - 47) } else { $projectPath }
        Write-Host "  项目: " -NoNewline -ForegroundColor Gray
        Write-Host $shortPath -ForegroundColor Cyan
    }
    Write-Host ""
}

# 显示带状态的目录选择函数
function Show-DirectorySelection {
    param(
        [int]$selectedIndex,
        [string]$modelName = "",
        [array]$sortedProjects
    )

    Clear-Host
    Write-Host "=== Claude 启动器 ===" -ForegroundColor Green
    Write-Host ""

    # 显示已选择状态
    Show-SelectionSummary -modelName $modelName

    Write-Host "选择项目目录:" -ForegroundColor Yellow
    Write-Host ""

    if ($sortedProjects.Count -eq 0) {
        Write-Host "  没有配置的目录" -ForegroundColor Red
        Write-Host ""
        Write-Host "按回车键返回主菜单..." -ForegroundColor Yellow
        return
    }

    for ($i = 0; $i -lt $sortedProjects.Count; $i++) {
        $projectInfo = $sortedProjects[$i]
        $path = $projectInfo.path

        if ($i -eq $selectedIndex) {
            Write-Host "  $($i+1). $path" -ForegroundColor Green -BackgroundColor Black
        } else {
            Write-Host "  $($i+1). $path" -ForegroundColor White
        }
    }

    Write-Host ""
    Write-Host "使用方向键导航，回车选择，ESC取消" -ForegroundColor Gray
    if ($script:removedProjectsCount -gt 0) {
        Write-Host "已清理 $($script:removedProjectsCount) 个无效目录" -ForegroundColor DarkGray
    }
}

# 显示模型选择的函数（按使用次数排序）
function Show-ModelSelection {
    param(
        [int]$selectedIndex,
        [array]$sortedModels
    )

    Clear-Host
    Write-Host "=== Claude 启动器 ===" -ForegroundColor Green
    Write-Host ""

    # 显示已选择状态（第一步还没有选择）
    Show-SelectionSummary

    Write-Host "选择模型:" -ForegroundColor Yellow
    Write-Host ""

    for ($i = 0; $i -lt $sortedModels.Count; $i++) {
        $model = $sortedModels[$i]
        $displayText = "$($model.name) ($($model.id))"

        if ($i -eq $selectedIndex) {
            Write-Host "  $($i+1). $displayText" -ForegroundColor Green -BackgroundColor Black
        } else {
            Write-Host "  $($i+1). $displayText" -ForegroundColor White
        }
    }

    Write-Host ""
    Write-Host "使用方向键导航，回车选择，ESC取消" -ForegroundColor Gray
}

# 权限模式定义（--permission-mode 合法取值，按菜单展示顺序；manual 为 default 的 CLI 别名，不单列）
$script:PermissionModes = @(
    @{ mode = "default";           label = "default           - 手动审查：每个权限逐一确认（Claude Code 默认）" },
    @{ mode = "acceptEdits";       label = "acceptEdits       - 自动接受文件编辑及常见文件命令，其余仍需确认" },
    @{ mode = "plan";              label = "plan              - 只读计划模式：研究与提案，不修改文件" },
    @{ mode = "auto";              label = "auto              - 常规操作直接执行，分类器模型后台审查拦截高危动作" },
    @{ mode = "bypassPermissions"; label = "bypassPermissions - 跳过所有权限检查（高危，建议仅限容器/VM）" },
    @{ mode = "dontAsk";           label = "dontAsk           - 未预授权的操作直接拒绝，会话永不等待（适合 CI）" }
)

# defaultPermission（yes/no）向后兼容映射为菜单默认选中索引（yes→bypassPermissions、no/default→default）
function ConvertTo-PermissionModeIndex {
    param([string]$DefaultPermission)
    $target = if ($DefaultPermission -eq "yes") { "bypassPermissions" } else { "default" }
    for ($i = 0; $i -lt $script:PermissionModes.Count; $i++) {
        if ($script:PermissionModes[$i].mode -eq $target) { return $i }
    }
    return 0
}

# 显示权限选择的函数
function Show-PermissionSelection {
    param(
        [int]$selectedIndex,
        [string]$modelName = "",
        [string]$projectPath = ""
    )

    Clear-Host
    Write-Host "=== Claude 启动器 ===" -ForegroundColor Green
    Write-Host ""

    # 显示已选择状态
    Show-SelectionSummary -modelName $modelName -projectPath $projectPath

    Write-Host "选择权限模式:" -ForegroundColor Yellow
    Write-Host ""

    for ($i = 0; $i -lt $script:PermissionModes.Count; $i++) {
        $line = $script:PermissionModes[$i].label
        if ($i -eq $selectedIndex) {
            Write-Host "  $($line)" -ForegroundColor Green -BackgroundColor Black
        } else {
            Write-Host "  $($line)" -ForegroundColor White
        }
    }

    Write-Host ""
    Write-Host "使用方向键导航，回车选择，ESC取消" -ForegroundColor Gray
}

# 显示帮助信息的函数
function Show-Help {
    Clear-Host
    Write-Host "=== 帮助信息 ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Claude 启动器使用说明:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "控制键:" -ForegroundColor White
    Write-Host "  方向键     - 导航菜单选项" -ForegroundColor White
    Write-Host "  回车键     - 选择当前选项 (次数+1)" -ForegroundColor White
    Write-Host "  ESC键      - 取消/返回 (次数-1)" -ForegroundColor White
    Write-Host "  H键        - 显示此帮助" -ForegroundColor White
    Write-Host ""
    Write-Host "功能:" -ForegroundColor White
    Write-Host "  - 按使用次数智能排序" -ForegroundColor White
    Write-Host "  - 简单的项目目录管理" -ForegroundColor White
    Write-Host "  - 可视化目录状态指示器" -ForegroundColor White
    Write-Host "  - 权限模式六选一（default/acceptEdits/plan/auto/bypassPermissions/dontAsk）" -ForegroundColor White
    Write-Host "  - 继续上次会话（主菜单一键续接上次启动）" -ForegroundColor White
    Write-Host "  - 自动配置保存/加载" -ForegroundColor White
    Write-Host ""
    Write-Host "配置文件位置:" -ForegroundColor Cyan
    Write-Host "  $configPath" -ForegroundColor White
    Write-Host ""
    Write-Host "按任意键返回..." -ForegroundColor Yellow
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# 添加模型的函数
function Add-Model {
    $config = Get-Config

    Clear-Host
    Write-Host "=== 添加模型 ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "当前配置的模型:" -ForegroundColor Cyan
    if ($config.models.Count -gt 0) {
        foreach ($m in $config.models) {
            Write-Host "  - $($m.id) ($($m.name))" -ForegroundColor White
        }
    } else {
        Write-Host "  没有配置的模型" -ForegroundColor Yellow
    }
    Write-Host ""

    # 输入模型 ID（空行取消）
    $newModelId = Read-HostWithCancel "输入模型 ID（如 glm-5.2[1m]）"
    if ([string]::IsNullOrWhiteSpace($newModelId)) {
        if (Confirm-Cancel) {
            return
        }
        # 用户选择不取消，继续输入
        while ([string]::IsNullOrWhiteSpace($newModelId)) {
            $newModelId = Read-Host "输入模型 ID（如 glm-5.2[1m]）"
            if ([string]::IsNullOrWhiteSpace($newModelId)) {
                Write-Host "模型 ID 不能为空!" -ForegroundColor Red
            }
        }
    }

    # 检查 ID 是否重复
    $idExists = $false
    foreach ($m in $config.models) {
        if ($m.id -eq $newModelId) {
            $idExists = $true
            break
        }
    }

    if ($idExists) {
        Write-Host ""
        Write-Host "模型 ID '$newModelId' 已存在!" -ForegroundColor Red
        Write-Host ""
        Write-Host "按任意键继续..." -ForegroundColor Yellow
        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }

    # 输入模型名称（空行取消）
    $newModelName = Read-HostWithCancel "输入模型显示名称（如 glm-5.2[1m]）"
    if ([string]::IsNullOrWhiteSpace($newModelName)) {
        if (Confirm-Cancel) {
            return
        }
        while ([string]::IsNullOrWhiteSpace($newModelName)) {
            $newModelName = Read-Host "输入模型显示名称（如 glm-5.2[1m]）"
            if ([string]::IsNullOrWhiteSpace($newModelName)) {
                Write-Host "模型显示名称不能为空!" -ForegroundColor Red
            }
        }
    }

    # 输入配置文件名（空行取消）
    $defaultConfigFile = "settings-$newModelId.json"
    $newConfigFile = Read-HostWithCancel "输入配置文件名" -defaultValue $defaultConfigFile
    if ([string]::IsNullOrWhiteSpace($newConfigFile)) {
        if (Confirm-Cancel) {
            return
        }
        $newConfigFile = $defaultConfigFile
    }

    # 验证配置文件名
    while ($newConfigFile -match '[\\\/]') {
        Write-Host "配置文件名不能包含路径分隔符!" -ForegroundColor Red
        $newConfigFile = Read-Host "输入配置文件名"
        if ([string]::IsNullOrWhiteSpace($newConfigFile)) {
            $newConfigFile = $defaultConfigFile
        }
    }

    Write-Host ""
    Write-Host "--- 配置 API 参数 ---" -ForegroundColor Cyan
    Write-Host ""

    # 输入 AUTH_TOKEN（必填，显示掩码提示，空行取消）
    $authToken = Read-HostWithCancel "输入 ANTHROPIC_AUTH_TOKEN（API 密钥）"
    if ([string]::IsNullOrWhiteSpace($authToken)) {
        if (Confirm-Cancel) {
            return
        }
        while ([string]::IsNullOrWhiteSpace($authToken)) {
            $authToken = Read-Host "输入 ANTHROPIC_AUTH_TOKEN（API 密钥）"
            if ([string]::IsNullOrWhiteSpace($authToken)) {
                Write-Host "API 密钥不能为空!" -ForegroundColor Red
            }
        }
    }

    # 输入 BASE_URL（有默认值）
    $defaultBaseUrl = "https://open.bigmodel.cn/api/anthropic"
    $baseUrl = Read-HostWithCancel "输入 ANTHROPIC_BASE_URL" -defaultValue $defaultBaseUrl
    if ([string]::IsNullOrWhiteSpace($baseUrl)) {
        $baseUrl = $defaultBaseUrl
    }

    # 输入 OPUS_MODEL（默认 = modelId）
    $opusModel = Read-HostWithCancel "输入 ANTHROPIC_DEFAULT_OPUS_MODEL" -defaultValue $newModelId
    if ([string]::IsNullOrWhiteSpace($opusModel)) {
        $opusModel = $newModelId
    }

    # 输入 SONNET_MODEL（默认 = modelId）
    $sonnetModel = Read-HostWithCancel "输入 ANTHROPIC_DEFAULT_SONNET_MODEL" -defaultValue $newModelId
    if ([string]::IsNullOrWhiteSpace($sonnetModel)) {
        $sonnetModel = $newModelId
    }

    # 输入 HAIKU_MODEL（此槽跑后台任务，建议 flash 级模型）
    $haikuModel = Read-HostWithCancel "输入 ANTHROPIC_DEFAULT_HAIKU_MODEL（此槽跑后台任务，建议 flash 级模型）" -defaultValue "glm-5.3-flash[1m]"
    if ([string]::IsNullOrWhiteSpace($haikuModel)) {
        $haikuModel = "glm-5.3-flash[1m]"
    }

    # 输入子代理模型（可选，留空使用系统默认；值尾加 ! 表示严格生效，写入 _FORCE=1）
    $subagentModel = Read-HostWithCancel "输入子代理模型（留空使用系统默认，值尾加 ! 表示严格生效）"
    if ([string]::IsNullOrWhiteSpace($subagentModel)) { $subagentModel = $null }

    # 输入 effort（可选，留空跳过；启动时透传 --effort）
    $newEffort = Read-HostWithCancel "输入 effort（留空跳过，如 high/max）"
    if ([string]::IsNullOrWhiteSpace($newEffort)) { $newEffort = $null }

    # 输入 fallbackModel（可选，留空跳过；启动时透传 --fallback-model 组成回退链）
    $newFallbackModel = Read-HostWithCancel "输入 fallbackModel（留空跳过，模型不可用时自动回退）"
    if ([string]::IsNullOrWhiteSpace($newFallbackModel)) { $newFallbackModel = $null }

    # 输入上下文窗口大小
    Write-Host ""
    Write-Host "--- 配置上下文窗口 ---" -ForegroundColor Cyan
    Write-Host ""

    $contextWindowSize = 0
    $contextWindowOriginal = ""

    while ($contextWindowSize -eq 0) {
        $windowInput = Read-Host "输入上下文窗口大小（如 200K、500K、1M，默认 1M）"

        if ([string]::IsNullOrWhiteSpace($windowInput)) {
            $contextWindowSize = 1000000
            $contextWindowOriginal = "1M"
        } else {
            $parsed = Parse-ContextWindow -ContextInput $windowInput
            if ($parsed) {
                $contextWindowSize = $parsed.size
                $contextWindowOriginal = $parsed.original
            } else {
                Write-Host "无效输入，请重新输入（格式：200K、500K、1M）" -ForegroundColor Red
            }
        }
    }

    # 检查配置文件是否存在，不存在则生成模板
    $fullConfigPath = Join-Path $CONFIG_DIR $newConfigFile
    $templateGenerated = $false

    if (-not (Test-Path -LiteralPath $fullConfigPath)) {
        Write-Host ""
        Write-Host "配置文件不存在，正在生成模板..." -ForegroundColor Yellow
        $templateGenerated = New-SettingsTemplate -modelId $newModelId -configFile $newConfigFile `
                                                  -authToken $authToken -baseUrl $baseUrl `
                                                  -opusModel $opusModel -sonnetModel $sonnetModel -haikuModel $haikuModel `
                                                  -subagentModel $subagentModel -contextWindowSize $contextWindowSize
    } else {
        # 配置文件已存在，需要更新上下文窗口 env
        try {
            $settingsContent = Get-Content -LiteralPath $fullConfigPath -Raw -Encoding UTF8
            $settings = $settingsContent | ConvertFrom-Json
            if ($settings.env) {
                Set-ContextWindowEnv -EnvObject $settings.env -ContextWindowSize $contextWindowSize
                $settings.env | Add-Member -MemberType NoteProperty -Name 'CLAUDE_PROFILE' -Value $newModelId -Force
            }

            # 更新子代理模型定制（env 级字段；留空跳过）
            if (-not [string]::IsNullOrWhiteSpace($subagentModel)) {
                $subForce = $subagentModel.EndsWith('!')
                $subValue = if ($subForce) { $subagentModel.TrimEnd('!') } else { $subagentModel }
                if ($settings.env -is [hashtable]) {
                    $settings.env['CLAUDE_CODE_SUBAGENT_MODEL'] = $subValue
                    if ($subForce) { $settings.env['CLAUDE_CODE_SUBAGENT_MODEL_FORCE'] = "1" }
                } else {
                    $settings.env | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_SUBAGENT_MODEL' -Value $subValue -Force
                    if ($subForce) {
                        $settings.env | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_SUBAGENT_MODEL_FORCE' -Value "1" -Force
                    }
                }
            }

            $settingsJson = $settings | ConvertTo-Json -Depth 10 | Format-Json
            Set-Content -LiteralPath $fullConfigPath -Value $settingsJson -Encoding UTF8
        } catch {
            # 静默失败
        }
    }

    # 添加模型到配置（effort/fallbackModel 仅在填写时写入）
    $newModelEntry = @{
        id = $newModelId
        name = $newModelName
        configFile = $newConfigFile
        contextWindow = $contextWindowOriginal
        usageCount = 0
    }
    if ($newEffort) { $newModelEntry.effort = $newEffort }
    if ($newFallbackModel) { $newModelEntry.fallbackModel = $newFallbackModel }
    $config.models += $newModelEntry

    Save-Config $config

    Write-Host ""
    Write-Host "✅ 模型添加成功!" -ForegroundColor Green
    if ($templateGenerated) {
        Write-Host "已生成 $newConfigFile 模板，API 配置已填入。" -ForegroundColor Green
    } else {
        Write-Host "配置文件已存在，未覆盖。" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "按任意键继续..." -ForegroundColor Yellow
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# 移除模型的函数
function Remove-Model {
    $config = Get-Config

    if ($config.models.Count -le 1) {
        Clear-Host
        Write-Host "=== 移除模型 ===" -ForegroundColor Green
        Write-Host ""
        Write-Host "至少需要保留一个模型!" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "按任意键继续..." -ForegroundColor Yellow
        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }

    $selectedIndex = 0
    $maxIndex = $config.models.Count - 1

    while ($true) {
        $config = Get-Config
        $maxIndex = $config.models.Count - 1
        if ($selectedIndex -gt $maxIndex) { $selectedIndex = $maxIndex }
        Clear-Host
        Write-Host "=== 移除模型 ===" -ForegroundColor Green
        Write-Host ""
        Write-Host "选择要移除的模型:" -ForegroundColor Yellow
        Write-Host ""

        for ($i = 0; $i -lt $config.models.Count; $i++) {
            $m = $config.models[$i]
            if ($i -eq $selectedIndex) {
                Write-Host "  $($i+1). $($m.id) ($($m.name))" -ForegroundColor Red -BackgroundColor Black
            } else {
                Write-Host "  $($i+1). $($m.id) ($($m.name))" -ForegroundColor White
            }
        }

        Write-Host ""
        Write-Host "使用方向键导航，回车选择，ESC取消" -ForegroundColor Gray

        $selectedIndex, $selected = Read-KeyInput -selectedIndex $selectedIndex -maxIndex $maxIndex

        if ($selected) {
            if ($selectedIndex -eq -1) { # ESC
                return
            }

            # 确认移除（使用循环顶部已读取的 $config，避免索引错位）
            $m = $config.models[$selectedIndex]
            $removedModelId = $m.id
            $removedModelName = $m.name

            Clear-Host
            Write-Host "=== 确认移除 ===" -ForegroundColor Red
            Write-Host ""
            Write-Host "你确定要移除以下模型吗:" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  $removedModelId ($removedModelName)" -ForegroundColor Red
            Write-Host ""
            Write-Host "此操作无法撤销。" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  是，移除它" -ForegroundColor Red
            Write-Host "  否，取消" -ForegroundColor White
            Write-Host ""
            Write-Host "使用方向键导航，回车选择" -ForegroundColor Gray

            $confirmIndex = 0
            $confirmSelected = $false

            while (-not $confirmSelected) {
                $confirmIndex, $confirmSelected = Read-KeyInput -selectedIndex $confirmIndex -maxIndex 1

                if ($confirmSelected) {
                    if ($confirmIndex -eq 0) { # 是
                        $config = Get-Config
                        $newModels = @($config.models | Where-Object { $_.id -ne $removedModelId })
                        $config.models = $newModels

                        # 如果删除的是默认模型，切换到第一个剩余模型
                        if ($config.defaultModel -eq $removedModelId) {
                            $config.defaultModel = $config.models[0].id
                        }

                        Save-Config $config
                        Clear-Host
                        Write-Host "模型移除成功!" -ForegroundColor Green
                        Write-Host ""
                        Write-Host "按任意键继续..." -ForegroundColor Yellow
                        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        return
                    } else { # 否
                        return
                    }
                }
            }
        }
    }
}

# 编辑模型配置的函数
function Edit-ModelConfig {
    $config = Get-Config

    if ($config.models.Count -eq 0) {
        Clear-Host
        Write-Host "=== 修改配置 ===" -ForegroundColor Green
        Write-Host ""
        Write-Host "没有配置的模型!" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "按任意键继续..." -ForegroundColor Yellow
        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }

    # 第一级：选择模型
    $modelSelectedIndex = 0

    while ($true) {
        $config = Get-Config
        $maxModelIndex = $config.models.Count - 1
        if ($modelSelectedIndex -gt $maxModelIndex) { $modelSelectedIndex = $maxModelIndex }

        Clear-Host
        Write-Host "=== 修改配置 ===" -ForegroundColor Green
        Write-Host ""
        Write-Host "选择要修改的模型:" -ForegroundColor Yellow
        Write-Host ""

        for ($i = 0; $i -lt $config.models.Count; $i++) {
            $m = $config.models[$i]
            if ($i -eq $modelSelectedIndex) {
                Write-Host "  $($i+1). $($m.name) ($($m.id))" -ForegroundColor Green -BackgroundColor Black
            } else {
                Write-Host "  $($i+1). $($m.name) ($($m.id))" -ForegroundColor White
            }
        }

        Write-Host ""
        Write-Host "使用方向键导航，回车选择，ESC返回" -ForegroundColor Gray

        $modelSelectedIndex, $modelSelected = Read-KeyInput -selectedIndex $modelSelectedIndex -maxIndex $maxModelIndex

        if ($modelSelected) {
            if ($modelSelectedIndex -eq -1) { # ESC - 返回主菜单
                return
            }

            # 获取选中的模型
            $selectedModel = $config.models[$modelSelectedIndex]
            $modelId = $selectedModel.id
            $modelName = $selectedModel.name
            $configFile = $selectedModel.configFile

            # 读取 settings 文件
            $settingsPath = Join-Path $CONFIG_DIR $configFile
            $settings = $null
            if (Test-Path -LiteralPath $settingsPath) {
                try {
                    $settingsContent = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8
                    $settings = $settingsContent | ConvertFrom-Json
                } catch {
                    Clear-Host
                    Write-Host "读取配置文件失败!" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "按任意键继续..." -ForegroundColor Yellow
                    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    continue
                }
            } else {
                Clear-Host
                Write-Host "配置文件不存在: $configFile" -ForegroundColor Red
                Write-Host ""
                Write-Host "按任意键继续..." -ForegroundColor Yellow
                $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                continue
            }

            # 第二级：选择字段
            $fieldSelectedIndex = 0

            while ($true) {
                # 确保 env 存在
                if (-not $settings.env) {
                    $settings | Add-Member -MemberType NoteProperty -Name "env" -Value (New-Object PSObject) -Force
                }

                # 获取当前值
                $currentToken = if ($settings.env.ANTHROPIC_AUTH_TOKEN) {
                    $token = $settings.env.ANTHROPIC_AUTH_TOKEN
                    if ($token.Length -gt 8) {
                        $token.Substring(0, 8) + "..."
                    } else {
                        $token
                    }
                } else { "" }

                $currentBaseUrl = if ($settings.env.ANTHROPIC_BASE_URL) { $settings.env.ANTHROPIC_BASE_URL } else { "" }
                $currentOpus = if ($settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL) { $settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL } else { "" }
                $currentSonnet = if ($settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL) { $settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL } else { "" }
                $currentHaiku = if ($settings.env.ANTHROPIC_DEFAULT_HAIKU_MODEL) { $settings.env.ANTHROPIC_DEFAULT_HAIKU_MODEL } else { "" }
                $currentSubagent = ""
                if ($settings.env.CLAUDE_CODE_SUBAGENT_MODEL) {
                    $currentSubagent = $settings.env.CLAUDE_CODE_SUBAGENT_MODEL
                    if ($settings.env.CLAUDE_CODE_SUBAGENT_MODEL_FORCE) { $currentSubagent += "（严格）" }
                } else { $currentSubagent = "系统默认" }
                $currentContext = if ($selectedModel.contextWindow) { $selectedModel.contextWindow } else { "1M" }
                $currentEffort = if ($selectedModel.effort) { $selectedModel.effort } else { "（未设置）" }
                $currentFallback = if ($selectedModel.fallbackModel) { $selectedModel.fallbackModel } else { "（未设置）" }

                $fieldItems = @(
                    "API 密钥    : $currentToken",
                    "Base URL    : $currentBaseUrl",
                    "Opus 模型   : $currentOpus",
                    "Sonnet 模型  : $currentSonnet",
                    "Haiku 模型   : $currentHaiku",
                    "子代理模型   : $currentSubagent",
                    "effort      : $currentEffort",
                    "fallback    : $currentFallback",
                    "上下文窗口   : $currentContext",
                    "返回"
                )

                Clear-Host
                Write-Host "=== 修改配置 - $modelName ===" -ForegroundColor Green
                Write-Host ""
                Write-Host "选择要修改的字段:" -ForegroundColor Yellow
                Write-Host ""

                for ($i = 0; $i -lt $fieldItems.Count; $i++) {
                    if ($i -eq $fieldSelectedIndex) {
                        Write-Host "  $($fieldItems[$i])" -ForegroundColor Green -BackgroundColor Black
                    } else {
                        Write-Host "  $($fieldItems[$i])" -ForegroundColor White
                    }
                }

                Write-Host ""
                Write-Host "使用方向键导航，回车选择，ESC返回" -ForegroundColor Gray

                $fieldSelectedIndex, $fieldSelected = Read-KeyInput -selectedIndex $fieldSelectedIndex -maxIndex 9

                if ($fieldSelected) {
                    if ($fieldSelectedIndex -eq -1) { # ESC - 返回第一级
                        break
                    }

                    if ($fieldSelectedIndex -eq 9) { # 返回
                        break
                    }

                    # 编辑字段
                    Clear-Host
                    Write-Host "=== 修改字段 ===" -ForegroundColor Green
                    Write-Host ""

                    switch ($fieldSelectedIndex) {
                        0 { # API 密钥
                            Write-Host "当前值: $currentToken" -ForegroundColor Cyan
                            Write-Host ""
                            $newValue = Read-Host "输入新值（留空保持不变）"
                            if (-not [string]::IsNullOrWhiteSpace($newValue)) {
                                $settings.env | Add-Member -MemberType NoteProperty -Name 'ANTHROPIC_AUTH_TOKEN' -Value $newValue -Force
                            }
                        }
                        1 { # Base URL
                            Write-Host "当前值: $currentBaseUrl" -ForegroundColor Cyan
                            Write-Host ""
                            $newValue = Read-Host "输入新值（留空保持不变）"
                            if (-not [string]::IsNullOrWhiteSpace($newValue)) {
                                $settings.env | Add-Member -MemberType NoteProperty -Name 'ANTHROPIC_BASE_URL' -Value $newValue -Force
                            }
                        }
                        2 { # Opus 模型
                            Write-Host "当前值: $currentOpus" -ForegroundColor Cyan
                            Write-Host ""
                            $newValue = Read-Host "输入新值（留空保持不变）"
                            if (-not [string]::IsNullOrWhiteSpace($newValue)) {
                                $settings.env | Add-Member -MemberType NoteProperty -Name 'ANTHROPIC_DEFAULT_OPUS_MODEL' -Value $newValue -Force
                            }
                        }
                        3 { # Sonnet 模型
                            Write-Host "当前值: $currentSonnet" -ForegroundColor Cyan
                            Write-Host ""
                            $newValue = Read-Host "输入新值（留空保持不变）"
                            if (-not [string]::IsNullOrWhiteSpace($newValue)) {
                                $settings.env | Add-Member -MemberType NoteProperty -Name 'ANTHROPIC_DEFAULT_SONNET_MODEL' -Value $newValue -Force
                            }
                        }
                        4 { # Haiku 模型
                            Write-Host "当前值: $currentHaiku" -ForegroundColor Cyan
                            Write-Host ""
                            $newValue = Read-Host "输入新值（留空保持不变）"
                            if (-not [string]::IsNullOrWhiteSpace($newValue)) {
                                $settings.env | Add-Member -MemberType NoteProperty -Name 'ANTHROPIC_DEFAULT_HAIKU_MODEL' -Value $newValue -Force
                            }
                        }
                        5 { # 子代理模型
                            Write-Host "当前值: $currentSubagent" -ForegroundColor Cyan
                            Write-Host ""
                            $newValue = Read-Host "输入新值（留空保持不变，输入 null 清除为系统默认，值尾加 ! 表示严格生效）"
                            if (-not [string]::IsNullOrWhiteSpace($newValue)) {
                                if ($newValue -eq "null") {
                                    if ($settings.env -is [hashtable]) {
                                        $settings.env.Remove('CLAUDE_CODE_SUBAGENT_MODEL') | Out-Null
                                        $settings.env.Remove('CLAUDE_CODE_SUBAGENT_MODEL_FORCE') | Out-Null
                                    } else {
                                        if ($settings.env.PSObject.Properties['CLAUDE_CODE_SUBAGENT_MODEL']) {
                                            $settings.env.PSObject.Properties.Remove('CLAUDE_CODE_SUBAGENT_MODEL')
                                        }
                                        if ($settings.env.PSObject.Properties['CLAUDE_CODE_SUBAGENT_MODEL_FORCE']) {
                                            $settings.env.PSObject.Properties.Remove('CLAUDE_CODE_SUBAGENT_MODEL_FORCE')
                                        }
                                    }
                                } else {
                                    $subForce = $newValue.EndsWith('!')
                                    $subValue = if ($subForce) { $newValue.TrimEnd('!') } else { $newValue }
                                    if ($settings.env -is [hashtable]) {
                                        $settings.env['CLAUDE_CODE_SUBAGENT_MODEL'] = $subValue
                                        if ($subForce) { $settings.env['CLAUDE_CODE_SUBAGENT_MODEL_FORCE'] = "1" }
                                    } else {
                                        $settings.env | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_SUBAGENT_MODEL' -Value $subValue -Force
                                        if ($subForce) {
                                            $settings.env | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_SUBAGENT_MODEL_FORCE' -Value "1" -Force
                                        }
                                    }
                                }
                            }
                        }
                        6 { # effort
                            Write-Host "当前值: $currentEffort" -ForegroundColor Cyan
                            Write-Host ""
                            $newValue = Read-Host "输入新值（留空保持不变，输入 null 清除）"
                            if (-not [string]::IsNullOrWhiteSpace($newValue)) {
                                if ($newValue -eq "null") {
                                    $config = Get-Config
                                    for ($i = 0; $i -lt $config.models.Count; $i++) {
                                        if ($config.models[$i].id -eq $modelId) {
                                            if ($config.models[$i].PSObject.Properties['effort']) {
                                                $config.models[$i].PSObject.Properties.Remove('effort')
                                            }
                                            break
                                        }
                                    }
                                    Save-Config $config
                                } else {
                                    $config = Get-Config
                                    for ($i = 0;  $i -lt $config.models.Count; $i++) {
                                        if ($config.models[$i].id -eq $modelId) {
                                            $config.models[$i] | Add-Member -MemberType NoteProperty -Name "effort" -Value $newValue -Force
                                            break
                                        }
                                    }
                                    Save-Config $config
                                    $selectedModel | Add-Member -MemberType NoteProperty -Name "effort" -Value $newValue -Force
                                }
                            }
                        }
                        7 { # fallbackModel
                            Write-Host "当前值: $currentFallback" -ForegroundColor Cyan
                            Write-Host ""
                            $newValue = Read-Host "输入新值（留空保持不变，输入 null 清除）"
                            if (-not [string]::IsNullOrWhiteSpace($newValue)) {
                                if ($newValue -eq "null") {
                                    $config = Get-Config
                                    for ($i = 0; $i -lt $config.models.Count; $i++) {
                                        if ($config.models[$i].id -eq $modelId) {
                                            if ($config.models[$i].PSObject.Properties['fallbackModel']) {
                                                $config.models[$i].PSObject.Properties.Remove('fallbackModel')
                                            }
                                            break
                                        }
                                    }
                                    Save-Config $config
                                } else {
                                    $config = Get-Config
                                    for ($i = 0; $i -lt $config.models.Count; $i++) {
                                        if ($config.models[$i].id -eq $modelId) {
                                            $config.models[$i] | Add-Member -MemberType NoteProperty -Name "fallbackModel" -Value $newValue -Force
                                            break
                                        }
                                    }
                                    Save-Config $config
                                    $selectedModel | Add-Member -MemberType NoteProperty -Name "fallbackModel" -Value $newValue -Force
                                }
                            }
                        }
                        8 { # 上下文窗口
                            Write-Host "当前值: $currentContext" -ForegroundColor Cyan
                            Write-Host ""

                            $newContextSize = 0
                            $newContextOriginal = ""

                            while ($newContextSize -eq 0) {
                                $windowInput = Read-Host "输入新值（如 200K、500K、1M，留空保持不变）"

                                if ([string]::IsNullOrWhiteSpace($windowInput)) {
                                    $newContextSize = -1  # 标记为保持不变
                                    break
                                }

                                $parsed = Parse-ContextWindow -ContextInput $windowInput
                                if ($parsed) {
                                    $newContextSize = $parsed.size
                                    $newContextOriginal = $parsed.original
                                } else {
                                    Write-Host "无效输入，请重新输入（格式：200K、500K、1M）" -ForegroundColor Red
                                }
                            }

                            if ($newContextSize -ne -1) {
                                # 更新 settings env
                                Set-ContextWindowEnv -EnvObject $settings.env -ContextWindowSize $newContextSize

                                # 同步更新 claude-config.json 中的 contextWindow
                                $config = Get-Config
                                for ($i = 0; $i -lt $config.models.Count; $i++) {
                                    if ($config.models[$i].id -eq $modelId) {
                                        $config.models[$i] | Add-Member -MemberType NoteProperty -Name "contextWindow" -Value $newContextOriginal -Force
                                        break
                                    }
                                }
                                Save-Config $config
                            }
                        }
                    }

                    # 保存 settings 文件
                    try {
                        $settingsJson = $settings | ConvertTo-Json -Depth 10 | Format-Json
                        Set-Content -LiteralPath $settingsPath -Value $settingsJson -Encoding UTF8

                        Clear-Host
                        Write-Host "✅ 配置已保存!" -ForegroundColor Green
                        Write-Host ""
                        Write-Host "按任意键继续..." -ForegroundColor Yellow
                        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    } catch {
                        Clear-Host
                        Write-Host "保存失败: $_" -ForegroundColor Red
                        Write-Host ""
                        Write-Host "按任意键继续..." -ForegroundColor Yellow
                        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    }
                }
            }
        }
    }
}

# 添加项目目录的函数
function Add-ProjectDirectory {
    $config = Get-Config

    Clear-Host
    Write-Host "=== 添加项目目录 ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "当前配置的目录:" -ForegroundColor Cyan
    if ($config.projects.Count -gt 0) {
        foreach ($p in $config.projects) {
            $path = if ($p -is [string]) { $p } else { $p.path }
            Write-Host "  - $path" -ForegroundColor White
        }
    } else {
        Write-Host "  没有配置的目录" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "输入项目目录的完整路径:" -ForegroundColor Yellow
    Write-Host "(你可以将文件夹拖拽到这里)" -ForegroundColor Gray
    Write-Host ""

    $newPath = Read-Host "路径"

    if ([string]::IsNullOrWhiteSpace($newPath)) {
        Write-Host "路径不能为空!" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    if (Test-Path -LiteralPath $newPath -PathType Container) {
        # 检查是否已存在
        $exists = $false
        foreach ($p in $config.projects) {
            $path = if ($p -is [string]) { $p } else { $p.path }
            if ($path -eq $newPath) {
                $exists = $true
                break
            }
        }

        if (-not $exists) {
            $config.projects += @{
                path = $newPath
                usageCount = 0
            }
            Save-Config $config
            Write-Host "目录添加成功!" -ForegroundColor Green
        } else {
            Write-Host "目录已存在!" -ForegroundColor Yellow
        }
    } else {
        Write-Host "目录不存在，请检查路径!" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "按任意键继续..." -ForegroundColor Yellow
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# 移除项目目录的函数
function Remove-ProjectDirectory {
    $config = Get-Config

    if ($config.projects.Count -eq 0) {
        Clear-Host
        Write-Host "=== 移除项目目录 ===" -ForegroundColor Green
        Write-Host ""
        Write-Host "没有可移除的目录!" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "按任意键继续..." -ForegroundColor Yellow
        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }

    $selectedIndex = 0
    $maxIndex = $config.projects.Count - 1

    while ($true) {
        $config = Get-Config
        $maxIndex = $config.projects.Count - 1
        if ($selectedIndex -gt $maxIndex) { $selectedIndex = $maxIndex }
        Clear-Host
        Write-Host "=== 移除项目目录 ===" -ForegroundColor Green
        Write-Host ""
        Write-Host "选择要移除的目录:" -ForegroundColor Yellow
        Write-Host ""

        for ($i = 0; $i -lt $config.projects.Count; $i++) {
            $p = $config.projects[$i]
            $path = if ($p -is [string]) { $p } else { $p.path }
            if ($i -eq $selectedIndex) {
                Write-Host "  $($i+1). $path" -ForegroundColor Red -BackgroundColor Black
            } else {
                Write-Host "  $($i+1). $path" -ForegroundColor White
            }
        }

        Write-Host ""
        Write-Host "使用方向键导航，回车选择，ESC取消" -ForegroundColor Gray

        $selectedIndex, $selected = Read-KeyInput -selectedIndex $selectedIndex -maxIndex $maxIndex

        if ($selected) {
            if ($selectedIndex -eq -1) { # ESC
                return
            }

            # 确认移除（使用循环顶部已读取的 $config，避免索引错位）
            $p = $config.projects[$selectedIndex]
            $removedPath = if ($p -is [string]) { $p } else { $p.path }

            Clear-Host
            Write-Host "=== 确认移除 ===" -ForegroundColor Red
            Write-Host ""
            Write-Host "你确定要移除以下目录吗:" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  $removedPath" -ForegroundColor Red
            Write-Host ""
            Write-Host "此操作无法撤销。" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  是，移除它" -ForegroundColor Red
            Write-Host "  否，取消" -ForegroundColor White
            Write-Host ""
            Write-Host "使用方向键导航，回车选择" -ForegroundColor Gray

            $confirmIndex = 0
            $confirmSelected = $false

            while (-not $confirmSelected) {
                $confirmIndex, $confirmSelected = Read-KeyInput -selectedIndex $confirmIndex -maxIndex 1

                if ($confirmSelected) {
                    if ($confirmIndex -eq 0) { # 是
                        $config = Get-Config
                        $newProjects = @()
                        foreach ($p in $config.projects) {
                            $path = if ($p -is [string]) { $p } else { $p.path }
                            if ($path -ne $removedPath) {
                                $newProjects += $p
                            }
                        }
                        $config.projects = $newProjects
                        Save-Config $config
                        Clear-Host
                        Write-Host "目录移除成功!" -ForegroundColor Green
                        Write-Host ""
                        Write-Host "按任意键继续..." -ForegroundColor Yellow
                        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        return
                    } else { # 否
                        return
                    }
                }
            }
        }
    }
}

# 启动 Claude 的函数
function Start-Claude {
    param($projectPath, $permissionMode, $configFile, $modelId = $null, $modelName = $null, [switch]$Continue, [string[]]$ExtraArgs = @())

    # 检查项目目录是否存在
    if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
        Write-Host "项目目录不存在!" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    # 确定配置文件路径（使用 $CONFIG_DIR，尊重脚本顶部 $CUSTOM_CONFIG_DIR 自定义）
    $fullConfigPath = Join-Path $CONFIG_DIR $configFile

    # 检查配置文件是否存在
    if (-not (Test-Path -LiteralPath $fullConfigPath)) {
        Write-Host "配置文件不存在: $fullConfigPath" -ForegroundColor Red
        Write-Host "请确保配置文件已正确创建。" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        return
    }

    # 切换到项目目录
    try {
        Set-Location $projectPath
    } catch {
        Write-Host "切换目录失败: $_" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    # 检查 claude 命令是否可用
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue

    if ($claudeCmd) {
        try {
            # 透传 effort / fallbackModel（models[] 可选字段，留空不拼接）
            $effort = $null; $fallbackModel = $null
            if ($modelId) {
                $effortConfig = Get-Config
                foreach ($m in $effortConfig.models) {
                    if ($m.id -eq $modelId) {
                        $effort = $m.effort
                        $fallbackModel = $m.fallbackModel
                        break
                    }
                }
            }

            # 记录本次启动参数（主菜单「继续上次会话」的数据源；预检全部通过后写入）
            if ($modelId) {
                $llConfig = Get-Config
                if ($llConfig) {
                    $ll = @{
                        configFile = $configFile
                        modelId = $modelId
                        modelName = $modelName
                        projectPath = $projectPath
                        permissionMode = $permissionMode
                        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                    }
                    $llConfig | Add-Member -MemberType NoteProperty -Name "lastLaunch" -Value $ll -Force
                    Save-Config $llConfig
                }
            }

            # 使用本地安装的 Claude 命令启动（在当前窗口），统一走 --permission-mode
            # -Continue 时拼接 -c 续接最近会话
            $claudeArgs = @("--settings", $fullConfigPath, "--permission-mode", $permissionMode)
            if ($effort) { $claudeArgs += @("--effort", [string]$effort) }
            if ($fallbackModel) { $claudeArgs += @("--fallback-model", [string]$fallbackModel) }
            if ($Continue) { $claudeArgs += "-c" }
            if ($ExtraArgs.Count -gt 0) { $claudeArgs += $ExtraArgs }
            # 语句级直调（严禁携带管道，也严禁上游赋值/if 捕获本调用链）：claude 必须继承
            # 控制台 stdout（TTY）。stdout 一旦变成管道（| Out-Host 或 $x = 捕获），claude
            # 会判定非交互环境切入 --print 模式，无 prompt 时报 "Input must be provided..."
            # 瞬间退出（2026-10-28 录屏复盘，详见 tests 回归用例）
            & claude @claudeArgs

        } catch {
            Write-Host "启动 Claude 失败: $_" -ForegroundColor Red
            Start-Sleep -Seconds 2
            return
        }
    } else {
        Write-Host "未找到 claude 命令" -ForegroundColor Red
        Write-Host "请确保 Claude 已正确安装并配置环境变量" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        return
    }
}

# CLI 参数直启：解析 -Model/-Project/-Permission，任一未提供时回退默认值；校验失败回退主菜单
function Invoke-DirectLaunch {
    # 启动结果经 $script:DirectLaunchLaunched 上报：本函数必须被语句级调用，
    # 返回值会打到控制台（True/False），上游赋值捕获更会破坏 claude 的 TTY 继承
    $script:DirectLaunchLaunched = $false
    $config = Get-Config
    $dl = $script:DirectLaunchArgs

    # 解析模型：显式指定 → 校验存在；未提供 → defaultModel；均无效 → 回退主菜单
    $modelEntry = $null
    if ($dl.model) {
        foreach ($m in $config.models) {
            if ($m.id -eq $dl.model) { $modelEntry = $m; break }
        }
        if (-not $modelEntry) {
            Write-Host "模型不存在: $($dl.model)" -ForegroundColor Red
            Write-Host "可用模型: $(($config.models | ForEach-Object { $_.id }) -join ', ')"
            return
        }
    } else {
        foreach ($m in $config.models) {
            if ($m.id -eq $config.defaultModel) { $modelEntry = $m; break }
        }
        if (-not $modelEntry) { $modelEntry = $config.models[0] }
    }

    # 解析项目目录：显式指定 → 校验存在；未提供 → 使用次数最高的有效项目
    $projectPath = $null
    if ($dl.project) {
        if (Test-Path -LiteralPath $dl.project -PathType Container) {
            $projectPath = $dl.project
        } else {
            Write-Host "项目目录不存在: $($dl.project)" -ForegroundColor Red
            return
        }
    } else {
        $sortedProjects = Get-SortedProjects
        if ($sortedProjects.Count -gt 0) { $projectPath = $sortedProjects[0].path }
    }

    if (-not $projectPath) {
        Write-Host "无可用项目目录（用主菜单「添加项目目录」或 -Project 指定）" -ForegroundColor Red
        return
    }

    # 解析权限模式：显式合法 → 采用；显式非法 → 提示并回退映射默认；未提供 → 映射默认
    $mode = $null
    if ($dl.permission) {
        foreach ($pm in $script:PermissionModes) {
            if ($pm.mode -eq $dl.permission) { $mode = $pm.mode; break }
        }
        if (-not $mode) {
            Write-Host "无效权限模式: $($dl.permission)（合法取值: $(($script:PermissionModes | ForEach-Object { $_.mode }) -join '/')）"
            return
        }
    }
    if (-not $mode) {
        $mode = $script:PermissionModes[(ConvertTo-PermissionModeIndex -DefaultPermission $config.defaultPermission)].mode
    }

    # usage 计数 +1 并启动
    Update-ModelUsage -modelId $modelEntry.id -delta 1
    Update-ProjectUsage -projectPath $projectPath -delta 1
    Write-Host "直启: $($modelEntry.id) @ $projectPath ($mode)"
    Start-Claude -projectPath $projectPath -permissionMode $mode -configFile $modelEntry.configFile -modelId $modelEntry.id -modelName $modelEntry.name
    $script:DirectLaunchLaunched = $true
    return
}

      # Main：主菜单循环
# settings 废弃键清单（新增废弃键时在此追加）
$script:DeprecatedSettingsKeys = @(
    @{ key = "teammateDefaultModel"; scope = "top"; reason = "Claude Code v2.1.234 已移除，残留无效果" },
    @{ key = "teammateMode"; scope = "top"; reason = "Claude Code v2.1.234 已移除，残留无效果" }
)

# env 块废弃/非法取值清单
$script:DeprecatedEnvValues = @(
    @{ key = "ENABLE_TOOL_SEARCH"; bad = "0"; reason = "非官方取值（官方关闭值为 false）" }
)

# 环境体检：claude 版本比较、settings 废弃键扫描、登录状态检测
function Invoke-EnvironmentCheck {
    Clear-Host
    Write-Host "=== 环境体检 ===" -ForegroundColor Green
    Write-Host ""

    # 1. claude 版本与最新版比较
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($claudeCmd) {
        $vRaw = (& claude --version 2>$null) -join " "
        $localVersion = $null
        if ($vRaw -match '(\d+\.\d+\.\d+)') { $localVersion = $Matches[1] }
        $shownV = if ($localVersion) { $localVersion } else { $vRaw }
        Write-Host ("[版本] 本机 claude: " + $shownV) -ForegroundColor White
        if ($localVersion) {
            $job = Start-Job { & npm view @anthropic-ai/claude-code version 2>$null }
            if (Wait-Job $job -Timeout 12) {
                $latestRaw = (Receive-Job $job) -join ""
                Remove-Job $job
                if ($latestRaw -match '(\d+\.\d+\.\d+)') {
                    $latest = $Matches[1]
                    try { $isNewer = [version]$latest -gt [version]$localVersion } catch { $isNewer = $null }
                    if ($isNewer) {
                        Write-Host ("[版本] 最新版: $latest（可更新: npm install -g @anthropic-ai/claude-code@latest）") -ForegroundColor Yellow
                    } else {
                        Write-Host ("[版本] 最新版: $latest（已是最新）") -ForegroundColor Green
                    }
                } else {
                    Write-Host "[版本] 无法获取最新版（npm 查询结果异常）" -ForegroundColor DarkGray
                }
            } else {
                Stop-Job $job
                Remove-Job $job -Force
                Write-Host "[版本] 无法获取最新版（npm 查询超时）" -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Host "[版本] 未找到 claude 命令" -ForegroundColor Red
    }
    Write-Host ""

    # 2. settings-*.json 废弃键扫描
    $scanCount = 0
    $deprecatedHits = 0
    $scanFiles = @(Get-ChildItem -Path $CONFIG_DIR -Filter "settings-*.json" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "*.example.json" })
    foreach ($f in $scanFiles) {
        $scanCount++
        try {
            $s = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-Host ("[废弃键] " + $f.Name + ": 无法解析（JSON 损坏，跳过）") -ForegroundColor Yellow
            continue
        }
        foreach ($d in $script:DeprecatedSettingsKeys) {
            if ($s.PSObject.Properties[$d.key]) {
                $deprecatedHits++
                Write-Host ("[废弃键] " + $f.Name + ": " + $d.key + " — " + $d.reason) -ForegroundColor Yellow
            }
        }
        foreach ($d in $script:DeprecatedEnvValues) {
            if ($s.env -and $s.env.PSObject.Properties[$d.key]) {
                $val = [string]$s.env.($d.key)
                if ($val -eq $d.bad) {
                    $deprecatedHits++
                    Write-Host ("[废弃值] " + $f.Name + ": env." + $d.key + "=" + $val + " — " + $d.reason) -ForegroundColor Yellow
                }
            }
        }
    }
    if ($scanCount -eq 0) {
        Write-Host "[废弃键] $CONFIG_DIR 下未找到 settings-*.json" -ForegroundColor DarkGray
    } elseif ($deprecatedHits -eq 0) {
        Write-Host ("[废弃键] " + $scanCount + " 个配置文件均无废弃键") -ForegroundColor Green
    }
    Write-Host ""

    # 3. 登录状态（claude auth status；旧版无此子命令时降级为提示）
    if ($claudeCmd) {
        $authRaw = (& claude auth status 2>&1) -join " "
        if ($LASTEXITCODE -eq 0 -and $authRaw) {
            try { $auth = $authRaw | ConvertFrom-Json } catch { $auth = $null }
            if ($auth -and $null -ne $auth.loggedIn) {
                if ($auth.loggedIn) {
                    Write-Host ("[登录] 已登录（" + $auth.authMethod + " / " + $auth.apiProvider + "）") -ForegroundColor Green
                } else {
                    Write-Host "[登录] 未登录" -ForegroundColor Yellow
                }
            } else {
                Write-Host "[登录] claude auth status 输出无法解析" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "[登录] 当前 claude 版本不支持 auth status 子命令，无法检测" -ForegroundColor DarkGray
        }
    }
    Write-Host ""

    Write-Host "按任意键返回主菜单..." -ForegroundColor Yellow
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
# Main：主菜单循环
function Main {
    try {
    while ($true) {
        # 动态构建主菜单：lastLaunch 有效时显示「继续上次会话」，失效时清除并提示
        $menuItems = @("使用 Claude")
        $continueIndex = -1
        $invalidLastLaunch = $false
        $config = Get-Config
        if ($config.lastLaunch) {
            $ll = $config.lastLaunch
            $llSettingsFile = Join-Path $CONFIG_DIR $ll.configFile
            if ($ll.configFile -and (Test-Path -LiteralPath $llSettingsFile) -and $ll.projectPath -and (Test-Path -LiteralPath $ll.projectPath -PathType Container)) {
                $menuItems += "继续上次会话"
                $continueIndex = 1
            } else {
                # 失效清除：提示并移除该字段
                $config.PSObject.Properties.Remove('lastLaunch')
                Save-Config $config
                $invalidLastLaunch = $true
            }
        }
        $menuItems += @(
            "添加模型",
            "修改配置",
            "移除模型",
            "添加项目目录",
            "环境体检",
            "移除项目目录",
            "退出"
        )

        $selectedIndex = 0
        $maxIndex = $menuItems.Count - 1

        while ($true) {
            $menuFooter = if ($invalidLastLaunch) { "上次会话启动参数已失效，已清除续接记录" } else { "" }
            Show-MenuWithSelection -title "主菜单" -items $menuItems -selectedIndex $selectedIndex -footer $menuFooter

            $selectedIndex, $selected = Read-KeyInput -selectedIndex $selectedIndex -maxIndex $maxIndex

            if ($selected) {
                if ($selectedIndex -eq -1) { # ESC
                    continue
                }
                if ($selectedIndex -eq -2) { # H
                    Show-Help
                    continue
                }

                if ($selectedIndex -eq 0) {
                    # 使用 Claude
                    $config = Get-Config

                        if ($config.projects.Count -eq 0) {
                            Clear-Host
                            Write-Host "=== 使用 Claude ===" -ForegroundColor Green
                            Write-Host ""
                            Write-Host "没有配置项目目录!" -ForegroundColor Yellow
                            Write-Host ""
                            Write-Host "请先添加项目目录。" -ForegroundColor White
                            Write-Host ""
                            Write-Host "按任意键继续..." -ForegroundColor Yellow
                            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                            continue
                        }

                        # 第一步：选择模型（按使用次数排序）
                        $sortedModels = Get-SortedModels
                        $modelIndex = 0
                        $modelMax = $sortedModels.Count - 1

                        # 记录当前选择的模型ID（用于回退时减少计数）
                        $currentModelId = $null

                        # 使用标签来控制回退层级
                        :modelLoop while ($true) {
                            Show-ModelSelection -selectedIndex $modelIndex -sortedModels $sortedModels

                            $modelIndex, $modelSelected = Read-KeyInput -selectedIndex $modelIndex -maxIndex $modelMax

                            if ($modelSelected) {
                                if ($modelIndex -eq -1) { # ESC - 返回主菜单
                                    break modelLoop
                                    if ($modelIndex -eq -2) { # H - 显示帮助后回到本页
                                        Show-Help
                                        continue modelLoop
                                    }
                                }

                                # 获取选中的模型信息
                                $selectedModel = $sortedModels[$modelIndex]
                                $modelId = $selectedModel.id
                                $modelName = $selectedModel.name
                                $configFile = $selectedModel.configFile

                                # 增加模型使用次数
                                Update-ModelUsage -modelId $modelId -delta 1
                                $currentModelId = $modelId

                                # 重新获取排序后的模型列表
                                $sortedModels = Get-SortedModels

                                # 第二步：选择项目目录（按使用次数排序）
                                $sortedProjects = Get-SortedProjects
                                $dirIndex = 0
                                $dirMax = $sortedProjects.Count - 1

                                # 记录当前选择的项目路径（用于回退时减少计数）
                                $currentProjectPath = $null

                                :dirLoop while ($true) {
                                    Show-DirectorySelection -selectedIndex $dirIndex -modelName $modelName -sortedProjects $sortedProjects
                                    if ($sortedProjects.Count -eq 0) {
                                        # 全部目录失效被清理：等待按键后撤销模型计数，返回主菜单（防空数组击穿）
                                        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                                        if ($currentModelId) { Update-ModelUsage -modelId $currentModelId -delta -1 }
                                        break modelLoop
                                    }

                                    $dirIndex, $dirSelected = Read-KeyInput -selectedIndex $dirIndex -maxIndex $dirMax

                                    if ($dirSelected) {
                                        if ($dirIndex -eq -2) { # H - 显示帮助后回到本页
                                            Show-Help
                                            continue dirLoop
                                        }
                                        if ($dirIndex -eq -1) { # ESC - 返回模型选择
                                            # 减少模型使用次数
                                            if ($currentModelId) {
                                                Update-ModelUsage -modelId $currentModelId -delta -1
                                            }
                                            # 重新获取排序后的模型列表并查找当前模型的索引
                                            $sortedModels = Get-SortedModels
                                            for ($i = 0; $i -lt $sortedModels.Count; $i++) {
                                                if ($sortedModels[$i].id -eq $currentModelId) {
                                                    $modelIndex = $i
                                                    break
                                                }
                                            }
                                            $dirIndex = 0
                                            break dirLoop
                                        }

                                        # 获取选中的项目信息
                                        $selectedProjectInfo = $sortedProjects[$dirIndex]
                                        $selectedProjectPath = $selectedProjectInfo.path

                                        # 增加项目使用次数
                                        Update-ProjectUsage -projectPath $selectedProjectPath -delta 1
                                        $currentProjectPath = $selectedProjectPath

                                        # 重新获取排序后的项目列表
                                        $sortedProjects = Get-SortedProjects

                                        # 第三步：选择权限模式
                                        $config = Get-Config
                                        $permIndex = ConvertTo-PermissionModeIndex -DefaultPermission $config.defaultPermission
                                        $permMax = $script:PermissionModes.Count - 1

                                        :permLoop while ($true) {
                                            Show-PermissionSelection -selectedIndex $permIndex -modelName $modelName -projectPath $selectedProjectPath

                                            $permIndex, $permSelected = Read-KeyInput -selectedIndex $permIndex -maxIndex $permMax

                                            if ($permSelected) {
                                                if ($permIndex -eq -2) { # H - 显示帮助后回到本页
                                                    Show-Help
                                                    continue permLoop
                                                }
                                                if ($permIndex -eq -1) { # ESC - 返回项目选择
                                                    # 减少项目使用次数
                                                    if ($currentProjectPath) {
                                                        Update-ProjectUsage -projectPath $currentProjectPath -delta -1
                                                    }
                                                    $permIndex = ConvertTo-PermissionModeIndex -DefaultPermission $config.defaultPermission
                                                    break permLoop
                                                }

                                                $selectedMode = $script:PermissionModes[$permIndex].mode

                                                # 启动 Claude（记录 lastLaunch 供「继续上次会话」使用）
                                                Start-Claude -projectPath $selectedProjectPath -permissionMode $selectedMode -configFile $configFile -modelId $modelId -modelName $modelName

                                                # Claude 退出后返回主菜单
                                                Clear-Host
                                                Write-Host "Claude 已退出。" -ForegroundColor Yellow
                                                Write-Host ""
                                                Write-Host "按任意键返回主菜单..." -ForegroundColor Yellow
                                                $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                                                break modelLoop
                                            }
                                        }
                                        # 权限选择 ESC 后重置状态，继续项目选择循环
                                    }
                                }
                                # 项目选择 ESC 后重置状态，继续模型选择循环
                            }
                        }
                        # 模型选择 ESC 后回到这里，继续主菜单
                    }
                    elseif ($continueIndex -ge 0 -and $selectedIndex -eq $continueIndex) {
                        # 继续上次会话：直接以 -c 续接，usage 计数同步 +1
                        $config = Get-Config
                        $ll = $config.lastLaunch
                        if ($ll) {
                            # 权限模式校验：失效回退到 defaultPermission 映射
                            $llMode = $ll.permissionMode
                            $modeValid = $false
                            foreach ($pm in $script:PermissionModes) {
                                if ($pm.mode -eq $llMode) { $modeValid = $true; break }
                            }
                            if (-not $modeValid) {
                                $llMode = $script:PermissionModes[(ConvertTo-PermissionModeIndex -DefaultPermission $config.defaultPermission)].mode
                            }

                            # usage 计数 +1（模型或项目已不存在时为安全空操作）
                            Update-ModelUsage -modelId $ll.modelId -delta 1
                            Update-ProjectUsage -projectPath $ll.projectPath -delta 1

                            Start-Claude -projectPath $ll.projectPath -permissionMode $llMode -configFile $ll.configFile -modelId $ll.modelId -modelName $ll.modelName -Continue

                            Clear-Host
                            Write-Host "Claude 已退出。" -ForegroundColor Yellow
                            Write-Host ""
                            Write-Host "按任意键返回主菜单..." -ForegroundColor Yellow
                            $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        }
                    }
                    else {
                        switch ($menuItems[$selectedIndex]) {
                            "添加模型" { Add-Model }
                            "修改配置" { Edit-ModelConfig }
                            "移除模型" { Remove-Model }
                            "添加项目目录" { Add-ProjectDirectory }
                            "环境体检" { Invoke-EnvironmentCheck }
                            "移除项目目录" { Remove-ProjectDirectory }
                            "退出" {
                                Clear-Host
                                Write-Host "再见!" -ForegroundColor Green
                                exit
                            }
                        }
                    }
                break
            }
        }
    }
} catch {
    Clear-Host
    Write-Host "发生错误: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "按任意键退出..." -ForegroundColor Yellow
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}

# dot-source 守卫：仅当脚本被直接运行时执行 Bootstrap + Main；
# dot-source（. .\cboot.ps1）只加载函数与当前作用域常量，零输出零交互，可重复加载
if ($MyInvocation.InvocationName -ne '.') {
    Bootstrap | Out-Null
    if ($script:DirectLaunchArgs) {
        # 必须语句级调用（结果经 $script:DirectLaunchLaunched 上报）：赋值/if 条件捕获会把
        # Start-Claude 内 & claude 的 stdout 重定向进管道，claude 检测到 stdout 非 TTY 后
        # 切入 --print 模式，无 prompt 时报错瞬间退出
        Invoke-DirectLaunch
        if (-not $script:DirectLaunchLaunched) { Main }
    }
    else { Main }
}
