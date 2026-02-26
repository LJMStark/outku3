# TestFlight 发布快速指南

## 前提条件

✅ 付费 Apple Developer Program 账号(xiaoyouzi2010@gmail.com)
✅ 账号状态: Active
✅ 项目构建成功

## 步骤 1: 创建 Distribution 证书

### 在 Xcode 中创建(推荐)

1. 打开 Xcode
2. 菜单栏: **Xcode** → **Settings...** (⌘,)
3. 切换到 **Accounts** 标签
4. 选择你的 Apple ID: `xiaoyouzi2010@gmail.com`
5. 点击右下角 **Manage Certificates...**
6. 点击左下角 **+** 按钮
7. 选择 **Apple Distribution**
8. 证书会自动创建并安装到钥匙串

### 验证证书

```bash
# 检查 Distribution 证书
security find-identity -v -p codesigning | grep "Apple Distribution"
```

预期输出:
```
1) ABC123... "Apple Distribution: Your Name (TEAM_ID)"
```

## 步骤 2: 在 Developer Portal 启用 Family Controls

### 2.1 登录 Developer Portal

1. 访问 https://developer.apple.com/account/
2. 使用 `xiaoyouzi2010@gmail.com` 登录
3. 确认账号状态为 **Active**

### 2.2 配置 App ID

1. 点击左侧 **Certificates, Identifiers & Profiles**
2. 选择 **Identifiers**
3. 找到 `com.kirole.app`
   - 如果不存在,点击 **+** 创建:
     - Description: `Kirole`
     - Bundle ID: `com.kirole.app` (Explicit)
     - Platform: iOS

### 2.3 启用 Family Controls

1. 点击 `com.kirole.app` 进入详情
2. 在 **Capabilities** 列表中找到 **Family Controls**
3. **勾选** Family Controls 复选框
4. 点击右上角 **Save**
5. 确认保存成功

**重要**: 无需填写任何表格,勾选后立即生效!

## 步骤 3: 在 Xcode 中刷新 Provisioning Profile

### 3.1 自动刷新(推荐)

1. 打开 `Kirole.xcworkspace`
2. 选择 **Kirole** project
3. 选择 **Kirole** target
4. 切换到 **Signing & Capabilities** 标签
5. 确认 **Automatically manage signing** 已勾选
6. 等待 Xcode 自动下载新的 Provisioning Profile(1-2 分钟)
7. **Family Controls (Development)** 警告应该消失

### 3.2 手动刷新(如果自动失败)

1. Xcode 菜单: **Xcode** → **Settings...**
2. **Accounts** 标签
3. 选择你的 Apple ID
4. 点击 **Download Manual Profiles**
5. 等待下载完成
6. 返回项目的 **Signing & Capabilities**
7. 警告应该消失

## 步骤 4: 在 App Store Connect 创建 App

### 4.1 登录 App Store Connect

1. 访问 https://appstoreconnect.apple.com/
2. 使用 `xiaoyouzi2010@gmail.com` 登录

### 4.2 创建新 App

1. 点击 **My Apps**
2. 点击左上角 **+** → **New App**
3. 填写信息:
   - **Platforms**: iOS
   - **Name**: Kirole
   - **Primary Language**: Chinese (Simplified) 或 English
   - **Bundle ID**: 选择 `com.kirole.app`
   - **SKU**: `kirole-ios` (唯一标识符,自定义)
   - **User Access**: Full Access
4. 点击 **Create**

### 4.3 填写 App 基本信息

1. **App Information**:
   - Category: Productivity
   - Content Rights: 根据实际情况选择

2. **Pricing and Availability**:
   - Price: Free (或设置价格)
   - Availability: 选择发布地区

3. **App Privacy**:
   - 点击 **Get Started**
   - 添加隐私政策 URL(如果有)
   - 声明数据收集情况

## 步骤 5: Archive 并上传到 App Store Connect

### 5.1 准备 Archive

1. 在 Xcode 中打开 `Kirole.xcworkspace`
2. 选择目标设备: **Any iOS Device (arm64)**
3. 确认 Scheme 为 **Kirole**
4. 确认 Build Configuration 为 **Release**

### 5.2 创建 Archive

```bash
# 方法 A: 通过 Xcode UI(推荐)
# 1. 菜单栏: Product → Archive
# 2. 等待构建完成(5-10 分钟)
# 3. Organizer 窗口会自动打开

# 方法 B: 通过命令行
xcodebuild -workspace Kirole.xcworkspace \
  -scheme Kirole \
  -configuration Release \
  -archivePath ~/Desktop/Kirole.xcarchive \
  archive
```

### 5.3 上传到 App Store Connect

在 Organizer 窗口:

1. 选择刚创建的 Archive
2. 点击 **Distribute App**
3. 选择 **App Store Connect**
4. 点击 **Next**
5. 选择 **Upload**
6. 点击 **Next**
7. 选择 Distribution 证书和 Provisioning Profile
8. 点击 **Next**
9. 审查信息,点击 **Upload**
10. 等待上传完成(5-15 分钟)

### 5.4 验证上传

1. 返回 App Store Connect
2. 进入 **Kirole** App
3. 切换到 **TestFlight** 标签
4. 等待构建处理完成(10-30 分钟)
5. 状态变为 **Ready to Submit** 或 **Ready to Test**

## 步骤 6: 配置 TestFlight

### 6.1 内部测试(立即可用)

1. 在 TestFlight 标签下
2. 点击构建版本号
3. 在 **Internal Testing** 区域
4. 点击 **+** 添加内部测试员
5. 输入测试员的 Apple ID 邮箱
6. 点击 **Add**
7. 测试员会立即收到邀请邮件

**内部测试特点**:
- ✅ 无需审核,立即可用
- ✅ 最多 100 名测试员
- ✅ 测试员必须是你的 App Store Connect 团队成员

### 6.2 外部测试(需要审核)

1. 在 TestFlight 标签下
2. 点击 **External Testing** 区域
3. 点击 **+** 创建新的测试组
4. 填写组名称(如 "Beta Testers")
5. 添加构建版本
6. 添加测试员邮箱(最多 10,000 人)
7. 填写 **Test Information**:
   - What to Test: 描述测试重点
   - Feedback Email: 接收反馈的邮箱
   - Marketing URL: 可选
   - Privacy Policy URL: 可选
8. 点击 **Submit for Review**
9. 等待审核(1-2 天)

**外部测试特点**:
- ⚠️ 需要 Apple 审核(1-2 天)
- ✅ 最多 10,000 名测试员
- ✅ 测试员无需是团队成员
- ✅ 通过公开链接邀请

## 步骤 7: 测试员安装 TestFlight

### 测试员操作

1. 在 iPhone 上安装 **TestFlight** App(App Store 免费下载)
2. 打开邀请邮件
3. 点击 **View in TestFlight** 或 **Start Testing**
4. TestFlight App 会自动打开
5. 点击 **Accept** 接受邀请
6. 点击 **Install** 安装 Kirole
7. 安装完成后,点击 **Open** 启动 App

### 测试员反馈

测试员可以通过 TestFlight App 提交:
- 截图
- 崩溃报告
- 文字反馈

你会在 App Store Connect 的 TestFlight 标签下看到所有反馈。

## 常见问题

### Q1: Archive 失败,提示签名错误?

**A**: 检查:
1. 是否选择了 **Any iOS Device (arm64)**
2. 是否有有效的 Distribution 证书
3. 是否启用了 **Automatically manage signing**
4. 清理构建缓存: `xcodebuild clean`

### Q2: 上传后一直显示 "Processing"?

**A**: 正常现象,Apple 需要处理构建:
- 通常 10-30 分钟
- 最长可能 1-2 小时
- 可以先去做其他事情

### Q3: 构建被拒绝,提示 "Invalid Binary"?

**A**: 常见原因:
1. **缺少隐私说明** → 检查 `Info.plist` 的 `NSFamilyControlsUsageDescription`
2. **Bitcode 问题** → 在 Build Settings 中禁用 Bitcode
3. **架构问题** → 确认只包含 arm64 架构

### Q4: 测试员无法安装,提示 "Unable to Install"?

**A**: 检查:
1. 测试员的设备 iOS 版本 >= 17.0
2. 测试员的 Apple ID 是否正确
3. 测试员是否已接受邀请
4. 设备存储空间是否充足

### Q5: Family Controls 在 TestFlight 上不工作?

**A**: 确认:
1. 已在 Developer Portal 启用 Family Controls
2. 使用的是 Distribution 版本(不是 Development)
3. Provisioning Profile 包含 Family Controls
4. 测试设备 iOS 版本 >= 15.0

## 时间线估算

| 步骤 | 预计时间 |
|------|---------|
| 创建 Distribution 证书 | 5 分钟 |
| 在 Developer Portal 启用 Family Controls | 5 分钟 |
| Xcode 刷新 Provisioning Profile | 1-2 分钟 |
| Archive 构建 | 5-10 分钟 |
| 上传到 App Store Connect | 5-15 分钟 |
| Apple 处理构建 | 10-30 分钟 |
| 配置 TestFlight | 5 分钟 |
| 内部测试员安装 | 立即 |
| 外部测试审核 | 1-2 天 |

**总计**: 从开始到内部测试员可以安装,预计 **30-60 分钟**

## 检查清单

### 准备阶段
- [x] 付费 Apple Developer Program 账号
- [ ] Distribution 证书已创建
- [ ] Developer Portal 启用 Family Controls
- [ ] Xcode 刷新 Provisioning Profile
- [ ] Family Controls 警告消失

### 构建阶段
- [ ] 选择 "Any iOS Device (arm64)"
- [ ] Build Configuration 为 Release
- [ ] Archive 构建成功
- [ ] 无签名错误

### 上传阶段
- [ ] App Store Connect 创建 App
- [ ] 上传成功
- [ ] 构建处理完成
- [ ] 状态为 "Ready to Test"

### TestFlight 阶段
- [ ] 添加内部测试员
- [ ] 测试员收到邀请
- [ ] 测试员成功安装
- [ ] App 正常运行
- [ ] Family Controls 功能正常

### 外部测试(可选)
- [ ] 创建外部测试组
- [ ] 填写 Test Information
- [ ] 提交审核
- [ ] 审核通过
- [ ] 外部测试员可以安装

## 下一步

完成 TestFlight 内部测试后:
1. 收集测试反馈
2. 修复发现的问题
3. 上传新的构建版本
4. 准备 App Store 提交
5. 填写 App Store 元数据
6. 提交正式审核

## 相关资源

- App Store Connect: https://appstoreconnect.apple.com/
- TestFlight 文档: https://developer.apple.com/testflight/
- App Store 审核指南: https://developer.apple.com/app-store/review/guidelines/
- TestFlight 最佳实践: https://developer.apple.com/testflight/testers/

## 需要帮助?

如果遇到问题:
1. 查看 Xcode Organizer 的错误信息
2. 检查 App Store Connect 的构建状态
3. 查看 Apple Developer 论坛
4. 联系 Apple Developer Support
