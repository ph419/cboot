# cboot 现代化改造实施方案

依据 docs/reports/2026-10-28_cboot-modernization-audit.html（8/8 核心主张对抗核查通过）制定，覆盖其全部 10 条改进，按 P0/P1/P2 三批次组织。全局约束：单文件仓库，所有工作单元经依赖链串行执行，禁止并行修改 cboot.ps1。

## 刷新模型模板并清理 teammateDefaultModel 死键

批次：P0。审计改进 1+2 合并执行（同改一批文件）。teammateDefaultModel 已被 Claude Code v2.1.234 移除，现行版本忽略残留值。

- 删除 cboot.ps1 全部 teammate 相关代码共 11 处：New-SettingsTemplate 的 -teammateModel 参数（L228）与写入块（L337-347，含 teammateMode）、Initialize-Config 步骤 3/7 采集（L430-435）、确认页显示（L506）、向导调用（L580）、Add-Model 采集（L1276-1280）、向导调用（L1317）、写入（L1329-1330）、Edit-ModelConfig 显示（L1562/L1571）、编辑菜单项（L1650-1658）；Initialize-Config 向导步骤编号由 7 步重排为 6 步
- 替代通道：Add-Model 与 Edit-ModelConfig 新增可选「子代理模型」字段，写入 env.CLAUDE_CODE_SUBAGENT_MODEL（需严格生效可同时写入 CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1，要求 Claude Code ≥2.1.257），保留原 WP-009 能力的现行等价入口
- 删除 5 个 config/settings/*.example.json 中的 teammateDefaultModel 与 teammateMode 字段
- 新增 config/settings/settings-glm-5.3[1m].example.json：ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.3[1m]、ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5.3[1m]、ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5.3-flash[1m]、CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000、CLAUDE_PROFILE=glm-5.3[1m]
- 全部模板 HAIKU 槽统一改为 glm-5.3-flash[1m]（该槽跑后台任务，不跟随主模型世代；glm-4.5-air 不在官方自动切换名单）
- 运行时 Haiku 槽默认值同步修复：Initialize-Config（L427-428）与 Add-Model（L1271-1273）当前默认填 $modelId（旗舰），改为 glm-5.3-flash[1m]，输入提示注明「此槽跑后台任务，建议 flash 级模型」
- 隔离环境重生成全部 example，补齐 env.CLAUDE_PROFILE、CLAUDE_CODE_AUTO_COMPACT_WINDOW 及 claude-config.example.json models[].contextWindow，保证 example 与代码运行产物一致
- [acceptance] 重生成验收须隔离执行：dot-source cboot.ps1 后将 $CONFIG_DIR/$env:USERPROFILE 重定向到无 settings-*.json 的临时目录（走硬编码母版分支，防止覆盖用户真实配置），New-SettingsTemplate 产物与 example 逐字段 diff 为空

## 升级权限选择为 --permission-mode 六模式

批次：P0。依赖：先完成「刷新模型模板并清理 teammateDefaultModel 死键」（同改向导确认页区域）。CLI 实测支持 acceptEdits/auto/bypassPermissions/manual/dontAsk/plan 六取值，cboot 当前仅两态且硬编码 --dangerously-skip-permissions。

- Show-PermissionSelection（L1089）菜单由 2 项扩为 6 项：default/acceptEdits/plan/auto/bypassPermissions/dontAsk，各项附中文说明
- Start-Claude（L1885）参数 $noConfirm 改为 $permissionMode，统一拼接 --permission-mode <mode>，移除 --dangerously-skip-permissions 分支（bypassPermissions 等价且更规范）
- 主循环（L2064-2085）传递链改造；defaultPermission 字段保持 yes/no 存储不变，向后兼容映射为菜单默认选中项（yes→bypassPermissions、no→default）
- Initialize-Config 向导步骤 5（L465-479）与配置校验修复逻辑（L653/L835 附近）与新枚举同步
- Show-Help 权限说明文案更新
- [acceptance] 分别选 default、bypassPermissions、plan 三种模式实测 claude --settings X --permission-mode <mode> 生效

## 建立 CI 双守卫

批次：P0。无依赖。将 v1.0.9 BOM 事故（PS 5.1 一闪而过）转化为不可复发。

- 新建 .github/workflows/ci.yml：windows-latest，push master 与 pull_request 触发
- 守卫 1：扫描仓库全部 .ps1，首三字节必须为 EF BB BF（UTF-8 with BOM）
- 守卫 2：powershell.exe（PS 5.1，即事故版本）运行 [System.Management.Automation.Language.Parser]::ParseFile，解析错误数 >0 则失败；pwsh 复跑一遍双保险
- [acceptance] 本地模拟两项检查脚本均通过

## 实现会话续接组合启动

批次：P0。依赖：先完成「升级权限选择为 --permission-mode 六模式」。官方文档确认 --resume/--continue 不还原 --settings 等启动参数，「目录+套餐+续接」组合启动是 cboot 独有能力。

- claude-config.json 增加可选 lastLaunch 字段（configFile/modelId/modelName/projectPath/permissionMode/timestamp），启动成功后 Save-Config 保存
- 主菜单新增「继续上次会话」项（lastLaunch 存在且 configFile/projectPath 仍有效时显示）：直接以 claude --settings <file> --permission-mode <mode> -c 启动，usage 计数同步 +1
- Start-Claude 增加 -Continue 开关，拼接 -c
- lastLaunch 失效（配置文件或项目目录丢失）时提示并清除该字段
- [acceptance] 启动→退出→主菜单续接，确认 -c 与 --permission-mode 拼接正确且 env 生效

## 验证并修复上下文窗口与工具搜索 env 语义

批次：P1。依赖：先完成「刷新模型模板并清理 teammateDefaultModel 死键」（同改模板 env 块）。本单元两条语义问题为审计标注「未对抗核查」项，必须先验证后修改，以验证结论为准。

- 实测或查官方文档确认 CLAUDE_CODE_DISABLE_1M_CONTEXT 在窗口 <1M 时对 1M 原生模型是否强制压回 200K、是否覆盖 AUTO_COMPACT_WINDOW=500000（当前 Set-ContextWindowEnv L189-215 在 <1M 时同时写两键）
- 按验证结论修复 Set-ContextWindowEnv：倾向方案为仅当用户显式选择 200K 时才写 CLAUDE_CODE_DISABLE_1M_CONTEXT，其余窗口只写 AUTO_COMPACT_WINDOW
- 实测 ENABLE_TOOL_SEARCH="0" 在官方取值集（unset/true/auto/auto:N/false）下的真实行为（按字符串真值可能等效开启，与写 0 意图相反）
- 按验证结论处理硬编码模板 L277 的 ENABLE_TOOL_SEARCH 键：移除或改为 false
- [acceptance] 选择 500K 窗口新建模型配置，检查写入 settings 的 env 组合与用户意图一致

## 封装 Main 入口并加 dot-source 守卫

批次：P1。依赖：先完成「刷新模型模板并清理 teammateDefaultModel 死键」「升级权限选择为 --permission-mode 六模式」「实现会话续接组合启动」「验证并修复上下文窗口与工具搜索 env 语义」。顶层重构放在功能改动之后，减少冲突；同时为 Pester 铺路。

- 将 L598-2128 全部顶层交互代码封装进函数（配置校验修复循环 L598-857、projects 归一化 L859-882、主循环），可拆 Bootstrap + Main 两个函数，不建议只包主循环
- 脚本末尾加 dot-source 守卫：仅当脚本被直接运行（非 dot-source 加载）时调用 Main
- [integration] powershell.exe -File cboot.ps1 交互行为与改造前一致
- [integration] dot-source 加载零输出零交互、可重复 dot-source；保存后 cboot.ps1 编码仍为 UTF-8 with BOM

## 支持 CLI 参数直启与 extraArgs 透传

批次：P2。依赖：先完成「升级权限选择为 --permission-mode 六模式」「实现会话续接组合启动」。

- 脚本顶部解析 $args，支持 -Model/-Project/-Permission 参数跳过菜单直启（-Permission 取六模式枚举）
- Start-Claude 增加 -ExtraArgs 数组参数，以 & claude @extraArgs 数组形式展开，防引号问题
- 验证性任务（cboot.cmd 第 3 行已含 %* 透传，勿重复实现）：确认 cboot.cmd %* → cboot.ps1 $args → Start-Claude -ExtraArgs → & claude @extraArgs 端到端可用，含含空格的路径参数
- [acceptance] .\cboot.ps1 -Model <id> -Project <path> 直启成功进入 claude 会话

## 增加 effort 与 fallbackModel 透传

批次：P2。依赖：先完成「刷新模型模板并清理 teammateDefaultModel 死键」「升级权限选择为 --permission-mode 六模式」。

- claude-config.json models[] 增加可选 effort 字段，启动时透传 --effort（GLM 官方提供 /effort 映射表）
- models[] 增加可选 fallbackModel 字段，启动时透传 --fallback-model 组成回退链
- Add-Model 与 Edit-ModelConfig 向导增加上述两项可选输入（留空跳过）
- 模板 env 提供可选 CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK=1 说明，供网关用户防 2.1.312 起的静默换模型
- [acceptance] 配置 effort 后启动，确认 --effort 值正确拼接

## 实现环境体检

批次：P2。依赖：先完成「刷新模型模板并清理 teammateDefaultModel 死键」「升级权限选择为 --permission-mode 六模式」。

- 实现环境体检：claude --version 与最新版本比较、settings-*.json 废弃键扫描（维护废弃键清单，首项 teammateDefaultModel）、claude auth status 可用性检测（实现时先验证本机 claude 是否存在该子命令，不存在则降级为提示）
- 主菜单新增「环境体检」入口，结果输出到终端
- [acceptance] 实测各体检项输出正确

## 建立 Pester 单元测试

批次：P2。依赖：先完成「建立 CI 双守卫」「验证并修复上下文窗口与工具搜索 env 语义」「封装 Main 入口并加 dot-source 守卫」。

- 新建 tests/ 目录，Pester 5.x 约定
- [unit] Format-Json 输出格式断言（2 空格缩进）
- [unit] Parse-ContextWindow 边界用例（200K/500K/1M/非法输入）
- [unit] Set-ContextWindowEnv 各窗口档位写入的 env 组合断言
- [unit] Get-Config/Save-Config roundtrip 与旧配置缺字段兼容
- [unit] defaultPermission yes/no → 六模式映射函数
- [integration] CI workflow 接入 Pester job 并全绿

## 修正文档并固化明确不做清单

批次：P2。依赖：先完成「支持 CLI 参数直启与 extraArgs 透传」「增加 effort 与 fallbackModel 透传」「实现环境体检」「建立 Pester 单元测试」。文档收尾必须放在全部功能之后。

- README 新增功能文档：权限六模式、会话续接、CLI 参数直启、effort/fallback、环境体检、Pester 测试运行方式
- README 补配置语义说明：settings env 块同名变量在大多数会话覆盖 shell 继承值（附例外简表：Desktop/自托管 launch environment 优先、共享项目文件需信任工作区、部分变量项目/本地文件禁设）
- README 补 Haiku 槽提示文案：说明其跑后台任务的后台语义与额度影响
- README 补子代理模型手动定制路径：env.CLAUDE_CODE_SUBAGENT_MODEL（可选 CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1）
- README 固化「明确不做」清单：fast-mode 预设（token+自定义 BASE_URL 被组织检查拦截）、中途切换代理（ccr 领域）、用量面板（非启动器职责）；注明「中途换模型用 /model，permissions/hooks 热重载免重启」
- README 维护性要点：每季度复查官方原生 profile/多配置切换进展（issue #30031/#18435），若落地需重估本项目价值
- 移除 README L207 的 teammateDefaultModel 功能描述（已废弃键）
- 版本号升级 v1.0.12，三处同步：README 徽章、CHANGELOG.md 新条目、.wolf/cerebrum.md 描述行
- [acceptance] README 与实际行为逐项核对无过期描述

## 成功标准

- cboot.ps1 与 config/ 目录内 grep -in teammate 零命中；README 旧 teammateDefaultModel 描述已移除；CHANGELOG、task.md、docs/wp、docs/reports 为历史记录白名单不改动
- 隔离环境重生成验收通过：全部 example 与硬编码母版产物逐字段一致，含 env.CLAUDE_PROFILE、CLAUDE_CODE_AUTO_COMPACT_WINDOW、models[].contextWindow
- CI 双守卫本地模拟通过；权限六模式与会话续接实测可用；两条未核查 env 项（DISABLE_1M_CONTEXT、ENABLE_TOOL_SEARCH）有验证记录且修改与结论一致
- powershell.exe -File cboot.ps1（PS 5.1）全流程可运行，仓库全部 .ps1 保持 UTF-8 with BOM，cboot.ps1 解析 0 错误
