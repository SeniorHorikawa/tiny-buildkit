# buildkit

公开 runner 上的构建脚手架。源码在运行时临时拉取，产物与工具链缓存都写入目标私有仓库。

## 配置

**1. Secret**（Settings → Secrets and variables → Actions → Secrets）

`SRC_TOKEN`（或 `Actions`）：

- Fine-grained token，Repository access → Only select repositories → 选中目标私有仓库
- Permissions → Repository permissions → **Contents: Read and write**
- Metadata 会自动是 Read-only，其余保持 No access

**2. Variable**（同一页面的 Variables）

`SRC_REPO` = `<owner>/<repo>`

## 运行

Actions → **Build** → Run workflow。

| 输入 | 说明 | 默认 |
|---|---|---|
| `source_repo` | 覆盖 `SRC_REPO` | 空 |
| `source_ref` | 分支 / tag / commit | 空（默认分支） |
| `toolchain_version` | 工具链版本 | `1.11.0` |
| `obfuscation` | `on` / `off`（对照用） | `on` |
| `release_tag` | 产物 Release tag | 自动生成 |

## 缓存

工具链与构建产物都写入**目标私有仓库**的 Release（tag `toolchain` 与 `ci-<版本>-<运行号>`），
本仓库只保留脚本。
