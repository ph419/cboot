# env 语义验证记录（cboot 现代化 Unit 5/8/9 依据）

日期：2026-10-28。方法：并行研究工作流（6 组问题，各含本机 2.1.308 CLI 探测 + 官方文档 + changelog + GitHub issues 交叉验证），全部结论高置信度。对应计划：docs/plan/cboot-modernization.md。

## 1. CLAUDE_CODE_DISABLE_1M_CONTEXT 与 CLAUDE_CODE_AUTO_COMPACT_WINDOW

- `DISABLE_1M_CONTEXT=1` 会把 glm-5.2[1m] 等 1M 原生模型的有效窗口压回 200K（[1m] 后缀失效，按未识别 ID 默认 200K 对待）
- `AUTO_COMPACT_WINDOW` 是官方变量，语义为**自动压缩触发阈值**（非有效窗口）
- 计划担心的「DISABLE 压窗口到 200K + 阈值 500K → 永不压缩溢出」**不存在**：官方对压缩阈值做 min(配置值, 有效窗口) 钳制
- **修改决定**（与计划倾向方案一致）：`Set-ContextWindowEnv` 仅当显式选择 200K 时写 `DISABLE_1M_CONTEXT=1` 并清除 `AUTO_COMPACT_WINDOW`；其余窗口只写 `AUTO_COMPACT_WINDOW=<size>`，消除矛盾组合
- 验收：Pester Set-ContextWindowEnv 6 用例 + 隔离重生成逐字段一致

## 2. ENABLE_TOOL_SEARCH

- 官方取值集：unset / true / auto / auto:N(0-100) / false；默认开启（unset 即延迟 MCP 工具）
- 「0」担忧不成立：2.1.308 二进制用显式布尔字面量解析器（falsy = 0/false/no/off），「0」实际等效关闭
- **修改决定**：模板统一写 `"false"`（官方文档化取值），不移除该键（GLM 网关场景官方建议 false）
- 验收：重生成 example 全部 ENABLE_TOOL_SEARCH=false

## 3. 其余结论（Unit 2/4/8/9 依据）

- `--permission-mode` 合法取值 6 个：default/acceptEdits/plan/auto/dontAsk/bypassPermissions；manual 是 default 的别名（≥2.1.200），不单列。auto/bypassPermissions 写入项目级 settings 不生效，必须 CLI 传参（cboot 正确做法）
- `CLAUDE_CODE_SUBAGENT_MODEL`/`_FORCE` 均为官方 env；_FORCE 要求 ≥2.1.257；settings env 块设置生效；两者须成对设置
- `--effort`/`--fallback-model`/`--continue`/`--settings` 均为现行 CLI flag（本机 2.1.308 --help 实测）
- `claude auth status` 存在（本机 2.1.308 实测 JSON 输出：loggedIn/authMethod/apiProvider）
- `CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK` 真实存在（二进制可寻址），=1 防止 ≥2.1.312 refusal 静默换模型
- `--resume/--continue` 不还原 `--settings` 等启动参数（官方 sessions 文档逐字确认）→「目录+套餐+续接」组合启动是必要封装
- settings env 块覆盖 shell 继承同名变量；例外：Desktop app/自托管 launch environment 优先、managed settings 最高且免信任、project/.local 禁设清单（CLAUDE_CONFIG_DIR、HOME/TMPDIR/XDG_*、系统变量、遥测导出等）

完整证据（URL + 引文 + 命令输出）存于研究工作流 journal：
`C:\Users\MECHREVO\.claude\projects\D--cboot\f3cd23f7-cf76-440f-81dc-9b372f6db504\subagents\workflows\wf_a8784684-15b\journal.jsonl`

---

## 附：v1.0.12 交付前对抗性审查处置记录（2026-10-28）

5 维度并行审查（运行时逻辑/PS5.1 兼容/模板一致性/文档准确性/CI 与测试）产出 21 个候选问题，逐项人工核验后处置如下：

已修复（13 项）：
1. H 键（-2）在模型/目录/权限三个子菜单未处理，被当索引用——权限页按 H 会以 auto 模式误启动 Claude。已加 Show-Help + continue
2. 全部项目目录失效时「按回车返回主菜单」击穿空数组防护致崩溃退出。已加空数组防护 + 撤销模型计数
3. 直启非法值报错后直接退出脚本，与「回退主菜单」承诺不符。改为布尔返回协议，失败回退 Main
4. PowerShell 函数返回单元素数组被解包（return @(...)），单模型/单项目配置下 .Count 变键数、[0] 取空。Get-SortedModels/Get-SortedProjects 改 return ,@(...) 源头修复
5. Bootstrap 修复循环对缺失的 defaultModel/defaultPermission 直接赋值抛错（旧配置缺属性）。改 Add-Member -Force
6. New-SettingsTemplate 复用 PSCustomObject 模板且 env 缺键时点赋值抛错。五键 + model 键改双分支
7. Edit-ModelConfig 字段 0-4 同样的缺键赋值问题。改 Add-Member -Force（ensure-env 改为 PSObject 统一语义）
8. Edit-ModelConfig effort/fallback 修改成功后菜单显示旧值。保存后同步 $selectedModel
9. Start-Claude 硬编码 $env:USERPROFILE\.claude，不尊重 $CUSTOM_CONFIG_DIR。改用 $CONFIG_DIR
10. 环境体检对损坏 JSON 无防护，ConvertFrom-Json 抛错中断扫描。加 per-file try/catch
11. -Permission 校验拒绝 manual 但报错文案列为合法值。文案修正
12. CHANGELOG「初始化与编辑向导」措辞与实际不符（向导在添加/编辑入口）。措辞修正
13. 4 个非 [1m] 示例模板 contextWindow=1M 与自身 [1m] 约定矛盾。按 200K 语义重生成（DISABLE_1M_CONTEXT=1，无 AUTO_COMPACT_WINDOW）

确认不修（2 项）：
- Format-Json 的 `:  +` 正则会改写 JSON 字符串值内部的「冒号+多空格」——v1.0.0 起的已知限制，正确修复需 JSON 感知格式化器，超出本计划范围（当前模板值不含该模式）
- README 菜单顺序问题经核验为审查者误报（README 与代码顺序一致）

其余为重复报告或文档类小项（已随上述修复覆盖）。修复后全量回归：PS 5.1 解析 0 错误、Pester 22/22、e2e stub 全通过、重生成 ALL PASS、CI 模拟 ALL PASS、dot-source 可重复。
