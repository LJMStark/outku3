# 页面重构规范

## 概述

本文档定义了 Kirole iOS 应用主要页面的重构规范，目标是实现与参考代码（React/TypeScript）的**像素级精确**还原。

## 参考代码位置

```
/Users/demon/vibecoding/kirole3/页面一比一还原 (Copy)/src/
├── App.tsx              # 主应用框架、Header、页面导航
├── components/
│   ├── PetPage.tsx      # 宠物页面
│   ├── PetStatusPage.tsx # 宠物状态页面
│   └── SettingsPage.tsx  # 设置页面
└── utils/
    └── themes.ts        # 主题定义
```

## 重构范围

| 页面 | 对应文件 | 说明 |
|------|----------|------|
| Home | HomeView.swift | 时间线视图、事件卡片 |
| Pet | PetPageView.swift | 宠物展示、任务列表 |
| Pet Status | PetStatusView.swift | 宠物状态、统计数据 |
| Settings | SettingsView.swift | 设备、主题、头像、集成 |
| Header | AppHeaderView.swift | 完全重写，独立组件 |

## 主题系统

采用参考代码的 3 个主题，替换现有的 5 个主题：

### Theme 1: Classic Warm
```swift
colors:
  primary: #a67c52
  primaryDark: #8b6f47
  primaryLight: #d4a574
  accent: #4a5f4f
  accentLight: #d4e8e0
  accentDark: #3a4f3f

gradients:
  header: linear-gradient(to bottom, #a67c52, #8b6f47)
  card: linear-gradient(to bottom right, #d4e8e0, #c8ddd4)
```

### Theme 2: Elegant Purple
```swift
colors:
  primary: #9b7bb5
  primaryDark: #7a5d8f
  primaryLight: #c4a7d9
  accent: #5f4a6f
  accentLight: #e8d4f0
  accentDark: #4a3555

gradients:
  header: linear-gradient(to bottom, #9b7bb5, #7a5d8f)
  card: linear-gradient(to bottom right, #e8d4f0, #d9c4e6)
```

### Theme 3: Modern Teal
```swift
colors:
  primary: #5a9aa8
  primaryDark: #457a85
  primaryLight: #7ec4d4
  accent: #4a6f6f
  accentLight: #d4e8e8
  accentDark: #3a5555

gradients:
  header: linear-gradient(to bottom, #5a9aa8, #457a85)
  card: linear-gradient(to bottom right, #d4e8e8, #c4dddd)
```

## 动画策略

**iOS 原生化**：保留动画意图，使用 SwiftUI 原生动画系统实现。

| React (framer-motion) | SwiftUI |
|-----------------------|---------|
| `initial={{ opacity: 0 }}` | `.opacity(0)` + `.onAppear` |
| `animate={{ opacity: 1 }}` | `withAnimation { }` |
| `transition={{ duration: 0.5 }}` | `.animation(.easeInOut(duration: 0.5))` |
| `whileHover={{ scale: 1.05 }}` | 不适用（移动端无 hover） |
| `whileTap={{ scale: 0.95 }}` | `.scaleEffect` + `@GestureState` |
| `type: 'spring'` | `.spring()` |

## 代码组织

### 文件结构

```
KirolePackage/Sources/KiroleFeature/
├── Design/
│   └── Theme.swift              # 重写：3个主题
├── Views/
│   ├── Components/
│   │   ├── AppHeaderView.swift  # 新建：独立Header组件
│   │   ├── TaskItemView.swift   # 新建：任务项组件
│   │   ├── StatRowView.swift    # 新建：统计行组件
│   │   └── ToggleSwitchView.swift # 新建：开关组件
│   ├── Home/
│   │   ├── HomeView.swift       # 重写：主视图
│   │   ├── TimelineView.swift   # 新建：时间线组件
│   │   └── EventCardView.swift  # 新建：事件卡片组件
│   ├── Pet/
│   │   ├── PetPageView.swift    # 重写：宠物页面
│   │   └── PetStatusView.swift  # 重写：宠物状态页面
│   └── Settings/
│       ├── SettingsView.swift   # 重写：设置主视图
│       ├── ThemeSectionView.swift    # 新建：主题选择
│       ├── AvatarSectionView.swift   # 新建：头像选择
│       └── IntegrationSectionView.swift # 新建：集成管理
└── Models/
    └── Models.swift             # 重写：数据模型
```

### 文件大小规范

- 目标：200-400 行/文件
- 最大：800 行/文件
- 超过 400 行时考虑拆分

## 数据模型

完全重写，匹配参考代码结构：

### Task
```swift
struct Task: Identifiable {
    let id: String
    var title: String
    var tag: String
    var tagLabel: String
    var completed: Bool
}
```

### Pet Stats
```swift
struct PetStats {
    var age: Int           // days
    var status: String     // "Exploring"
    var stage: String      // "Newborn"
    var progress: Double   // 0.0 - 1.0
    var weight: String     // "4.9g"
    var height: String     // "1.6cm"
    var wingspan: String   // "4.1cm"
}
```

### Integration App
```swift
struct IntegrationApp: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: String
}
```

### 集成应用列表（完整复制）
```swift
let integrationApps = [
    IntegrationApp(name: "Outlook Calendar", icon: "📅", color: "#0078D4"),
    IntegrationApp(name: "Apple Calendar", icon: "", color: "#000"),
    IntegrationApp(name: "Google Tasks", icon: "", color: "#4285F4"),
    IntegrationApp(name: "Microsoft To Do", icon: "✓", color: "#2564CF"),
    IntegrationApp(name: "Todoist", icon: "", color: "#E44332"),
    IntegrationApp(name: "TickTick", icon: "", color: "#4CAF50"),
    IntegrationApp(name: "Notion (Experimental)", icon: "", color: "#000"),
    IntegrationApp(name: "CalDAV", icon: "📅", color: "#666"),
    IntegrationApp(name: "iCal/WebCal", icon: "📅", color: "#666")
]
```

## 特殊元素

### 1. 事件详情弹窗

**实现方式**：混合方案 - 使用 `.sheet()` 但自定义内容布局

```swift
.sheet(isPresented: $showEventDetail) {
    EventDetailView(event: selectedEvent)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
```

### 2. 滚动到顶部按钮

```swift
// 在 ScrollView 底部显示
if showScrollToTop {
    Button(action: scrollToTop) {
        Image(systemName: "arrow.up")
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(Circle())
    }
}
```

## 图片资源

**当前状态**：尚未准备

**处理方式**：使用占位符

```swift
// 占位符示例
Image(systemName: "photo")
    .resizable()
    .aspectRatio(contentMode: .fit)
    .foregroundStyle(.secondary)
```

资源准备后替换为：
```swift
Image("pet_image")
    .resizable()
    .aspectRatio(contentMode: .fit)
```

## 实现策略

### 阶段 1：基础组件
1. Theme.swift - 重写主题系统（3个主题）
2. AppHeaderView.swift - 独立 Header 组件
3. 通用组件（TaskItemView, ToggleSwitchView 等）

### 阶段 2：页面布局
1. HomeView.swift - 基础布局（无动画）
2. PetPageView.swift - 基础布局
3. PetStatusView.swift - 基础布局
4. SettingsView.swift - 基础布局

### 阶段 3：动画效果
1. 入场动画（opacity, offset）
2. 交互动画（tap scale）
3. 持续动画（breathing effect）

### 阶段 4：数据连接
1. 连接 AppState
2. 实现数据绑定
3. 添加交互逻辑

## 文件处理

**策略**：覆盖现有文件

- 直接修改现有文件
- 不保留旧代码备份
- 新组件创建新文件

## 验收标准

### 视觉还原
- [ ] 颜色值完全匹配
- [ ] 间距/圆角/阴影一致
- [ ] 字体大小/粗细匹配
- [ ] 布局结构相同

### 交互行为
- [ ] 点击反馈一致
- [ ] 滚动行为正确
- [ ] 动画流畅自然

### 代码质量
- [ ] 文件大小 < 800 行
- [ ] 组件职责单一
- [ ] 无编译警告
- [ ] 遵循 Swift 6 并发规范

## 参考尺寸

基于参考代码的关键尺寸：

| 元素 | 尺寸 |
|------|------|
| 卡片圆角 | 24px (rounded-3xl) |
| 内边距 | 24px (p-6) |
| 小圆角 | 16px (rounded-2xl) |
| 头像尺寸 | 128x128px (w-32 h-32) |
| 图标尺寸 | 24x24px (w-6 h-6) |
| 进度点 | 12x12px (w-3 h-3) |
| 开关尺寸 | 48x28px (w-12 h-7) |

## 开始实施

准备就绪，按以下顺序开始：

1. **Theme.swift** - 主题系统重写
2. **AppHeaderView.swift** - Header 组件
3. **HomeView.swift** - 首页重构
4. **PetPageView.swift** - 宠物页面
5. **PetStatusView.swift** - 宠物状态
6. **SettingsView.swift** - 设置页面
