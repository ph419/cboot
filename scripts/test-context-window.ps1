<#
.SYNOPSIS
    Set-ContextWindowEnv 独立测试脚本（WP-010-3）

.DESCRIPTION
    自包含测试：原样复制 cboot.ps1:188-218 的 Set-ContextWindowEnv 实现（方式 A），
    覆盖 hashtable / PSCustomObject 双类型、<1M / >=1M 双分支、模板残留场景及端到端复现。

    用法：
        pwsh scripts/test-context-window.ps1
        powershell -File scripts/test-context-window.ps1

    退出码：全 PASS → 0；任一 FAIL → 1
#>

# ============================================================
# 被测函数：原样复制自 cboot.ps1:188-218（不得偏离）
# ============================================================
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

# ============================================================
# 断言辅助
# ============================================================
$script:passed = 0
$script:failed = 0

function Assert-True {
    param(
        [bool]$Condition,
        [string]$CaseName,
        [string]$Reason
    )
    if ($Condition) {
        Write-Host "[PASS] $CaseName"
        $script:passed++
    } else {
        Write-Host "[FAIL] $($CaseName): $($Reason)"
        $script:failed++
    }
}

# hashtable / PSCustomObject 字段探测统一封装
function Test-HasField {
    param([object]$Obj, [string]$Field)
    if ($Obj -is [hashtable]) {
        return $Obj.ContainsKey($Field)
    } else {
        return $null -ne $Obj.PSObject.Properties[$Field]
    }
}

function Get-FieldValue {
    param([object]$Obj, [string]$Field)
    if ($Obj -is [hashtable]) {
        return $Obj[$Field]
    } else {
        return $Obj.$Field
    }
}

# ============================================================
# 用例 1：hashtable + 1M → 无 DISABLE_1M_CONTEXT、AUTO_COMPACT_WINDOW=1000000
# ============================================================
$env1 = @{ 'API_KEY' = 'k1' }
Set-ContextWindowEnv -EnvObject $env1 -ContextWindowSize 1000000
$compact1 = Get-FieldValue -Obj $env1 -Field 'CLAUDE_CODE_AUTO_COMPACT_WINDOW'
$ok1 = (-not (Test-HasField -Obj $env1 -Field 'CLAUDE_CODE_DISABLE_1M_CONTEXT')) -and
       (Test-HasField -Obj $env1 -Field 'CLAUDE_CODE_AUTO_COMPACT_WINDOW') -and
       ($compact1 -eq '1000000')
Assert-True $ok1 `
    '用例1: hashtable+1M 无DISABLE_1M_CONTEXT, AUTO_COMPACT_WINDOW=1000000' `
    ('期望无DISABLE_1M_CONTEXT且AUTO_COMPACT_WINDOW=1000000，实际 DISABLE_1M_CONTEXT存在={0}, AUTO_COMPACT_WINDOW={1}' -f (Test-HasField -Obj $env1 -Field 'CLAUDE_CODE_DISABLE_1M_CONTEXT'), $compact1)

# ============================================================
# 用例 2：hashtable + 200K → DISABLE_1M_CONTEXT="1"、AUTO_COMPACT_WINDOW="200000"
# ============================================================
$env2 = @{ 'API_KEY' = 'k2' }
Set-ContextWindowEnv -EnvObject $env2 -ContextWindowSize 200000
$disable2 = Get-FieldValue -Obj $env2 -Field 'CLAUDE_CODE_DISABLE_1M_CONTEXT'
$compact2 = Get-FieldValue -Obj $env2 -Field 'CLAUDE_CODE_AUTO_COMPACT_WINDOW'
$ok2 = (Test-HasField -Obj $env2 -Field 'CLAUDE_CODE_DISABLE_1M_CONTEXT') -and
       ($disable2 -eq '1') -and
       (Test-HasField -Obj $env2 -Field 'CLAUDE_CODE_AUTO_COMPACT_WINDOW') -and
       ($compact2 -eq '200000')
Assert-True $ok2 `
    '用例2: hashtable+200K DISABLE_1M_CONTEXT=1, AUTO_COMPACT_WINDOW=200000' `
    ('实际 DISABLE_1M_CONTEXT={0}, AUTO_COMPACT_WINDOW={1}' -f $disable2, $compact2)

# ============================================================
# 用例 3（核心根因场景）：PSCustomObject + 1M（env 预含 200K 残留两字段）
#   → 无 DISABLE_1M_CONTEXT、AUTO_COMPACT_WINDOW=1000000（残留 200000 被覆盖）
# ============================================================
$env3 = [PSCustomObject]@{ 'API_KEY' = 'k3' }
# 先模拟 200K 模板残留
$env3 | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_DISABLE_1M_CONTEXT' -Value '1'
$env3 | Add-Member -MemberType NoteProperty -Name 'CLAUDE_CODE_AUTO_COMPACT_WINDOW' -Value '200000'
# 确认残留确实存在（前置条件）
$preCondition = (Test-HasField -Obj $env3 -Field 'CLAUDE_CODE_DISABLE_1M_CONTEXT') -and
                (Test-HasField -Obj $env3 -Field 'CLAUDE_CODE_AUTO_COMPACT_WINDOW')
if (-not $preCondition) {
    Write-Host "[FAIL] 用例3前置条件失败: 残留字段未成功注入"
    $script:failed++
} else {
    Set-ContextWindowEnv -EnvObject $env3 -ContextWindowSize 1000000
    $compact3 = Get-FieldValue -Obj $env3 -Field 'CLAUDE_CODE_AUTO_COMPACT_WINDOW'
    $ok3 = (-not (Test-HasField -Obj $env3 -Field 'CLAUDE_CODE_DISABLE_1M_CONTEXT')) -and
           (Test-HasField -Obj $env3 -Field 'CLAUDE_CODE_AUTO_COMPACT_WINDOW') -and
           ($compact3 -eq '1000000')
    Assert-True $ok3 `
        '用例3(根因): PSCustomObject+1M 预含200K残留 → 无DISABLE_1M_CONTEXT, AUTO_COMPACT_WINDOW=1000000(覆盖200000)' `
        ('期望无DISABLE_1M_CONTEXT且AUTO_COMPACT_WINDOW=1000000，实际 DISABLE_1M_CONTEXT存在={0}, AUTO_COMPACT_WINDOW={1}' -f (Test-HasField -Obj $env3 -Field 'CLAUDE_CODE_DISABLE_1M_CONTEXT'), $compact3)
}

# ============================================================
# 用例 4：PSCustomObject + 1M（env 无残留）→ AUTO_COMPACT_WINDOW=1000000
# ============================================================
$env4 = [PSCustomObject]@{ 'API_KEY' = 'k4' }
Set-ContextWindowEnv -EnvObject $env4 -ContextWindowSize 1000000
$compact4 = Get-FieldValue -Obj $env4 -Field 'CLAUDE_CODE_AUTO_COMPACT_WINDOW'
$ok4 = (-not (Test-HasField -Obj $env4 -Field 'CLAUDE_CODE_DISABLE_1M_CONTEXT')) -and
       (Test-HasField -Obj $env4 -Field 'CLAUDE_CODE_AUTO_COMPACT_WINDOW') -and
       ($compact4 -eq '1000000')
Assert-True $ok4 `
    '用例4: PSCustomObject+1M 无残留 无DISABLE_1M_CONTEXT, AUTO_COMPACT_WINDOW=1000000' `
    ('期望无DISABLE_1M_CONTEXT且AUTO_COMPACT_WINDOW=1000000，实际 DISABLE_1M_CONTEXT存在={0}, AUTO_COMPACT_WINDOW={1}' -f (Test-HasField -Obj $env4 -Field 'CLAUDE_CODE_DISABLE_1M_CONTEXT'), $compact4)

# ============================================================
# 用例 5：PSCustomObject + 500K → DISABLE_1M_CONTEXT="1"、AUTO_COMPACT_WINDOW="500000"
# ============================================================
$env5 = [PSCustomObject]@{ 'API_KEY' = 'k5' }
Set-ContextWindowEnv -EnvObject $env5 -ContextWindowSize 500000
$disable5 = Get-FieldValue -Obj $env5 -Field 'CLAUDE_CODE_DISABLE_1M_CONTEXT'
$compact5 = Get-FieldValue -Obj $env5 -Field 'CLAUDE_CODE_AUTO_COMPACT_WINDOW'
$ok5 = (Test-HasField -Obj $env5 -Field 'CLAUDE_CODE_DISABLE_1M_CONTEXT') -and
       ($disable5 -eq '1') -and
       (Test-HasField -Obj $env5 -Field 'CLAUDE_CODE_AUTO_COMPACT_WINDOW') -and
       ($compact5 -eq '500000')
Assert-True $ok5 `
    '用例5: PSCustomObject+500K DISABLE_1M_CONTEXT=1, AUTO_COMPACT_WINDOW=500000' `
    ('实际 DISABLE_1M_CONTEXT={0}, AUTO_COMPACT_WINDOW={1}' -f $disable5, $compact5)

# ============================================================
# 用例 6（端到端复现）：200K settings 模板 PSCustomObject（env 含两残留字段）
#   → 调用 Set-ContextWindowEnv 模拟 New-SettingsTemplate 的 1M 路径
#   → ConvertTo-Json 序列化 → 断言 JSON 无 DISABLE_1M_CONTEXT、含 AUTO_COMPACT_WINDOW=1000000
# ============================================================
# 构造一个完整的 200K settings 模板（PSCustomObject，env 含两残留字段）
$settings200k = [PSCustomObject]@{
    ANTHROPIC_API_KEY = 'sk-200k-template'
    env = [PSCustomObject]@{
        ANTHROPIC_API_KEY                 = 'sk-200k-template'
        ANTHROPIC_BASE_URL                = 'https://api.example.com'
        CLAUDE_CODE_DISABLE_1M_CONTEXT    = '1'        # 200K 残留
        CLAUDE_CODE_AUTO_COMPACT_WINDOW   = '200000'   # 200K 残留
    }
    permissions = [PSCustomObject]@{
        allow = @('Read', 'Write')
    }
}

# 模拟 New-SettingsTemplate 复用此模板新建 1M 模型：对 env 调用 Set-ContextWindowEnv（1M 路径）
Set-ContextWindowEnv -EnvObject $settings200k.env -ContextWindowSize 1000000

# ConvertTo-Json 序列化（与 cboot.ps1 实际保存行为一致）
$jsonText = $settings200k | ConvertTo-Json -Depth 10

$jsonHasDisable = $jsonText -match 'CLAUDE_CODE_DISABLE_1M_CONTEXT'
$jsonHasCompact = $jsonText -match 'CLAUDE_CODE_AUTO_COMPACT_WINDOW'
$jsonCompactIs1000000 = $jsonText -match 'CLAUDE_CODE_AUTO_COMPACT_WINDOW["\s]*:\s*"1000000"'
Assert-True `
    (-not $jsonHasDisable -and $jsonHasCompact -and $jsonCompactIs1000000) `
    '用例6(端到端): 200K模板→新建1M→JSON序列化 无DISABLE_1M_CONTEXT, 含AUTO_COMPACT_WINDOW=1000000' `
    ('JSON 断言不匹配：DISABLE_1M_CONTEXT存在={0}, AUTO_COMPACT_WINDOW存在={1}, 值=1000000={2}' -f $jsonHasDisable, $jsonHasCompact, $jsonCompactIs1000000)

# ============================================================
# 用例 7（可选，>1M 边界）：PSCustomObject + 2M（2000000）
#   → 无 DISABLE_1M_CONTEXT、AUTO_COMPACT_WINDOW=2000000
# ============================================================
$env7 = [PSCustomObject]@{ 'API_KEY' = 'k7' }
Set-ContextWindowEnv -EnvObject $env7 -ContextWindowSize 2000000
$compact7 = Get-FieldValue -Obj $env7 -Field 'CLAUDE_CODE_AUTO_COMPACT_WINDOW'
$ok7 = (-not (Test-HasField -Obj $env7 -Field 'CLAUDE_CODE_DISABLE_1M_CONTEXT')) -and
       (Test-HasField -Obj $env7 -Field 'CLAUDE_CODE_AUTO_COMPACT_WINDOW') -and
       ($compact7 -eq '2000000')
Assert-True $ok7 `
    '用例7: PSCustomObject+2M 无DISABLE_1M_CONTEXT, AUTO_COMPACT_WINDOW=2000000' `
    ('期望无DISABLE_1M_CONTEXT且AUTO_COMPACT_WINDOW=2000000，实际 DISABLE_1M_CONTEXT存在={0}, AUTO_COMPACT_WINDOW={1}' -f (Test-HasField -Obj $env7 -Field 'CLAUDE_CODE_DISABLE_1M_CONTEXT'), $compact7)

# ============================================================
# 汇总
# ============================================================
Write-Host ""
Write-Host "Passed: $($script:passed) / Failed: $($script:failed)"

if ($script:failed -gt 0) {
    exit 1
} else {
    exit 0
}
