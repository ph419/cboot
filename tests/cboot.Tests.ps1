# cboot Pester 5.x 单元测试
# 运行: Invoke-Pester -Configuration @{ Run = @{ Path = 'tests' } }
# CI 守卫要求 UTF-8 with BOM（构建后已注入 BOM）

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    # 隔离：USERPROFILE 重定向到临时目录后再 dot-source（dot-source 守卫保证零副作用）
    $script:TestHome = Join-Path $TestDrive 'home'
    New-Item -ItemType Directory -Path (Join-Path $script:TestHome '.claude') -Force | Out-Null
    $env:USERPROFILE = $script:TestHome
    . (Join-Path $script:RepoRoot 'cboot.ps1')
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
        $cfg = @{
            models = @(@{ id = 'm1'; name = 'Model 1'; configFile = 'settings-m1.json'; contextWindow = '1M'; usageCount = 3 })
            defaultModel = 'm1'
            defaultPermission = 'yes'
            projects = @(@{ path = 'D:\proj'; usageCount = 1 })
        }
        Save-Config $cfg
        $r = Get-Config
        $r | Should -Not -BeNullOrEmpty
        $r.models[0].id | Should -Be 'm1'
        $r.models[0].usageCount | Should -Be 3
        $r.defaultModel | Should -Be 'm1'
        $r.defaultPermission | Should -Be 'yes'
        $r.projects[0].path | Should -Be 'D:\proj'
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
        $cfg = @{
            models = @(@{ id = 'only'; name = 'Only'; configFile = 'settings-only.json'; usageCount = 0 })
            defaultModel = 'only'
            defaultPermission = 'no'
            projects = @(@{ path = 'D:\cboot'; usageCount = 0 })
        }
        Save-Config $cfg
        $m = Get-SortedModels
        ($m -is [System.Array]) | Should -Be $true
        $m.Count | Should -Be 1
        $m[0].id | Should -Be 'only'
        $p2 = Get-SortedProjects
        ($p2 -is [System.Array]) | Should -Be $true
        $p2.Count | Should -Be 1
        $p2[0].path | Should -Be 'D:\cboot'
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
