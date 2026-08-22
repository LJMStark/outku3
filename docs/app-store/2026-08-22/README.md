# Kirole App Store 2.0 候选记录

候选日期：2026-08-22
目标版本：Kirole 2.0（Build 651）
发布标签：等待单独批准后再创建并推送 Build 651 标签；`release/appstore-2.0-build-650` 已作废
源提交：`545150129037f196748d744387c56ced1ffc5530`

这个目录只记录 App Store 候选，不替代 Internal TestFlight 649 的硬件联调记录。

当前已经完成：

- `main` 和候选标签已推送，并从远端回读到同一源提交。
- `Kirole-AppStore` / `AppStoreRelease` 模拟器构建成功。
- Internal/App Store 发布隔离检查通过。
- `swift test --no-parallel` 通过，共 1286 个测试、157 个测试组。
- 三张英文截图从 AppStoreRelease 构建直接截取，人工检查后已上传 App Store Connect，并回读到 3 张。
- 生产 BLE 密钥已生成到本机忽略文件 `fastlane/.env`，权限为 `0600`；其 Base64 文本解码后恰好为 32 字节，密钥未写入仓库或日志。
- Build 651 已归档、导出并上传，App Store Connect 处理状态为 `VALID`，内外测试组均为 0。Build 649 仍是硬件联调 TestFlight；Build 650 使用旧密钥，已作废。
- 最终归档已回读版本、签名权限并完成内部符号和工程文件扫描。

当前不能把记录改成 `READY`：

- 硬件团队尚未把同一生产密钥写入 1.3.1 固件；在此之前不能用 Build 651 判断 BLE 连接、DeviceWake 和普通同步。
- 配对 iPhone 当前也不在线，固件密钥一致后还需完成一次最小真机检查。
- App Privacy 问卷仍需按最终二进制重新核对。

全部证据见 `SUBMISSION-RECORD.md`。只有记录改成 `Status: READY` 且以下命令通过，才可选择 Build 651 送审：

```bash
./docs/app-store/2026-08-22/validate-assets.sh submission
```
