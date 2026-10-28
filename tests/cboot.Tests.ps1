# cboot Pester 5.x 单元测试
# 运行: Invoke-Pester -Configuration @{ Run = @{ Path = 'tests' } }
# CI 守卫要求 UTF-8 with BOM（构建后已注入 BOM）

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    # 隔离：USERPROFILE 重定向到临时目录后再 dot-source（dot-source 守卫保证零副作用）
    # 顺序约束：重定向必须严格先于 dot-source —— cboot.ps1 顶部在加载时把 $env:USERPROFILE 烤进 $configPath
    $script:OrigUserProfile = $env:USERPROFILE
    $script:TestHome = Join-Path $TestDrive 'home'
    New-Item -ItemType Directory -Path (Join-Path $script:TestHome '.claude') -Force | Out-Null
    $env:USERPROFILE = $script:TestHome
    . (Join-Path $script:RepoRoot 'cboot.ps1')
}

AfterAll {
    # 恢复进程级 USERPROFILE，避免交互式会话跑完测试后子进程继承指向已删除临时目录的污染
    $env:USERPROFILE = $script:OrigUserProfile
}

Describe 'Format-Json' {
    It '输出 2 空格缩进且冒号后单空格' {
        $json = @{ a = @{ b = 1 } } | ConvertTo-Json -Depth 5
        $out = $json | Format-Json
        ($out -split "`r`n")[1] | Should -Match '^  "a": \{$'
        ($out -split "`r`n")[2] | Should -Match '^    "b": 1$'
    }
    It '空行被移除并保留 CRLF 结尾' {
        $out = "{`r`n`"a`":  1`r`n}" | Format-Json
        $out.EndsWith("`r`n") | Should -Be $true
        $out | Should -Match '"a": 1'
    }
}

Describe 'Parse-ContextWindow' {
    It '200K 解析为 200000' {
        $r = Parse-ContextWindow -ContextInput '200K'
        $r.size | Should -Be 200000
        $r.original | Should -Be '200K'
    }
    It '500K 解析为 500000' {
        $r = Parse-ContextWindow -ContextInput '500K'
        $r.size | Should -Be 500000
        [string]::IsNullOrEmpty($r.original) | Should -Be $false
    }
    It '1M 解析为 1000000（默认值）' {
        $r = Parse-ContextWindow -ContextInput '1M'
        $r.size | Should -Be 1000000
        $r.original | Should -Be '1M'
    }
    It '0.5M 解析为 500000' {
        $r = Parse-ContextWindow -ContextInput '0.5M'
        $r.size | Should -Be 500000
    }
    It '非法输入返回 $null' {
        Parse-ContextWindow -ContextInput 'abc' | Should -BeNullOrEmpty
        Parse-ContextWindow -ContextInput '12x' | Should -BeNullOrEmpty
    }
    It '空输入返回默认 1M' {
        $r = Parse-ContextWindow -ContextInput ''
        $r.size | Should -Be 1000000
        $r.original | Should -Be '1M'
    }
}

Describe 'Set-ContextWindowEnv' {
    It '200K: 写 DISABLE_1M_CONTEXT，清除 AUTO_COMPACT（hashtable）' {
        $env_ = @{}
        Set-ContextWindowEnv -EnvObject $env_ -ContextWindowSize 200000
        $env_['CLAUDE_CODE_DISABLE_1M_CONTEXT'] | Should -Be '1'
        $env_.ContainsKey('CLAUDE_CODE_AUTO_COMPACT_WINDOW') | Should -Be $false
    }
    It '200K: 同上（PSCustomObject）' {
        $env_ = '{"x":"1"}' | ConvertFrom-Json
        Set-ContextWindowEnv -EnvObject $env_ -ContextWindowSize 200000
        $env_.CLAUDE_CODE_DISABLE_1M_CONTEXT | Should -Be '1'
        $env_.PSObject.Properties['CLAUDE_CODE_AUTO_COMPACT_WINDOW'] | Should -BeNullOrEmpty
    }
    It '500K: 只写 AUTO_COMPACT=500000，无 DISABLE（hashtable）' {
        $env_ = @{}
        Set-ContextWindowEnv -EnvObject $env_ -ContextWindowSize 500000
        $env_['CLAUDE_CODE_AUTO_COMPACT_WINDOW'] | Should -Be '500000'
        $env_.ContainsKey('CLAUDE_CODE_DISABLE_1M_CONTEXT') | Should -Be $false
    }
    It '500K: 同上（PSCustomObject）' {
        $env_ = '{"CLAUDE_CODE_DISABLE_1M_CONTEXT":"1","CLAUDE_CODE_AUTO_COMPACT_WINDOW":"1000000"}' | ConvertFrom-Json
        Set-ContextWindowEnv -EnvObject $env_ -ContextWindowSize 500000
        $env_.CLAUDE_CODE_AUTO_COMPACT_WINDOW | Should -Be '500000'
        $env_.PSObject.Properties['CLAUDE_CODE_DISABLE_1M_CONTEXT'] | Should -BeNullOrEmpty
    }
    It '1M: AUTO_COMPACT=1000000，无 DISABLE' {
        $env_ = @{}
        Set-ContextWindowEnv -EnvObject $env_ -ContextWindowSize 1000000
        $env_['CLAUDE_CODE_AUTO_COMPACT_WINDOW'] | Should -Be '1000000'
        $env_.ContainsKey('CLAUDE_CODE_DISABLE_1M_CONTEXT') | Should -Be $false
    }
    It '1M: 清除模板遗留 DISABLE（PSCustomObject）' {
        $env_ = '{"CLAUDE_CODE_DISABLE_1M_CONTEXT":"1"}' | ConvertFrom-Json
        Set-ContextWindowEnv -EnvObject $env_ -ContextWindowSize 1000000
        $env_.CLAUDE_CODE_AUTO_COMPACT_WINDOW | Should -Be '1000000'
        $env_.PSObject.Properties['CLAUDE_CODE_DISABLE_1M_CONTEXT'] | Should -BeNullOrEmpty
    }
}

Describe 'Get-Config / Save-Config' {
    It 'roundtrip 保留字段' {
        # 项目路径用 $TestDrive 拼接的占位字符串（本测试仅做 JSON 往返、不触盘）。
        # 不得硬编码盘符路径 —— Get-SortedProjects 会清理不存在的目录，见"测试卫生守卫"用例。
        $projPath = Join-Path $TestDrive 'roundtrip-proj'
        $cfg = @{
            models = @(@{ id = 'm1'; name = 'Model 1'; configFile = 'settings-m1.json'; contextWindow = '1M'; usageCount = 3 })
            defaultModel = 'm1'
            defaultPermission = 'yes'
            projects = @(@{ path = $projPath; usageCount = 1 })
        }
        Save-Config $cfg
        $r = Get-Config
        $r | Should -Not -BeNullOrEmpty
        $r.models[0].id | Should -Be 'm1'
        $r.models[0].usageCount | Should -Be 3
        $r.defaultModel | Should -Be 'm1'
        $r.defaultPermission | Should -Be 'yes'
        $r.projects[0].path | Should -Be $projPath
    }
    It '旧配置缺字段时 Get-Config 可读且缺字段为 null' {
        $configPath2 = $configPath
        Set-Content -LiteralPath $configPath -Value '{"models":[{"id":"old1","name":"Old","configFile":"s.json"}],"defaultModel":"old1"}' -Encoding UTF8
        $r = Get-Config
        $r | Should -Not -BeNullOrEmpty
        $r.models[0].id | Should -Be 'old1'
        $r.models[0].usageCount | Should -BeNullOrEmpty
        $r.defaultPermission | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-PermissionModeIndex' {
    It 'yes 映射到 bypassPermissions（索引 4）' {
        ConvertTo-PermissionModeIndex -DefaultPermission 'yes' | Should -Be 4
    }
    It 'no 映射到 default（索引 0）' {
        ConvertTo-PermissionModeIndex -DefaultPermission 'no' | Should -Be 0
    }
    It '无效值回退 default（索引 0）' {
        ConvertTo-PermissionModeIndex -DefaultPermission 'bogus' | Should -Be 0
        ConvertTo-PermissionModeIndex -DefaultPermission '' | Should -Be 0
    }
    It '索引回读模式名与 $script:PermissionModes 一致' {
        $script:PermissionModes[4].mode | Should -Be 'bypassPermissions'
        $script:PermissionModes.Count | Should -Be 6
    }
}

Describe 'Get-SortedModels / Get-SortedProjects 单元素不解包' {
    It '单模型时仍返回数组（Count=1 而非键数）' {
        # Get-SortedProjects 会清理磁盘上不存在的目录，项目路径必须是真实存在的目录
        # （2026-10-28 CI 事故：硬编码 D:\cboot 在 runner 上不存在被自动清理，返回空数组）
        $projDir = Join-Path $TestDrive 'proj'
        New-Item -ItemType Directory -Path $projDir -Force | Out-Null
        $cfg = @{
            models = @(@{ id = 'only'; name = 'Only'; configFile = 'settings-only.json'; usageCount = 0 })
            defaultModel = 'only'
            defaultPermission = 'no'
            projects = @(@{ path = $projDir; usageCount = 0 })
        }
        Save-Config $cfg
        $m = Get-SortedModels
        ($m -is [System.Array]) | Should -Be $true
        $m.Count | Should -Be 1
        $m[0].id | Should -Be 'only'
        $p2 = Get-SortedProjects
        ($p2 -is [System.Array]) | Should -Be $true
        $p2.Count | Should -Be 1
        $p2[0].path | Should -Be $projDir
    }
    It '无效目录被清理并写回配置（removedCount>0 分支）' {
        # 覆盖 cboot.ps1 Get-SortedProjects 清理写回分支：一个存在 + 一个不存在
        $keepDir = Join-Path $TestDrive 'proj-keep'
        New-Item -ItemType Directory -Path $keepDir -Force | Out-Null
        $cfg = @{
            models = @(@{ id = 'm'; name = 'M'; configFile = 's.json'; usageCount = 0 })
            defaultModel = 'm'
            defaultPermission = 'no'
            projects = @(
                @{ path = $keepDir; usageCount = 2 }
                @{ path = (Join-Path $TestDrive 'proj-gone'); usageCount = 5 }  # 从不创建，必然不存在
            )
        }
        Save-Config $cfg
        $p = Get-SortedProjects
        ($p -is [System.Array]) | Should -Be $true
        $p.Count | Should -Be 1
        $p[0].path | Should -Be $keepDir
        # 清理写回：磁盘配置只剩有效条目
        $r = Get-Config
        $r.projects.Count | Should -Be 1
        $r.projects[0].path | Should -Be $keepDir
        $script:removedProjectsCount | Should -Be 1
    }
    It '缺 path 的畸形条目按无效目录清理（PS5.1/PS7 行为统一）' {
        # cboot.ps1 曾对缺 path 条目直接 Test-Path -LiteralPath $null：PS7 终止单条语句
        # 静默改写磁盘配置、PS5.1 终止迭代体静默吞条目，行为分歧。现显式 IsNullOrEmpty 防御。
        $validDir = Join-Path $TestDrive 'proj-valid'
        New-Item -ItemType Directory -Path $validDir -Force | Out-Null
        $cfg = @{
            models = @(@{ id = 'm'; name = 'M'; configFile = 's.json'; usageCount = 0 })
            defaultModel = 'm'
            defaultPermission = 'no'
            projects = @(
                @{ path = $validDir; usageCount = 1 }
                @{ usageCount = 9 }   # 畸形条目：缺 path 字段
            )
        }
        Save-Config $cfg
        $p = Get-SortedProjects
        ($p -is [System.Array]) | Should -Be $true
        $p.Count | Should -Be 1
        $p[0].path | Should -Be $validDir
        # 畸形条目已从磁盘配置清理
        $r = Get-Config
        $r.projects.Count | Should -Be 1
        $script:removedProjectsCount | Should -Be 1
    }
}

Describe 'New-SettingsTemplate 复用旧模板（PSCustomObject 缺键）' {
    It 'env 缺键时不抛错且五键全部写入' {
        # 复用场景：CONFIG_DIR 已有一个 env 缺 ANTHROPIC_AUTH_TOKEN 的 settings 文件
        Set-Content -LiteralPath (Join-Path $TestDrive 'tpl.json') -Value '{"env":{"OTHER":"1"}}' -Encoding UTF8
        $CONFIG_DIR = $TestDrive
        Get-ChildItem -Path $TestDrive -Filter 'settings-*.json' | Remove-Item -Force -ErrorAction SilentlyContinue
        Copy-Item -LiteralPath (Join-Path $TestDrive 'tpl.json') -Destination (Join-Path $TestDrive 'settings-old.json') -Force
        $ok = New-SettingsTemplate -modelId 'm9' -configFile 'settings-new.json' -authToken 'tok' -baseUrl 'https://x' -opusModel 'm9' -sonnetModel 'm9' -haikuModel 'h9' -contextWindowSize 1000000
        $ok | Should -Be $true
        $s = Get-Content -LiteralPath (Join-Path $TestDrive 'settings-new.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $s.env.ANTHROPIC_AUTH_TOKEN | Should -Be 'tok'
        $s.env.ANTHROPIC_BASE_URL | Should -Be 'https://x'
        $s.env.ANTHROPIC_DEFAULT_HAIKU_MODEL | Should -Be 'h9'
        $s.env.CLAUDE_PROFILE | Should -Be 'm9'
        $s.model | Should -Be 'm9'
    }
}

Describe 'Start-Claude TTY 继承回归（claude --print 瞬退）' {
    # 2026-10-28 事故：& claude @claudeArgs | Out-Host 把 stdout 变成管道，claude 检测
    # stdout 非 TTY 后切入 --print 模式，无 prompt 报 "Input must be provided either
    # through stdin or as a prompt argument when using --print" 瞬间退出（录屏实证）。
    # TTY 继承无法在 CI 中真实模拟，故用源码断言锁定两个必要条件。
    BeforeAll {
        $script:Src = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'cboot.ps1') -Raw -Encoding UTF8
        $script:AstErrors = $null
        $script:CbootAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $script:Src, [ref]$null, [ref]$script:AstErrors)
    }

    It 'cboot.ps1 可解析（无 AST 错误）' {
        $script:AstErrors | Should -BeNullOrEmpty
    }

    It 'Start-Claude 内 & claude 直调行不含管道' {
        $fn = $script:CbootAst.FindAll(
            { param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Start-Claude' },
            $true) | Select-Object -First 1
        $fn | Should -Not -BeNullOrEmpty
        $pipeLines = $fn.Body.Extent.Text -split "`r?`n" |
            Where-Object { $_ -match '&\s+claude\b' -and $_ -match '\|' }
        $pipeLines | Should -BeNullOrEmpty -Because '管道会让 claude 判定 stdout 非 TTY，切入 --print 模式瞬间退出'
    }

    It 'Invoke-DirectLaunch 为语句级调用（无赋值捕获）' {
        $captured = $script:Src -split "`r?`n" | Where-Object { $_ -match '=\s*Invoke-DirectLaunch\b' }
        $captured | Should -BeNullOrEmpty -Because '赋值捕获会把 Start-Claude 内 & claude 的 stdout 重定向进管道，同样触发 --print 瞬退'
    }
}

Describe '测试卫生守卫' {
    # 2026-10-28 事故：测试硬编码盘符路径在本机恰好存在、CI runner 上不存在，
    # 被 Get-SortedProjects 的无效目录清理逻辑清除后返回空数组，本地绿 CI 红。
    # 本守卫用 AST 扫描 tests/*.Tests.ps1 的字符串字面量（注释与变量自动豁免），
    # 测试所需路径一律通过 $TestDrive / Join-Path 构造。
    It '测试代码不含硬编码盘符路径（防本地绿 CI 红）' {
        $violations = foreach ($file in (Get-ChildItem -Path $PSScriptRoot -Filter '*.Tests.ps1' -File)) {
            $t = $null; $e = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$t, [ref]$e)
            $ast.FindAll(
                { param($a) $a -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $a.Value -match '^[A-Za-z]:\\' },
                $true
            ) | ForEach-Object {
                [pscustomobject]@{ File = $file.Name; Line = $_.Extent.StartLineNumber; Value = $_.Value }
            }
        }
        $violations | Should -BeNullOrEmpty -Because '硬编码盘符路径是环境依赖地雷：本机存在而 CI runner 上不存在时必挂；测试路径一律用 $TestDrive 构造'
    }
}
