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
| `release_tag` | 产物 Release tag | 自动生成（`v<版本>`） |

## 四个产物

`4-build.sh` 按顺序调用私有仓库的 `.ci/buildkit.sh <stage>`，五个阶段：

| 阶段 | 作用 | 产出（`$ARTIFACTS_DIR`） |
|---|---|---|
| `prepare` | 拉取私有审计输入、装依赖、编译本工程工具 | — |
| `vm` | 只加虚拟机层，签名出包 | `01-vm.apk` |
| `ollvm` | 在 VM 之上叠加编译器层，重新出包 | `02-vm-ollvm.apk` |
| `fog` | 以上一份**已签名**包为输入做收尾 | `03-vm-ollvm-fog.apk` |
| `module` | 独立模块单独出包 | `04-module.apk` |

四份产物随后改名为 `<包名>-<版本>.apk` / `-ollvm` / `-fog` / `<模块包名>-<版本>.apk`，
校验「恰好四份且摘要互不相同」后由 `5-upload.sh` 推到私有仓库的 Release。
版本号由 `1-setup.sh` 依 tag 递增，`4-build.sh` 写回 Gradle 配置。

阶段失败时公开日志只回显：失败阶段名、退出码、过滤后的任务名/错误标题行；
完整输出只留在 runner 临时文件里，且 `::error::` 里不出现源仓库路径。

## 缓存

工具链与构建产物都写入**目标私有仓库**的 Release（tag `toolchain` 与 `v<版本>`），
本仓库只保留脚本。
