# Kirole App Store 历史诊断与首发准备包

诊断日期：2026-08-14

历史检查点：Kirole 2.0，Build 644，Git `fd56bf7`

当前状态：**BLOCKED — 不是可上传的 App Store 提交包**

这个目录保留 Build 644 的上架诊断、已核对的英文元数据和下一次候选包的操作模板。不要把目录日期或历史检查点改写成新的候选版本。双配置（`InternalRelease` / `AppStoreRelease`）已于 2026-08-15 落地；真正出候选包时应新建 `docs/app-store/YYYY-MM-DD/`，复制仍适用的模板，并记录实际 release tag、构建号和验收证据。

## 当前可用内容

- `metadata-en.md`：已核对的英文元数据草稿。
- `CAPTURE.md`：面向 `Kirole-AppStore` / `AppStoreRelease` 的归档和截图流程。双配置与 scheme 已于 2026-08-15 落地，但内部工具尚未迁出 App Store 二进制，且本目录没有可上传截图，因此当前仍不能执行正式归档。
- `SUBMISSION-RECORD.md`：候选包验收记录模板，目前保持 `BLOCKED`。
- `validate-assets.sh`：素材包和正式提交两种校验模式。

本目录没有可上传截图。简中截图和元数据也已撤出；产品完成简中本地化并重新审阅前，不应在 App Store Connect 建立简中素材版本。

## 为什么撤出原截图

- 场景图重新拼出了 Build 644 中并不存在的界面结构。
- 专注图重排了真实组件，不是 App 正在使用时的完整页面。
- 角色图把界面里的截断文字放大成卖点。
- 时间线素材含有表情符号，不符合仓库文档规范。
- 伙伴图的英文标题不够自然。
- 两套联系表只复制扁平 PNG，源图变化后容易过期。

这些文件不应以“营销覆盖”或“后续审阅稿”的名义留在可上传目录。新截图必须保留正式候选包的真实界面结构；可以在界面外添加营销标题，但不能重排、补造或隐藏 App 组件。

## 双构建发布边界

完整规则见仓库根目录 `AGENTS.md` 的 `Release Channel Policy`。上架材料必须遵守以下边界：

- Internal TestFlight 使用 `Kirole-Internal` / `InternalRelease`，Release 优化并包含全部内部调试工具，只上传为 TestFlight Internal Only。
- App Store 使用 `Kirole-AppStore` / `AppStoreRelease`，内部调试界面、行为、日志、工厂命令和测试捷径必须在编译阶段排除。
- 只维护一个长期 `main`。产品功能经过用户明确确认后，以小型 PR 晋级 App Store；调试和工厂能力永不晋级。
- Internal 验收和 App Store 候选是不同二进制。Internal 验收不能替代 App Store 候选包的负向门控和真机冒烟测试。
- TestFlight 收据判断只能作为辅助信号，不能作为正式包隔离的主要边界。

## 当前上架阻断项

1. ~~工程仍只有 `Debug` / `Release` 和一个 `Kirole` Scheme；`InternalRelease` / `AppStoreRelease` 尚未实现。~~ **已实现 2026-08-15**：双配置（项目 + 全部 target）+ `Kirole-Internal` / `Kirole-AppStore` 共享 scheme + fastlane `release`（Internal 渠道）/ `appstore`（候选包）双 lane。
2. `AppBuildEnvironment.showsHardwareDebugTools` 在 Build 644 恒为 `true`。Wi-Fi PC Debug、BLE Keep Alive、测试专注会话、Focus Debug 及相关后台行为会进入当前 Release 包。**仍阻断**：内部工具尚未迁到 `KIROLE_INTERNAL` 边界后面。
3. ~~必须证明 App Store 编译条件已传入 `KirolePackage`。~~ **已裁定 2026-08-15**：实测 Xcode 不会把自定义配置的编译条件传入 SwiftPM 包目标，按政策回退规则边界放在 app target（`Kirole/InternalBuildBoundary.swift`）；`scripts/verify-release-boundary.sh` 做成对符号门控（Internal 有标记 / App Store 无标记）。**仍需**：每个内部工具迁移后补成对存在/缺失测试。
4. App Store 安全配置必须失败关闭；BLE 安全输入缺失时不得生成可提交候选包，也不能靠隐藏诊断文案掩盖未签名传输。
5. 当前没有可上传截图。只能从同一 release tag 的 `AppStoreRelease` 归档、`AppStoreRelease` 模拟器构建和必要的真机页面重新取图。
6. 仓库内官网和隐私政策源文件已按正式版范围修正，但线上网址必须部署后重新读取验证；本地修改不等于线上生效。
7. App Privacy 问卷必须与定位、WeatherKit、AI 服务商、登录、后端快照和已启用的数据来源逐项一致。
8. `device-started focus`、场景应用、自定义头像传输等硬件声明必须有正式 App 构建和对应固件的真机证据。
9. App 显示 WeatherKit 数据时必须清楚展示 Apple Weather 标识和法律归属链接。当前 Settings 有静态 “Provided by Apple Weather” 与法律链接，但首页天气数据旁没有归属信息，因此不能把 Settings 里的入口当作已经满足要求。正式候选包应使用 `WeatherService.attribution` 返回的标识与法律 URL，并逐个验收实际显示天气的页面。

如果计划在中国大陆商店首发，还要单独核对内容许可要求。Silas 包含基督教与经文内容，不能只靠商店文案淡化后视为已经满足当地要求。

## 校验方式

检查当前历史/元数据包：

```bash
./docs/app-store/2026-08-14/validate-assets.sh package
```

检查真正可提交的候选包：

```bash
./docs/app-store/YYYY-MM-DD/validate-assets.sh submission
```

`submission` 模式必须失败，直到以下条件全部满足：双构建存在、记录状态为 `READY`、所有占位符已填写、官网正式版源文件无禁用来源/Beta 文案、截图数量与规格正确、校验和匹配。

## 文案边界

- 不宣传尚未完成真机验收的唤醒、固件、同步频率或续航细节。
- 正式可用来源只列 Google Calendar、Google Tasks、Apple Calendar、Apple Reminders。其他来源逐个完成部署和真实账号验收后再晋级；未通过的只能隐藏或显示 `Coming Soon`。
- 不声称所有数据永远只留在本地，也不声称 App 不使用定位。
- 自定义伙伴照片可以写“在 iPhone 上处理且不上传到我们的服务器”。
- 生成陪伴语、当天摘要、日程分类与简短支持文本时，相关日历、任务、专注、目标、工作偏好与伙伴设置可能发送给 AI 服务商。
- 桌面显示、设备发起专注、应用场景和自定义头像传输都要注明兼容硬件与受支持固件，并以真机证据决定是否进入商店文案。

## 设计方向

视觉采用 `Companion Quiet`：暖纸质感、深绿墨色、少量陶土橙，以及大留白。完整说明见 `design-philosophy.md`；写作口吻见 `voice-profile.md`。
