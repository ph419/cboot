# WP-012-2-verify: 多环境编码验证

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-012.md`
> - 包含: 问题分析、验证标准、验证命令

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | verify |
| **父工作包** | WP-012 |
| **依赖** | WP-012-1-impl |
| **执行角色** | tester |
| **状态** | 📋 待执行 |

## 职责

在多个环境/维度验证 WP-012-1-impl 的转换结果：BOM 字节、PS 5.1 解析、PS 7 解析、实际启动、全项目脚本扫描。**本子包是 WP-012 的核心**——修复操作很简单，价值在于证明问题真正消除且无回归。

## 任务清单

- [ ] **BOM 字节检查**：首三字节 `EF BB BF`
- [ ] **PS 5.1 AST 解析**（必须通过 `powershell.exe` 调用，确保走 5.1 引擎）→ 期望 **0 错误**（修复前 37 条）：
  ```powershell
  powershell.exe -NoProfile -Command "$err=$null; $null=[System.Management.Automation.Language.Parser]::ParseFile('D:\cboot\cboot.ps1',[ref]$null,[ref]$err); $err.Count"
  ```
- [ ] **PS 7 AST 解析**（pwsh 当前环境）→ 期望 **0 错误**（无回归）：
  ```powershell
  $err=$null; $null=[System.Management.Automation.Language.Parser]::ParseFile('D:\cboot\cboot.ps1',[ref]$null,[ref]$err); $err.Count
  ```
- [ ] **实际启动**：执行 `D:\cboot\cboot.cmd`，确认进入主菜单（不再一闪而过）。若在无 TTY 环境无法交互，至少确认进程未立即退出、能渲染菜单首屏
- [ ] **全项目其他 `.ps1` 编码扫描**：列出每个 `.ps1` 的 BOM 状态，标记是否存在同类隐患：
  ```powershell
  Get-ChildItem -Path 'D:\cboot' -Recurse -Include *.ps1,*.psm1,*.psd1 -File |
    ForEach-Object { $b=[System.IO.File]::ReadAllBytes($_.FullName); [PSCustomObject]@{ File=$_.FullName; HasBOM=($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) } }
  ```
- [ ] 记录对照基准：`scripts\test-context-window.ps1`（已有 BOM，应保持不变）

## 验收标准

- [ ] `cboot.ps1` 首三字节 `EF BB BF`
- [ ] PS 5.1 AST 解析 **0 错误**（37 → 0）
- [ ] PS 7 AST 解析 **0 错误**（无回归）
- [ ] `cboot.cmd` 能进入主菜单
- [ ] 全项目 `.ps1` 编码状态表已输出，无中文 .ps1 缺 BOM 的遗漏（cboot.ps1 外的脚本若含中文且无 BOM 需单独标记）

## 关键文件

- `D:\cboot\cboot.ps1` — 验证对象
- `D:\cboot\cboot.cmd` — 启动入口
- `D:\cboot\scripts\*.ps1` — 扫描范围

## 验证方法（端到端）

```powershell
# 1. BOM 检查
$bytes = [System.IO.File]::ReadAllBytes('D:\cboot\cboot.ps1')
($bytes[0..2] | ForEach-Object { $_.ToString('X2') }) -join ' '   # 期望: EF BB BF

# 2. PS 5.1 AST 解析（powershell.exe 走 5.1 引擎）
powershell.exe -NoProfile -Command "$err=$null; $null=[System.Management.Automation.Language.Parser]::ParseFile('D:\cboot\cboot.ps1',[ref]$null,[ref]$err); $err.Count"   # 期望: 0

# 3. PS 7 AST 解析（pwsh）
$err=$null; $null=[System.Management.Automation.Language.Parser]::ParseFile('D:\cboot\cboot.ps1',[ref]$null,[ref]$err); $err.Count   # 期望: 0

# 4. 实际启动（cmd 入口）
D:\cboot\cboot.cmd   # 期望: 进入主菜单，不闪退
```

## 注意事项

- PS 5.1 验证**必须**用 `powershell.exe`（不是 pwsh），否则不会复现真实双击环境
- 若 `cboot.cmd` 实际启动需要交互式 TTY 而当前环境无法提供，可退化为：`powershell.exe -NoProfile -File D:\cboot\cboot.ps1` 观察是否进入菜单渲染阶段而非立即报错退出
- 验证结果（错误数、BOM 状态表、启动行为）需如实记录，写入完成报告
