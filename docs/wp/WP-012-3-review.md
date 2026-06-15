# WP-012-3-review: 代码审查 + 版本号 + CHANGELOG

## 🤖 Subagent 读取指令

> **重要**: 执行此任务前，请先阅读父工作包文档获取完整上下文：
> - 父工作包: `docs/wp/WP-012.md`
> - 包含: 问题分析、验收标准、版本与文档约定

## 基本信息

| 属性 | 值 |
|------|-----|
| **类型** | review |
| **父工作包** | WP-012 |
| **依赖** | WP-012-2-verify |
| **执行角色** | reviewer |
| **状态** | 📋 待执行 |

## 职责

审查转换未引入内容篡改，更新版本号与变更记录，排查连带编码问题，沉淀经验到项目注意事项。

## 任务清单

- [ ] **内容完整性审查**：对比 `cboot.ps1.bak`（去掉 BOM 后）与转换后文件，确认除 3 字节 BOM 外逐字节一致，无逻辑/字符变更
- [ ] **README 徽章版本号更新**：确认 `README.md` 当前版本（git log 显示 v1.0.9），更新为 v1.0.10（若 review 阶段发现实际版本不同，以实际为准）
- [ ] **CHANGELOG 追加记录**：在 `CHANGELOG.md` 顶部新增条目，说明修复了 PS 5.1 一闪而过问题
- [ ] **连带编码排查**：确认 `cboot.cmd`、`config/` 下模板（`.json`）编码无连带问题（JSON 由脚本读取，受影响小，但需确认）
- [ ] **经验沉淀**：将"PS 脚本含中文必须 UTF-8 with BOM"写入项目注意事项（README 编辑注意事项 或 CLAUDE.md），避免后续再次踩坑
- [ ] 备份文件处理建议：`.bak` 确认稳定后可删除，但在 review 阶段先保留并记录

## 验收标准

- [ ] 转换后内容与 `.bak`（去 BOM）逐字节一致
- [ ] README 版本号已更新（v1.0.9 → v1.0.10 或以实际为准）
- [ ] CHANGELOG 已追加本次修复条目
- [ ] `cboot.cmd` / config 模板编码状态已确认无连带问题
- [ ] 项目注意事项已补充"含中文 PS 脚本须存为 UTF-8 with BOM"

## 关键文件

- `D:\cboot\cboot.ps1` / `D:\cboot\cboot.ps1.bak` — 内容对比
- `D:\cboot\README.md` — 版本号徽章
- `D:\cboot\CHANGELOG.md` — 变更记录
- `D:\cboot\cboot.cmd` / `D:\cboot\config\**` — 连带排查
- `D:\cboot\CLAUDE.md`（可选）— 经验沉淀

## 注意事项

- 版本号变更需与 `README.md` 徽章 + `CHANGELOG.md` 两处保持一致
- 提交信息格式：`fix: 修复 cboot.ps1 编码为 UTF-8 无 BOM 导致 PS5.1 一闪而过`
- review 阶段发现 verify 结果不达标（如 PS 5.1 仍有错误）时，不得标记完成，需回退至 WP-012-1-impl 排查
