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

# 检查配置文件是否存在
if (-not (Test-Path $configPath)) {
    Clear-Host
    Write-Host "=== 配置错误 ===" -ForegroundColor Red
    Write-Host ""
    Write-Host "配置文件不存在: $configPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "请创建配置文件并设置以下必需字段:" -ForegroundColor Yellow
    Write-Host "  - projects: 项目目录数组" -ForegroundColor White
    Write-Host "  - defaultModel: 默认模型 (glm 或 arc)" -ForegroundColor White
    Write-Host "  - defaultPermission: 默认权限 (yes 或 no)" -ForegroundColor White
    Write-Host ""
    Write-Host "按任意键退出..." -ForegroundColor Yellow
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# 读取配置
function Get-Config {
    try {
        $configContent = Get-Content $configPath -Raw -Encoding UTF8
        return ConvertFrom-Json $configContent
    } catch {
        return $null
    }
}

# 保存配置
function Save-Config {
    param($config)
    try {
        $configJson = $config | ConvertTo-Json -Depth 10
        Set-Content -Path $configPath -Value $configJson -Encoding UTF8
    } catch {
        # 静默失败
    }
}

$config = Get-Config

# 验证配置
if (-not $config) {
    Clear-Host
    Write-Host "=== 配置错误 ===" -ForegroundColor Red
    Write-Host ""
    Write-Host "配置文件读取失败或为空" -ForegroundColor Red
    Write-Host ""
    Write-Host "按任意键退出..." -ForegroundColor Yellow
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# 验证必需字段
$missingFields = @()
if (-not $config.models) { $missingFields += "models" }
if (-not $config.defaultModel) { $missingFields += "defaultModel" }
if (-not $config.projects) { $missingFields += "projects" }
if (-not $config.defaultPermission) { $missingFields += "defaultPermission" }

if ($missingFields.Count -gt 0) {
    Clear-Host
    Write-Host "=== 配置错误 ===" -ForegroundColor Red
    Write-Host ""
    Write-Host "配置文件缺少必需字段: $($missingFields -join ', ')" -ForegroundColor Red
    Write-Host ""
    Write-Host "按任意键退出..." -ForegroundColor Yellow
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# 验证 models 是否为数组且不为空
if ($config.models -isnot [array] -or $config.models.Count -eq 0) {
    Clear-Host
    Write-Host "=== 配置错误 ===" -ForegroundColor Red
    Write-Host ""
    Write-Host "models 必须是一个非空数组" -ForegroundColor Red
    Write-Host ""
    Write-Host "按任意键退出..." -ForegroundColor Yellow
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# 验证每个模型是否有必需字段
for ($i = 0; $i -lt $config.models.Count; $i++) {
    $model = $config.models[$i]
    $modelMissing = @()
    if (-not $model.id) { $modelMissing += "id" }
    if (-not $model.name) { $modelMissing += "name" }
    if (-not $model.configFile) { $modelMissing += "configFile" }

    if ($modelMissing.Count -gt 0) {
        Clear-Host
        Write-Host "=== 配置错误 ===" -ForegroundColor Red
        Write-Host ""
        Write-Host "models[$i] 缺少必需字段: $($modelMissing -join ', ')" -ForegroundColor Red
        Write-Host ""
        Write-Host "按任意键退出..." -ForegroundColor Yellow
        $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit
    }

    # 确保 usageCount 存在
    if ($null -eq $model.usageCount) {
        $config.models[$i] | Add-Member -MemberType NoteProperty -Name "usageCount" -Value 0 -Force
    }
}

# 验证 defaultModel 是否对应 models 中的某个 id
$validModelIds = $config.models | ForEach-Object { $_.id }
if ($config.defaultModel -notin $validModelIds) {
    Clear-Host
    Write-Host "=== 配置错误 ===" -ForegroundColor Red
    Write-Host ""
    Write-Host "defaultModel 的值 '$($config.defaultModel)' 不存在于 models 中" -ForegroundColor Red
    Write-Host ""
    Write-Host "按任意键退出..." -ForegroundColor Yellow
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# 验证字段值
if ($config.defaultPermission -notin @("yes", "no")) {
    Clear-Host
    Write-Host "=== 配置错误 ===" -ForegroundColor Red
    Write-Host ""
    Write-Host "defaultPermission 的值必须为 'yes' 或 'no'" -ForegroundColor Red
    Write-Host ""
    Write-Host "按任意键退出..." -ForegroundColor Yellow
    $null = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}

# 确保 projects 是数组
if ($config.projects -isnot [array]) {
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
            $config.models[$i].usageCount = [Math]::Max(0, $currentCount + $delta)
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
            $config.projects[$i].usageCount = [Math]::Max(0, $currentCount + $delta)
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
        if (Test-Path $path -PathType Container) {
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

    if (Test-Path $newPath -PathType Container) {
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

            # 确认移除
            $config = Get-Config
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
                        for ($i = 0; $i -lt $config.projects.Count; $i++) {
                            if ($i -ne $selectedIndex) {
                                $newProjects += $config.projects[$i]
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
    if (-not (Test-Path $projectPath -PathType Container)) {
        Write-Host "项目目录不存在!" -ForegroundColor Red
        Start-Sleep -Seconds 2
        return
    }

    # 确定配置文件路径
    $claudeConfigPath = "$env:USERPROFILE\.claude"
    $fullConfigPath = Join-Path $claudeConfigPath $configFile

    # 检查配置文件是否存在
    if (-not (Test-Path $fullConfigPath)) {
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
                    1 { # 添加项目目录
                        Add-ProjectDirectory
                    }
                    2 { # 移除项目目录
                        Remove-ProjectDirectory
                    }
                    3 { # 退出
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
