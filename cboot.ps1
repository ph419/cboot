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
function Set-ContextWindowEnv {
    param(
        [object]$EnvObject,
        [int]$ContextWindowSize
    )

    if ($EnvObject -is [hashtable]) {
        # hashtable 类型：通过 key 索引赋值，Remove 移除
        if ($ContextWindowSize -lt 1000000) {
            $EnvObject['CLAUDE_CODE_DISABLE_1M_CONTEXT'] = "1"
            $EnvObject['CLAUDE_CODE_AUTO_COMPACT_WINDOW'] = "$ContextWindowSize"
        } else {
            $EnvObject.Remove('CLAUDE_CODE_DISABLE_1M_CONTEXT') | Out-Null
            $EnvObject['CLAUDE_CODE_AUTO_COMPACT_WINDOW'] = "$ContextWindowSize"
        }
    } else {
        # PSCustomObject 类型：Add-Member -Force 覆盖属性，PSObject.Properties 判存在后 Remove
        if ($ContextWindowSize -lt 1000000) {
            $EnvObject | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_DISABLE_1M_CONTEXT' -Value "1" -Force
            $EnvObject | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_AUTO_COMPACT_WINDOW' -Value "$ContextWindowSize" -Force
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
        [string]$teammateModel = $null,
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
                ENABLE_TOOL_SEARCH = "0"
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

    $template.env.ANTHROPIC_AUTH_TOKEN = $authToken
    $template.env.ANTHROPIC_BASE_URL = $baseUrl
    $template.env.ANTHROPIC_DEFAULT_OPUS_MODEL = $opusModel
    $template.env.ANTHROPIC_DEFAULT_SONNET_MODEL = $sonnetModel
    $template.env.ANTHROPIC_DEFAULT_HAIKU_MODEL = $haikuModel

    # 上下文窗口设置（>=1M 时清除模板可能遗留的字段）
    Set-ContextWindowEnv -EnvObject $template.env -ContextWindowSize $contextWindowSize

    # teammate 配置（[string] 参数会将 $null 转为空字符串，需显式还原为 $null）
    $teammateModelValue = if ([string]::IsNullOrWhiteSpace($teammateModel)) { $null } else { $teammateModel }
    if ($template -is [hashtable]) {
        # hashtable 类型：Add-Member 只添加 note property，ConvertTo-Json 不会序列化
        # 必须通过 key 赋值才能写入 JSON
        $template["teammateDefaultModel"] = $teammateModelValue
        $template["teammateMode"] = "auto"
    } else {
        # PSCustomObject 类型：Add-Member -Force 可正确覆盖属性
        $template | Add-Member -MemberType NoteProperty -Name "teammateDefaultModel" -Value $teammateModelValue -Force
        $template | Add-Member -MemberType NoteProperty -Name "teammateMode" -Value "auto" -Force
    }

    $template.model = $modelId

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

    # 步骤 1/7: 配置模型基础信息
    Write-Host "步骤 1/7: 配置模型基础信息" -ForegroundColor Cyan
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

    # 步骤 2/7: 配置 API 参数
    Write-Host "步骤 2/7: 配置 API 参数" -ForegroundColor Cyan
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

    $haikuModel = Read-HostWithCancel "请输入 ANTHROPIC_DEFAULT_HAIKU_MODEL" -defaultValue $modelId
    if ([string]::IsNullOrWhiteSpace($haikuModel)) { $haikuModel = $modelId }

    # 步骤 3/7: Teammate 模型设置
    Write-Host "步骤 3/7: Teammate 模型设置" -ForegroundColor Cyan
    Write-Host ""

    $teammateModel = Read-HostWithCancel "请输入 Teammate 默认模型（留空使用系统默认）"
    if ([string]::IsNullOrWhiteSpace($teammateModel)) { $teammateModel = $null }

    Write-Host ""

    # 步骤 4/7: 上下文窗口设置
    Write-Host "步骤 4/7: 上下文窗口设置" -ForegroundColor Cyan
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

    # 步骤 5/7: 默认权限
    Write-Host "步骤 5/7: 默认权限" -ForegroundColor Cyan
    Write-Host ""

    $defaultPermission = ""
    while ($defaultPermission -notin @("yes", "no")) {
        $permInput = Read-Host "是否默认允许所有操作？(Y/n)"
        if ([string]::IsNullOrWhiteSpace($permInput) -or $permInput -eq "y" -or $permInput -eq "Y") {
            $defaultPermission = "yes"
        } elseif ($permInput -eq "n" -or $permInput -eq "N") {
            $defaultPermission = "no"
        } else {
            Write-Host "请输入 Y 或 n" -ForegroundColor Red
        }
    }
    Write-Host ""

    # 步骤 6/7: 项目目录
    Write-Host "步骤 6/7: 项目目录" -ForegroundColor Cyan
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
        Write-Host "  Teammate 模型: $(if ($teammateModel) { $teammateModel } else { '系统默认' })" -ForegroundColor White
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

    # 步骤 7/7: 保存配置并生成模板
    Write-Host "步骤 7/7: 保存配置" -ForegroundColor Cyan
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
                                             -teammateModel $teammateModel -contextWindowSize $contextWindowSize

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

# 配置加载与验证循环（缺失字段可逐项修复）
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
        $config.defaultModel = $selected
    }

    # 修复 defaultPermission
    if ($config.defaultPermission -notin @("yes", "no")) {
        Clear-Host
        Write-Host "=== 修复配置 ===" -ForegroundColor Yellow
        Write-Host "defaultPermission 无效或缺失" -ForegroundColor Red
        Write-Host ""
        $permValue = ""
        while ($permValue -notin @("yes", "no")) {
            $permInput = Read-Host "是否默认允许所有操作？(Y/n)"
            if ([string]::IsNullOrWhiteSpace($permInput) -or $permInput -eq "y" -or $permInput -eq "Y") {
                $permValue = "yes"
            } elseif ($permInput -eq "n" -or $permInput -eq "N") {
                $permValue = "no"
            } else {
                Write-Host "请输入 Y 或 n" -ForegroundColor Red
            }
        }
        $config.defaultPermission = $permValue
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

# 获取按使用次数排序的模型列表
function Get-SortedModels {
    $config = Get-Config
    return @($config.models | Sort-Object -Property usageCount -Descending)
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
    return @($validProjects | Sort-Object -Property usageCount -Descending)
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

    Write-Host "是否启用所有权限?" -ForegroundColor Yellow
    Write-Host ""

    $permissions = @(
        "是 - 跳过所有权限检查 (推荐)",
        "否 - 每个权限手动确认"
    )

    for ($i = 0; $i -lt $permissions.Count; $i++) {
        if ($i -eq $selectedIndex) {
            Write-Host "  $($permissions[$i])" -ForegroundColor Green -BackgroundColor Black
        } else {
            Write-Host "  $($permissions[$i])" -ForegroundColor White
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
    Write-Host "  - Claude 权限控制" -ForegroundColor White
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

    # 输入 HAIKU_MODEL（默认 = modelId）
    $haikuModel = Read-HostWithCancel "输入 ANTHROPIC_DEFAULT_HAIKU_MODEL" -defaultValue $newModelId
    if ([string]::IsNullOrWhiteSpace($haikuModel)) {
        $haikuModel = $newModelId
    }

    # 输入 TEAMMATE_MODEL（默认 = null，即使用系统默认）
    $teammateModel = Read-HostWithCancel "输入 Teammate 默认模型（留空使用系统默认）"
    if ([string]::IsNullOrWhiteSpace($teammateModel)) {
        $teammateModel = $null
    }

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
                                                  -teammateModel $teammateModel -contextWindowSize $contextWindowSize
    } else {
        # 配置文件已存在，需要更新上下文窗口 env
        try {
            $settingsContent = Get-Content -LiteralPath $fullConfigPath -Raw -Encoding UTF8
            $settings = $settingsContent | ConvertFrom-Json
            if ($settings.env) {
                Set-ContextWindowEnv -EnvObject $settings.env -ContextWindowSize $contextWindowSize
            }

            # 更新 teammate 配置（top-level 字段，不受 env 影响）
            $settings | Add-Member -MemberType NoteProperty -Name "teammateDefaultModel" -Value $teammateModel -Force
            $settings | Add-Member -MemberType NoteProperty -Name "teammateMode" -Value "auto" -Force

            $settingsJson = $settings | ConvertTo-Json -Depth 10 | Format-Json
            Set-Content -LiteralPath $fullConfigPath -Value $settingsJson -Encoding UTF8
        } catch {
            # 静默失败
        }
    }

    # 添加模型到配置
    $config.models += @{
        id = $newModelId
        name = $newModelName
        configFile = $newConfigFile
        contextWindow = $contextWindowOriginal
        usageCount = 0
    }

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
                    $settings | Add-Member -MemberType NoteProperty -Name "env" -Value @{} -Force
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
                $currentTeammate = if ($settings.teammateDefaultModel) { $settings.teammateDefaultModel } else { "系统默认" }
                $currentContext = if ($selectedModel.contextWindow) { $selectedModel.contextWindow } else { "1M" }

                $fieldItems = @(
                    "API 密钥    : $currentToken",
                    "Base URL    : $currentBaseUrl",
                    "Opus 模型   : $currentOpus",
                    "Sonnet 模型  : $currentSonnet",
                    "Haiku 模型   : $currentHaiku",
                    "Teammate 模型: $currentTeammate",
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

                $fieldSelectedIndex, $fieldSelected = Read-KeyInput -selectedIndex $fieldSelectedIndex -maxIndex 7

                if ($fieldSelected) {
                    if ($fieldSelectedIndex -eq -1) { # ESC - 返回第一级
                        break
                    }

                    if ($fieldSelectedIndex -eq 7) { # 返回
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
                                $settings.env.ANTHROPIC_AUTH_TOKEN = $newValue
                            }
                        }
                        1 { # Base URL
                            Write-Host "当前值: $currentBaseUrl" -ForegroundColor Cyan
                            Write-Host ""
                            $newValue = Read-Host "输入新值（留空保持不变）"
                            if (-not [string]::IsNullOrWhiteSpace($newValue)) {
                                $settings.env.ANTHROPIC_BASE_URL = $newValue
                            }
                        }
                        2 { # Opus 模型
                            Write-Host "当前值: $currentOpus" -ForegroundColor Cyan
                            Write-Host ""
                            $newValue = Read-Host "输入新值（留空保持不变）"
                            if (-not [string]::IsNullOrWhiteSpace($newValue)) {
                                $settings.env.ANTHROPIC_DEFAULT_OPUS_MODEL = $newValue
                            }
                        }
                        3 { # Sonnet 模型
                            Write-Host "当前值: $currentSonnet" -ForegroundColor Cyan
                            Write-Host ""
                            $newValue = Read-Host "输入新值（留空保持不变）"
                            if (-not [string]::IsNullOrWhiteSpace($newValue)) {
                                $settings.env.ANTHROPIC_DEFAULT_SONNET_MODEL = $newValue
                            }
                        }
                        4 { # Haiku 模型
                            Write-Host "当前值: $currentHaiku" -ForegroundColor Cyan
                            Write-Host ""
                            $newValue = Read-Host "输入新值（留空保持不变）"
                            if (-not [string]::IsNullOrWhiteSpace($newValue)) {
                                $settings.env.ANTHROPIC_DEFAULT_HAIKU_MODEL = $newValue
                            }
                        }
                        5 { # Teammate 模型
                            Write-Host "当前值: $currentTeammate" -ForegroundColor Cyan
                            Write-Host ""
                            $newValue = Read-Host "输入新值（留空保持不变，输入 null 清除为系统默认）"
                            if (-not [string]::IsNullOrWhiteSpace($newValue)) {
                                if ($newValue -eq "null") {
                                    $settings | Add-Member -MemberType NoteProperty -Name "teammateDefaultModel" -Value $null -Force
                                } else {
                                    $settings | Add-Member -MemberType NoteProperty -Name "teammateDefaultModel" -Value $newValue -Force
                                }
                            }
                        }
                        6 { # 上下文窗口
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
    param($projectPath, $noConfirm, $configFile)

    # 检查项目目录是否存在
    if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
        Write-Host "项目目录不存在!" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    # 确定配置文件路径
    $claudeConfigPath = "$env:USERPROFILE\.claude"
    $fullConfigPath = Join-Path $claudeConfigPath $configFile

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
            # 使用本地安装的 Claude 命令启动（在当前窗口）
            if ($noConfirm) {
                & claude --settings "$fullConfigPath" --dangerously-skip-permissions
            } else {
                & claude --settings "$fullConfigPath"
            }

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

# 主程序
try {
    while ($true) {
        $menuItems = @(
            "使用 Claude",
            "添加模型",
            "修改配置",
            "移除模型",
            "添加项目目录",
            "移除项目目录",
            "退出"
        )

        $selectedIndex = 0
        $maxIndex = $menuItems.Count - 1

        while ($true) {
            Show-MenuWithSelection -title "主菜单" -items $menuItems -selectedIndex $selectedIndex

            $selectedIndex, $selected = Read-KeyInput -selectedIndex $selectedIndex -maxIndex $maxIndex

            if ($selected) {
                if ($selectedIndex -eq -1) { # ESC
                    continue
                }
                if ($selectedIndex -eq -2) { # H
                    Show-Help
                    continue
                }

                switch ($selectedIndex) {
                    0 { # 使用 Claude
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

                                    $dirIndex, $dirSelected = Read-KeyInput -selectedIndex $dirIndex -maxIndex $dirMax

                                    if ($dirSelected) {
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

                                        # 第三步：选择权限
                                        $config = Get-Config
                                        $permIndex = if ($config.defaultPermission -eq "no") { 1 } else { 0 }
                                        $permMax = 1

                                        :permLoop while ($true) {
                                            Show-PermissionSelection -selectedIndex $permIndex -modelName $modelName -projectPath $selectedProjectPath

                                            $permIndex, $permSelected = Read-KeyInput -selectedIndex $permIndex -maxIndex $permMax

                                            if ($permSelected) {
                                                if ($permIndex -eq -1) { # ESC - 返回项目选择
                                                    # 减少项目使用次数
                                                    if ($currentProjectPath) {
                                                        Update-ProjectUsage -projectPath $currentProjectPath -delta -1
                                                    }
                                                    $permIndex = if ($config.defaultPermission -eq "no") { 1 } else { 0 }
                                                    break permLoop
                                                }

                                                $noConfirm = ($permIndex -eq 0)

                                                # 启动 Claude
                                                Start-Claude -projectPath $selectedProjectPath -noConfirm $noConfirm -configFile $configFile

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
                    1 { # 添加模型
                        Add-Model
                    }
                    2 { # 修改配置
                        Edit-ModelConfig
                    }
                    3 { # 移除模型
                        Remove-Model
                    }
                    4 { # 添加项目目录
                        Add-ProjectDirectory
                    }
                    5 { # 移除项目目录
                        Remove-ProjectDirectory
                    }
                    6 { # 退出
                        Clear-Host
                        Write-Host "再见!" -ForegroundColor Green
                        exit
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
