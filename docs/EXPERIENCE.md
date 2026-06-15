# 项目经验库

记录开发过程中的经验教训，供未来会话与团队成员参考，避免重复踩坑。

## 索引

| 标签 | 经验 | 来源 | 日期 |
|------|------|------|------|
| [编码规范] | 含中文的 PS 脚本必须 UTF-8 with BOM | WP-012 | 2026-06-15 |

---

## [编码规范] 含中文的 PowerShell 脚本必须存为 UTF-8 with BOM

**错误现象**: 双击 `cboot.cmd`（或 `.ps1`）运行时窗口「一闪而过」，PowerShell 立即退出，无任何输出。

**问题描述**: `cboot.ps1` 为 UTF-8 **无 BOM** 编码，含大量中文注释与字符串。在 Windows PowerShell 5.1（双击 / `cboot.cmd` 默认调用的 `powershell.exe`）下，无 BOM 的 `.ps1` 按系统 ANSI 代码页（中文系统为 GBK/CP936）解码，而非 UTF-8。

**原因分析**: 中文 UTF-8 字节中部分值（`0x22`=`"`、`0x7D`=`}`、`0x29`=`)`）在 GBK 解码后被当作合法 ASCII 符号，打乱字符串终止符与大括号配对，触发数十条 AST 解析错误（本次为 37 条），脚本根本未能解析、PowerShell 立即抛错退出。PS 7（pwsh）默认按 UTF-8 解码，故开发者无感——问题在开发期完全隐蔽，只在终端用户（双击 / `powershell.exe`）侧爆发。

**解决方案**:
```powershell
# 将 .ps1 转为 UTF-8 with BOM（仅前置 EF BB BF，正文逐字节不变）
$src = 'D:\cboot\cboot.ps1'
$content = Get-Content -LiteralPath $src -Raw -Encoding UTF8
$utf8Bom = New-Object System.Text.UTF8Encoding($true)   # $true = emit BOM
[System.IO.File]::WriteAllText($src, $content, $utf8Bom)
```

验证：
```powershell
# 1. 首三字节
([System.IO.File]::ReadAllBytes($src))[0..2] | ForEach-Object { $_.ToString('X2') }   # 期望: EF BB BF
# 2. PS 5.1 AST 解析（必须用 powershell.exe 走 5.1 引擎）
powershell.exe -NoProfile -Command "$err=$null; $null=[System.Management.Automation.Language.Parser]::ParseFile('$src',[ref]$null,[ref]$err); $err.Count"   # 期望: 0
```

**适用场景**:
- 任何含非 ASCII（中文等）字符的 `.ps1` / `.psm1` / `.psd1`
- 纯 ASCII 文件（如 `cboot.cmd`）不受影响，可保持无 BOM
- JSON 配置由脚本以 `-Encoding UTF8` 显式读取，BOM 探测不影响运行

**关键陷阱**:
- ⚠️ 不要用记事本/编辑器「另存为 UTF-8」——多数编辑器默认**不加 BOM**，会再次触发本问题
- 必须显式用 `UTF8Encoding($true)`（`$true` = emit BOM）写入
- 开发期务必在 `powershell.exe`（5.1）下验证，pwsh 下「能跑」不代表用户侧能跑

**来源工作包**: WP-012
**记录日期**: 2026-06-15
**沉淀位置**: `CLAUDE.md`「编码规范」段（项目核心约束，每次会话自动加载）
