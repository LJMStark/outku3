# Family Controls 权限配置完成指南

## ✅ 已完成的配置

1. **Entitlements 文件** (`Config/Kirole.entitlements`)
   - ✅ 已添加 `com.apple.developer.family-controls` 权限声明

2. **Info.plist 文件** (`Config/Info.plist`)
   - ✅ 已添加 `NSFamilyControlsUsageDescription` 隐私说明

3. **Xcode Capability**
   - ✅ 已在 Xcode 中启用 Family Controls capability (Development 版本)

4. **构建验证**
   - ✅ 项目构建成功
   - ✅ Info.plist 隐私说明已嵌入到 App 中

## ⚠️ Development vs Distribution 版本

当前使用的是 **Family Controls (Development)** 版本,这对开发和测试是正常的。

**Development 版本**:
- ✅ 适用于开发和本地测试
- ✅ 可以在开发设备上运行
- ❌ 无法通过 TestFlight 分发
- ❌ 无法提交到 App Store

**如果需要发布到 App Store**,需要升级到 Distribution 版本(见下方说明)。

## 🧪 验证步骤

### 1. 验证配置文件

```bash
# 检查 entitlements
grep -A 1 "com.apple.developer.family-controls" Config/Kirole.entitlements

# 检查 Info.plist
grep -A 1 "NSFamilyControlsUsageDescription" Config/Info.plist
```

### 2. 清理并重新构建

```bash
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  clean build
```

### 3. 在模拟器上测试

```bash
# 构建并运行
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath ./build \
  build

# 安装到模拟器
xcrun simctl install booted ./build/Build/Products/Debug-iphonesimulator/Kirole.app

# 启动 App
xcrun simctl launch booted com.kirole.app
```

### 4. 测试权限请求流程

在 App 中:
1. 进入 **Settings** 页面
2. 找到 **Focus Protection** 区域
3. 点击 **Deep Focus** 模式
4. 点击 **Request Screen Time Access** 按钮
5. 应该弹出系统权限对话框(真机)或显示权限状态(模拟器)

### 5. 查看日志

```bash
# 实时查看 App 日志
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.kirole.app"' --level debug
```

预期看到:
- `FocusGuardService` 请求授权
- `AuthorizationCenter` 状态变化
- 无权限相关错误

## ⚠️ 重要注意事项

1. **Apple Developer Account**
   - Family Controls 需要付费的 Apple Developer Program 账号($99/年)
   - 个人免费账号无法使用此功能

2. **真机测试**
   - 模拟器可能无法完整测试权限流程
   - 建议在真机上验证完整功能

3. **iOS 版本要求**
   - Family Controls 仅支持 iOS 15.0+
   - 当前项目最低支持 iOS 17.0,满足要求

4. **App Store 审核**
   - 隐私说明必须清晰合理
   - 当前的说明符合 Apple 的要求

## 📝 配置内容

### Entitlements (Config/Kirole.entitlements)

```xml
<key>com.apple.developer.family-controls</key>
<true/>
```

### Info.plist (Config/Info.plist)

```xml
<key>NSFamilyControlsUsageDescription</key>
<string>Kirole 需要访问屏幕使用时间权限,以便在专注模式下帮助你屏蔽分心应用,让你和你的宠物伙伴一起保持专注。</string>
```

## 🎯 下一步

### 开发阶段(当前)

1. ✅ 配置已完成,可以开始测试
2. 在模拟器或开发设备上测试 Deep Focus 功能
3. 验证权限请求流程是否正常

### 发布前准备

当准备发布到 App Store 或 TestFlight 时:

1. **注册 Apple Developer Program** ($99/年)
2. **在 Apple Developer Portal 启用 Family Controls**
   - 登录 https://developer.apple.com/account/
   - 进入 **Certificates, Identifiers & Profiles**
   - 选择 **Identifiers** → 找到 `com.kirole.app`
   - 勾选 **Family Controls** capability
   - 点击 **Save**
3. **在 Xcode 中刷新 Provisioning Profile**
   - 在 **Signing & Capabilities** 页面
   - 点击 **Download Manual Profiles** 或等待自动刷新
   - Development 警告应该消失

## 🔗 相关文件

- 代码实现: `KirolePackage/Sources/KiroleFeature/Core/FocusGuardService.swift`
- UI 集成: `KirolePackage/Sources/KiroleFeature/Views/Settings/SettingsFocusSection.swift`
- 测试覆盖: `KirolePackage/Tests/KiroleFeatureTests/FocusProtectionTests.swift`
- Feature Flag: `DEEP_FOCUS_FEATURE_ENABLED` (在 `AppState.swift` 中)
