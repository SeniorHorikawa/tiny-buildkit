# buildkit

公开 runner 上的构建脚手架。源码在运行时临时拉取，产物直接写入目标私有仓库的 Release。

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
| `ollvm_branch` | OLLVM 源码分支 | `llvm-12.x` |
| `obfuscation` | `max` / `balanced` / `off` | `max` |
| `release_tag` | 产物 Release tag | 自动生成 |
