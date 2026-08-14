# Kirole App Store 上架素材包

生成日期：2026-08-14
对应检查点：Kirole 2.0，Build 644，Git `fd56bf7`

## 建议直接使用

当前 App 界面以英文为主，首发建议使用：

- 英文截图：`screenshots-en/`
- 英文元数据：`metadata-en.md`
- 排序预览：`contact-sheet-screenshots-en.png`

中文素材放在 `screenshots-zh-Hans/` 和 `metadata-zh-Hans.md`，作为后续本地化审阅稿。它保留了真实的英文 App 界面，没有伪造中文版界面。

## 截图顺序

1. `01-cover.png` — Your day, with someone watching over it.
2. `02-timeline.png` — A calmer way to see your day.
3. `03-focus.png` — Protect your focus, quietly.
4. `04-companion.png` — Your companion stays with the work.
5. `05-scenes.png` — Focus unlocks new places.
6. `06-characters.png` — Choose who keeps you company.

App Store Connect 没有单独的“封面图”字段。没有上传 App Preview 视频时，第一张截图就是列表与产品页最先看到的封面，因此 `01-cover.png` 已按封面处理。

## 文件规格

- 每张：1320 × 2868 px
- 格式：PNG
- 色彩：RGB
- Alpha：无
- 数量：每套 6 张，低于每个本地化版本 10 张的上限
- 素材：当前 Build 644 的真实模拟器画面、当前角色资源与场景资源
- 示例数据：全部为虚构日程与任务，不含真实用户信息

## 上传前必须处理

`AppBuildEnvironment.showsHardwareDebugTools` 在 Build 644 仍然恒为 `true`。这会让 Release / App Store 包显示 Wi-Fi 调试、BLE Keep Alive 与 Focus Debug 等入口。正式归档前应恢复 Release 门控，并重新归档验证。

本素材包没有直接使用含调试入口的完整截图；专注图只保留正式功能区域，时间线图也裁掉了模拟器调试按钮。

当前营销网址仍写着 “private beta”。正式上线前要把首页的 beta 标识和 beta 招募文案改成正式版状态，再将它填入 App Store Connect。支持网址与隐私政策网址已确认可以正常访问。

线上隐私政策目前对两类数据流的说明与 Build 644 不一致：一是 AI 处理范围不只日历与任务，还包含部分专注、目标、工作类型和伙伴设置，并用于日程分类与简短支持文本；二是页面写着“不使用定位”及“数据只在两种情况下离开 App”，但 App 会请求使用期间定位并通过 WeatherKit 获取当地天气。提交 App Privacy 与商店描述前，需要同步修正线上隐私政策与 App Privacy 问卷；本素材包里的元数据已经按当前代码扩大 AI 披露范围。

如果计划在中国大陆商店首发，还要单独核对内容许可要求。当前产品的 Silas 包含基督教与经文内容，不能只靠商店文案淡化后直接视为已满足当地上架要求。

## 文案边界

- 不宣传尚未完成真机验收的唤醒、固件或续航细节。
- 不列出当前默认关闭的第三方来源。
- 不声称所有数据都永远只留在本地，也不声称 App 不使用定位。
- 自定义伙伴照片可以写“在 iPhone 上处理且不上传到我们的服务器”；生成陪伴语、当天摘要、日程分类与简短支持文本时，相关日程、任务、专注、目标、工作类型与伙伴设置可能发送给 AI 服务商。
- 桌面显示、设备发起专注、应用场景和自定义头像传输均明确要求兼容硬件与相应固件。

## 设计方向

视觉采用 `Companion Quiet`：暖纸质感、深绿墨色、少量陶土橙，以及大留白。完整说明见 `design-philosophy.md`；写作口吻见 `voice-profile.md`。
