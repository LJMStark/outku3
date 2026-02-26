# Deep Focus 功能测试指南

## 前置条件

✅ Family Controls 权限配置已完成
✅ 项目构建成功
✅ `DEEP_FOCUS_FEATURE_ENABLED` 已启用

## 测试环境

### 模拟器测试(快速验证)

```bash
# 构建并运行
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

# 安装到模拟器
xcrun simctl install booted \
  ~/Library/Developer/Xcode/DerivedData/Kirole-*/Build/Products/Debug-iphonesimulator/Kirole.app

# 启动 App
xcrun simctl launch booted com.kirole.app
```

**注意**: 模拟器可能无法完整测试 Screen Time 权限,但可以验证 UI 和基本流程。

### 真机测试(完整验证)

1. 连接 iPhone 到 Mac
2. 在 Xcode 中选择你的设备
3. 点击 Run (⌘R)

## 测试步骤

### 1. 检查 Feature Flag

在 `AppState.swift` 中确认:

```swift
static let DEEP_FOCUS_FEATURE_ENABLED = true
```

### 2. 进入 Settings 页面

1. 启动 Kirole App
2. 点击底部导航栏的 **Settings** 标签
3. 滚动到 **Focus Protection** 区域

### 3. 测试权限请求流程

#### 场景 A: 首次请求权限

1. 点击 **Deep Focus** 模式
2. 应该看到 **Request Screen Time Access** 按钮
3. 点击按钮
4. **真机**: 应该弹出系统权限对话框
5. **模拟器**: 可能显示权限状态或无响应(正常)

#### 场景 B: 权限已授予

1. 点击 **Deep Focus** 模式
2. 应该看到 **Select Apps to Block** 按钮
3. 点击按钮
4. 应该打开应用选择界面(FamilyActivityPicker)
5. 选择要屏蔽的应用
6. 点击 **Done**
7. 返回 Settings 页面,应该显示已选择的应用数量

#### 场景 C: 权限被拒绝

1. 点击 **Deep Focus** 模式
2. 应该看到错误提示
3. 提示用户前往系统设置授权

### 4. 测试专注模式激活

1. 在 Home 页面创建一个任务
2. 点击任务进入详情页
3. 点击 **Start Focus** 按钮
4. 如果 Deep Focus 已配置,应该:
   - 启动专注计时器
   - 屏蔽选中的应用(真机)
   - 显示专注状态

### 5. 测试专注模式结束

1. 点击 **Stop Focus** 按钮
2. 应该:
   - 停止计时器
   - 解除应用屏蔽
   - 记录专注时长

## 验证日志

### 查看实时日志

```bash
# 模拟器
xcrun simctl spawn booted log stream \
  --predicate 'subsystem == "com.kirole.app"' \
  --level debug

# 真机
idevicesyslog | grep -i "kirole\|focus\|family"
```

### 预期日志输出

```
[FocusGuardService] Requesting Screen Time authorization...
[FocusGuardService] Authorization status: authorized
[FocusGuardService] Blocking 5 applications
[FocusGuardService] Focus session started
[FocusGuardService] Focus session ended, duration: 25 minutes
```

## 常见问题

### Q1: 模拟器上无法测试权限?

**A**: 正常现象。Screen Time API 在模拟器上功能有限,建议在真机上测试完整流程。

### Q2: 真机上权限请求无响应?

**A**: 检查:
1. 是否使用付费的 Apple Developer Program 账号
2. 是否在 Developer Portal 中启用了 Family Controls
3. 设备 iOS 版本是否 >= 15.0

### Q3: 构建失败,提示 entitlements 错误?

**A**: 确认:
1. `Config/Kirole.entitlements` 包含 `com.apple.developer.family-controls`
2. Xcode 中已添加 Family Controls capability
3. 清理构建缓存: `xcodebuild clean`

### Q4: App 运行时崩溃?

**A**: 检查:
1. `Config/Info.plist` 包含 `NSFamilyControlsUsageDescription`
2. 查看崩溃日志: `xcrun simctl spawn booted log show --last 5m`

## 测试检查清单

- [ ] Feature flag 已启用
- [ ] Settings 页面显示 Deep Focus 选项
- [ ] 权限请求按钮可点击
- [ ] 真机上弹出系统权限对话框
- [ ] 授权后可以选择应用
- [ ] 专注模式可以正常启动
- [ ] 应用屏蔽生效(真机)
- [ ] 专注模式可以正常结束
- [ ] 专注时长正确记录
- [ ] 无崩溃或错误日志

## 性能测试

### 内存使用

```bash
# 监控内存使用
instruments -t "Allocations" -D trace.trace \
  -w "iPhone 17 Pro" \
  com.kirole.app
```

### 电池消耗

在真机上:
1. 启动 Deep Focus 模式
2. 保持专注 30 分钟
3. 检查 Settings → Battery 中的电量消耗

预期: Deep Focus 模式不应显著增加电池消耗(<5%)

## 下一步

测试通过后:
1. 提交代码到 Git
2. 创建 PR 并请求 Code Review
3. 准备 TestFlight 构建(需要 Distribution 版本)
4. 提交到 App Store 审核

## 相关文件

- 配置说明: `FAMILY_CONTROLS_SETUP.md`
- 代码实现: `KirolePackage/Sources/KiroleFeature/Core/FocusGuardService.swift`
- UI 集成: `KirolePackage/Sources/KiroleFeature/Views/Settings/SettingsFocusSection.swift`
- 单元测试: `KirolePackage/Tests/KiroleFeatureTests/FocusProtectionTests.swift`
