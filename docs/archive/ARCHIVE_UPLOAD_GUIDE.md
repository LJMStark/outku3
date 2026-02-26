# Archive 并上传到 TestFlight - 快速指南

## 前提条件确认

✅ Distribution 证书已创建
✅ Developer Portal 已启用 Family Controls
✅ App Store Connect 已创建 Kirole App
✅ 当前在 App Store Connect 的版本配置页面

## 步骤 1: 在 Xcode 中准备 Archive

### 1.1 打开项目

1. 打开 Xcode
2. 打开 `Kirole.xcworkspace`(不是 .xcodeproj)
3. 等待项目加载完成

### 1.2 选择目标设备

在 Xcode 顶部工具栏:
1. 点击设备选择器(当前可能显示 "iPhone 17 Pro" 或其他模拟器)
2. 选择 **Any iOS Device (arm64)**
   - 如果没有看到这个选项,选择 **Generic iOS Device**

**重要**: 必须选择 "Any iOS Device",不能选择模拟器或具体设备!

### 1.3 确认 Scheme 和 Configuration

1. 点击菜单栏 **Product** → **Scheme** → **Edit Scheme...**
2. 在左侧选择 **Archive**
3. 确认 **Build Configuration** 为 **Release**
4. 点击 **Close**

### 1.4 刷新 Provisioning Profile

1. 选择 **Kirole** project(左侧导航栏)
2. 选择 **Kirole** target
3. 切换到 **Signing & Capabilities** 标签
4. 确认 **Automatically manage signing** 已勾选
5. 确认 **Team** 为你的开发者账号
6. 等待 Xcode 自动刷新(看到 "Provisioning profile ... created" 提示)

**检查点**: Family Controls 的 Development 警告应该已经消失

## 步骤 2: 创建 Archive

### 2.1 开始 Archive

1. 确认已选择 **Any iOS Device (arm64)**
2. 点击菜单栏 **Product** → **Archive**
3. 等待构建完成(5-10 分钟)

**构建过程中会看到**:
- "Building Kirole..."
- "Archiving Kirole..."
- 进度条显示编译进度

### 2.2 Archive 成功

构建完成后,**Organizer** 窗口会自动打开,显示:
- 左侧: Archives 列表
- 右侧: 刚创建的 Archive 详情
  - App 图标
  - 版本号: 1.0
  - Build 号: 1
  - 日期和时间

**如果 Organizer 没有自动打开**:
- 菜单栏: **Window** → **Organizer**
- 切换到 **Archives** 标签

### 2.3 Archive 失败排查

如果构建失败,常见错误:

#### 错误 1: 签名错误
```
Code signing error: No signing certificate "iOS Distribution" found
```

**解决方法**:
1. 确认已创建 Distribution 证书
2. 运行: `security find-identity -v -p codesigning | grep Distribution`
3. 如果没有输出,重新创建证书

#### 错误 2: Provisioning Profile 错误
```
Provisioning profile doesn't include the com.apple.developer.family-controls entitlement
```

**解决方法**:
1. 前往 Developer Portal
2. 确认 com.kirole.app 已勾选 Family Controls
3. 在 Xcode 中: Xcode → Settings → Accounts → Download Manual Profiles
4. 重新 Archive

#### 错误 3: 构建错误
```
Build failed with errors
```

**解决方法**:
1. 查看错误详情(点击错误信息)
2. 通常是代码编译错误
3. 修复后重新 Archive

## 步骤 3: 上传到 App Store Connect

### 3.1 开始上传

在 Organizer 窗口:

1. 选择刚创建的 Archive(应该已经自动选中)
2. 点击右侧 **Distribute App** 按钮
3. 选择 **App Store Connect**
4. 点击 **Next**

### 3.2 选择分发方式

1. 选择 **Upload**
2. 点击 **Next**

### 3.3 配置选项

**App Store Connect distribution options**:

- ✅ **Upload your app's symbols** (推荐勾选,用于崩溃分析)
- ✅ **Manage Version and Build Number** (推荐勾选,自动管理版本号)
- ⬜ **Strip Swift symbols** (可选,减小包体积)

点击 **Next**

### 3.4 自动签名

Xcode 会自动选择:
- **Distribution certificate**: 你刚创建的 Apple Distribution 证书
- **Provisioning profile**: 包含 Family Controls 的 Distribution Profile

**检查点**: 确认显示的 Profile 包含 "Family Controls"

点击 **Next**

### 3.5 审查并上传

最后一步会显示:
- App 名称: Kirole
- Bundle ID: com.kirole.app
- 版本: 1.0
- Build: 1
- 文件大小

确认无误后:
1. 点击 **Upload**
2. 等待上传完成(5-15 分钟,取决于网络速度)

**上传过程中会看到**:
- "Uploading..."
- 进度条
- "Upload Successful" ✅

### 3.6 上传成功

看到 "Upload Successful" 后:
1. 点击 **Done**
2. 关闭 Organizer 窗口

## 步骤 4: 等待 Apple 处理构建

### 4.1 返回 App Store Connect

1. 回到浏览器中的 App Store Connect
2. 点击顶部 **TestFlight** 标签
3. 你会看到 "Processing" 状态

### 4.2 处理时间

Apple 需要处理上传的构建:
- **通常**: 10-30 分钟
- **最长**: 1-2 小时

**处理过程中**:
- 状态: "Processing"
- 无法添加测试员
- 可以先去做其他事情

### 4.3 处理完成

当处理完成后:
- 状态变为: "Ready to Submit" 或 "Ready to Test"
- 构建版本号会显示在列表中: **1.0 (1)**
- 可以开始添加测试员

**你会收到邮件通知**: "Your build has been processed"

## 步骤 5: 添加 TestFlight 内部测试员

### 5.1 进入 TestFlight

在 App Store Connect:
1. 确认在 **TestFlight** 标签
2. 看到构建版本 **1.0 (1)** 状态为 "Ready to Test"

### 5.2 添加内部测试员

1. 在左侧找到 **Internal Testing** 区域
2. 点击 **App Store Connect Users** 组(默认组)
3. 点击右侧 **+** 按钮
4. 选择要添加的测试员(或点击 **Add New Internal Tester**)
5. 输入测试员的 Apple ID 邮箱
6. 点击 **Add**

### 5.3 测试员收到邀请

测试员会立即收到邮件:
- 标题: "You're invited to test Kirole"
- 内容: 包含 TestFlight 安装链接

## 步骤 6: 测试员安装 App

### 测试员操作步骤

1. **安装 TestFlight App**
   - 在 iPhone 上打开 App Store
   - 搜索 "TestFlight"
   - 下载并安装(免费)

2. **接受邀请**
   - 打开邀请邮件
   - 点击 "View in TestFlight" 或 "Start Testing"
   - TestFlight App 会自动打开

3. **安装 Kirole**
   - 在 TestFlight 中点击 "Accept"
   - 点击 "Install"
   - 等待下载完成
   - 点击 "Open" 启动 App

4. **测试 Family Controls**
   - 进入 Settings 页面
   - 启用 Deep Focus 模式
   - 授予 Screen Time 权限
   - 选择要屏蔽的应用
   - 测试专注模式功能

## 常见问题

### Q1: Archive 时提示 "No signing certificate found"?

**A**: Distribution 证书未正确安装
```bash
# 检查证书
security find-identity -v -p codesigning | grep Distribution

# 如果没有输出,重新创建:
# Xcode → Settings → Accounts → Manage Certificates → + → Apple Distribution
```

### Q2: 上传后一直显示 "Processing"?

**A**: 正常现象,耐心等待
- 通常 10-30 分钟
- 可以关闭浏览器,稍后再查看
- 处理完成后会收到邮件通知

### Q3: 构建处理失败,收到拒绝邮件?

**A**: 查看邮件中的具体原因,常见问题:
1. **缺少隐私说明** → 检查 Info.plist
2. **Invalid Binary** → 检查架构设置
3. **Missing required icon** → 检查 App Icon

### Q4: TestFlight 中 Family Controls 不工作?

**A**: 确认:
1. Developer Portal 已启用 Family Controls
2. Provisioning Profile 包含 Family Controls
3. 测试设备 iOS >= 15.0
4. 已授予 Screen Time 权限

### Q5: 测试员无法安装,提示 "Unable to Install"?

**A**: 检查:
1. 测试员的 Apple ID 是否正确
2. 测试员是否已接受邀请
3. 设备 iOS 版本 >= 17.0
4. 设备存储空间是否充足

## 时间线总结

| 步骤 | 预计时间 |
|------|---------|
| 准备 Archive | 5 分钟 |
| 创建 Archive | 5-10 分钟 |
| 上传到 App Store Connect | 5-15 分钟 |
| Apple 处理构建 | 10-30 分钟 |
| 添加测试员 | 2 分钟 |
| 测试员安装 | 5 分钟 |

**总计**: 约 **30-60 分钟**

## 检查清单

### Archive 前
- [ ] 已选择 "Any iOS Device (arm64)"
- [ ] Scheme 为 Release
- [ ] Distribution 证书已创建
- [ ] Provisioning Profile 已刷新
- [ ] Family Controls 警告已消失

### 上传前
- [ ] Archive 构建成功
- [ ] Organizer 显示 Archive
- [ ] 选择 "App Store Connect"
- [ ] 选择 "Upload"
- [ ] 勾选推荐选项

### 上传后
- [ ] 上传成功
- [ ] 返回 App Store Connect
- [ ] 切换到 TestFlight 标签
- [ ] 看到 "Processing" 状态
- [ ] 等待处理完成

### TestFlight 配置
- [ ] 构建状态为 "Ready to Test"
- [ ] 添加内部测试员
- [ ] 测试员收到邀请
- [ ] 测试员成功安装
- [ ] App 正常运行
- [ ] Family Controls 功能正常

## 下一步

完成 TestFlight 内部测试后:
1. 收集测试反馈
2. 修复发现的问题
3. 上传新的构建版本(重复步骤 2-4)
4. 准备外部测试(可选)
5. 准备 App Store 提交

## 需要帮助?

如果遇到问题:
1. 查看 Xcode 的错误信息
2. 检查 App Store Connect 的构建状态
3. 查看邮件通知
4. 参考本指南的常见问题部分
