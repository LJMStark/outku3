# Family Controls Distribution 版本升级指南

## 前提条件

- ✅ 已有付费的 Apple Developer Program 账号($99/年)
- ✅ 账号状态为 Active
- ✅ 已在 Xcode 中登录开发者账号

## 升级步骤

### 1. 在 Apple Developer Portal 启用 Family Controls

#### 步骤 A: 登录 Developer Portal

1. 访问 https://developer.apple.com/account/
2. 使用你的 Apple ID 登录
3. 确认账号状态为 **Active**

#### 步骤 B: 配置 App ID

1. 点击左侧菜单 **Certificates, Identifiers & Profiles**
2. 选择 **Identifiers**
3. 在列表中找到 `com.kirole.app`
   - 如果不存在,点击 **+** 创建新的 App ID
   - App ID Description: `Kirole`
   - Bundle ID: `com.kirole.app` (Explicit)

#### 步骤 C: 启用 Family Controls Capability

1. 点击 `com.kirole.app` 进入详情页
2. 在 **Capabilities** 列表中找到 **Family Controls**
3. **勾选** Family Controls 复选框
4. 点击右上角 **Save** 按钮
5. 确认保存成功

**重要**: 无需填写任何表格或提交审批,勾选后立即生效!

### 2. 在 Xcode 中刷新 Provisioning Profile

#### 方法 A: 自动刷新(推荐)

1. 打开 `Kirole.xcworkspace`
2. 选择 **Kirole** target
3. 切换到 **Signing & Capabilities** 标签
4. 确认 **Automatically manage signing** 已勾选
5. 等待 Xcode 自动下载新的 Provisioning Profile(通常 1-2 分钟)
6. **Family Controls (Development)** 警告应该消失

#### 方法 B: 手动刷新

如果自动刷新失败:

1. 在 Xcode 菜单栏选择 **Xcode** → **Settings...**
2. 切换到 **Accounts** 标签
3. 选择你的 Apple ID
4. 点击右下角 **Download Manual Profiles** 按钮
5. 等待下载完成
6. 返回项目的 **Signing & Capabilities** 页面
7. 警告应该消失

### 3. 验证配置

#### 检查 Provisioning Profile

```bash
# 查看当前使用的 Provisioning Profile
security find-identity -v -p codesigning

# 检查 Profile 是否包含 Family Controls
grep -r "com.apple.developer.family-controls" \
  ~/Library/MobileDevice/Provisioning\ Profiles/
```

#### 构建测试

```bash
# 清理构建缓存
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole clean

# 重新构建(Release 配置)
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

预期结果:
- ✅ 构建成功
- ✅ 无 Family Controls 相关警告
- ✅ 可以正常运行

## App Store 提交准备

### 1. 隐私说明审查

Apple 会审查你的 `NSFamilyControlsUsageDescription`,确保:

✅ **当前的说明**(已通过):
```
Kirole 需要访问屏幕使用时间权限,以便在专注模式下帮助你屏蔽分心应用,让你和你的宠物伙伴一起保持专注。
```

**审查要点**:
- ✅ 清晰说明用途(专注模式、屏蔽应用)
- ✅ 用户友好的语言
- ✅ 不涉及数据收集
- ✅ 符合 App 的核心功能

### 2. App Review 信息准备

在 App Store Connect 提交时,建议在 **App Review Information** 中补充说明:

```
Family Controls Usage:

Kirole uses the Family Controls framework to help users stay focused
during work sessions by temporarily blocking distracting apps.

Key points:
- Users explicitly enable "Deep Focus" mode in Settings
- Users manually select which apps to block
- Blocking is only active during focus sessions
- No user data is collected or transmitted
- All settings are stored locally on device

Test Account:
- Email: [测试账号邮箱]
- Password: [测试密码]

Test Instructions:
1. Go to Settings tab
2. Enable "Deep Focus" mode
3. Grant Screen Time permission when prompted
4. Select apps to block
5. Start a focus session from Home tab
6. Verify selected apps are blocked during session
```

### 3. 测试账号准备

为 App Review 团队准备:
- 测试账号(如果需要登录)
- 测试设备配置说明
- 功能演示视频(可选,但推荐)

### 4. 隐私清单(Privacy Manifest)

确认 `PrivacyInfo.xcprivacy` 文件(如果有)包含 Family Controls 相关说明:

```xml
<key>NSPrivacyAccessedAPITypes</key>
<array>
    <dict>
        <key>NSPrivacyAccessedAPIType</key>
        <string>NSPrivacyAccessedAPICategoryScreenTime</string>
        <key>NSPrivacyAccessedAPITypeReasons</key>
        <array>
            <string>Focus session app blocking</string>
        </array>
    </dict>
</array>
```

**注意**: 截至 2026 年,Apple 可能要求所有使用敏感 API 的 App 提供 Privacy Manifest。

## 常见问题

### Q1: 需要向 Apple 提交特殊申请吗?

**A**: **不需要**。Family Controls 不需要任何特殊审批流程,只要:
- 有付费开发者账号
- 在 Developer Portal 勾选 Family Controls
- 提供合理的隐私说明

### Q2: 审核会被拒绝吗?

**A**: 只要满足以下条件,通过率很高:
- ✅ 隐私说明清晰合理
- ✅ 功能与说明一致
- ✅ 不收集或传输用户数据
- ✅ 用户可以控制权限和设置

### Q3: 需要多久才能生效?

**A**:
- Developer Portal 勾选后: **立即生效**
- Provisioning Profile 刷新: **1-5 分钟**
- App Store 审核: **1-3 天**(首次提交)

### Q4: 如果审核被拒怎么办?

**A**: Apple 会提供具体的拒绝原因,常见问题:
1. **隐私说明不清晰** → 修改 `NSFamilyControlsUsageDescription`
2. **功能与说明不符** → 确保 App 行为与说明一致
3. **疑似数据收集** → 在 App Review 信息中明确说明不收集数据

### Q5: 可以在 TestFlight 测试吗?

**A**: 可以!升级到 Distribution 版本后:
1. 在 App Store Connect 创建 App
2. 上传构建版本
3. 添加内部或外部测试员
4. 通过 TestFlight 分发测试

## 时间线估算

| 步骤 | 预计时间 |
|------|---------|
| 注册 Apple Developer Program | 24-48 小时 |
| 在 Developer Portal 启用 Family Controls | 5 分钟 |
| Xcode 刷新 Provisioning Profile | 1-5 分钟 |
| 构建并上传到 App Store Connect | 30-60 分钟 |
| TestFlight 审核(内部测试) | 即时 |
| TestFlight 审核(外部测试) | 1-2 天 |
| App Store 审核(首次提交) | 1-3 天 |
| App Store 审核(更新版本) | 1-2 天 |

**总计**: 从注册到 App Store 上线,预计 **3-7 天**

## 检查清单

### 升级前
- [ ] 已有付费 Apple Developer Program 账号
- [ ] 账号状态为 Active
- [ ] 已在 Xcode 中登录开发者账号
- [ ] 当前 Development 版本构建成功

### 升级中
- [ ] 在 Developer Portal 勾选 Family Controls
- [ ] Xcode 刷新 Provisioning Profile
- [ ] Family Controls 警告消失
- [ ] Release 配置构建成功

### 提交前
- [ ] 隐私说明清晰合理
- [ ] 准备 App Review 信息
- [ ] 准备测试账号(如需要)
- [ ] 录制功能演示视频(可选)
- [ ] 检查 Privacy Manifest(如需要)

### 提交后
- [ ] 上传到 App Store Connect
- [ ] 填写 App 元数据
- [ ] 提交审核
- [ ] 响应审核反馈(如有)

## 相关资源

- Apple Developer Portal: https://developer.apple.com/account/
- App Store Connect: https://appstoreconnect.apple.com/
- Family Controls 文档: https://developer.apple.com/documentation/familycontrols
- App Review 指南: https://developer.apple.com/app-store/review/guidelines/
- 隐私最佳实践: https://developer.apple.com/privacy/

## 下一步

1. 确认已有付费开发者账号
2. 按照本指南升级到 Distribution 版本
3. 在 TestFlight 进行内部测试
4. 准备 App Store 提交材料
5. 提交审核并等待结果
