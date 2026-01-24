# 智能 E-Paper 桌面伴侣 MVP - 技术规范文档

> 基于采访结果整理，2026-01-24

---

## 1. 项目概述

### 1.1 产品定位
- **产品名称**: Outku (智能 E-Paper 桌面伴侣)
- **目标用户**: 美国/国际市场远程工作者 (Kickstarter 众筹)
- **核心价值**: 通过 AI 驱动的像素宠物陪伴，帮助用户建立健康的工作习惯

### 1.2 项目范围
- **预算**: 88,000 RMB
- **工期**: 45 个工作日
- **优先级**: App 优先开发，硬件集成后续进行

---

## 2. 技术架构

### 2.1 iOS App 技术栈
| 组件 | 技术选型 |
|------|----------|
| 平台 | iOS 17.0+ (iPhone only) |
| 语言 | Swift 6.1+ (strict concurrency) |
| UI 框架 | SwiftUI + Model-View 模式 |
| 状态管理 | @Observable (AppState singleton) |
| 本地存储 | SwiftData |
| 网络层 | Combine + async/await |
| 测试框架 | Swift Testing |

### 2.2 后端技术栈
| 组件 | 技术选型 |
|------|----------|
| 数据库 | Supabase (PostgreSQL) |
| AI 服务 | LangChain.js + OpenAI API |
| 认证 | Supabase Auth |
| 实时同步 | Supabase Realtime |

### 2.3 第三方集成
| 服务 | 用途 |
|------|------|
| Google Calendar API | 日历事件读取 |
| Google Tasks API | 任务读取 + 完成状态同步 |
| Apple Sign In | 用户认证 |
| Google Sign In | 用户认证 + API 授权 |
| OpenAI API | Haiku 生成 |
| CoreBluetooth | E-Paper 硬件通信 |

---

## 3. 数据同步策略

### 3.1 架构模式
- **Offline-first**: 本地优先，支持离线使用
- **Real-time sync**: 有网络时实时同步

### 3.2 任务数据流
```
Google Calendar ──读取──> App (只读)
Google Tasks ────读取──> App (只读)
App 任务完成 ───同步──> Google Tasks (双向)
App 状态 ──────同步──> Supabase (双向)
```

### 3.3 同步规则
| 数据类型 | 方向 | 说明 |
|----------|------|------|
| 日历事件 | Google → App | 只读，不创建新事件 |
| 任务列表 | Google → App | 只读，不创建新任务 |
| 任务完成状态 | App ↔ Google | 双向同步 |
| 宠物状态 | App ↔ Supabase | 双向同步 |
| 用户偏好 | App ↔ Supabase | 双向同步 |

---

## 4. 用户认证

### 4.1 认证方式
1. **Apple Sign In** - 主要认证方式
2. **Google Sign In** - 用于 Google API 授权

### 4.2 认证流程
```
1. 用户选择 Apple Sign In 或 Google Sign In
2. 完成 OAuth 认证
3. 如选择 Apple Sign In，后续需要 Google 授权以访问日历/任务
4. 获取 Google OAuth tokens 用于 API 调用
5. 创建/更新 Supabase 用户记录
```

---

## 5. 宠物系统

### 5.1 宠物形态
- **艺术风格**: 像素风格，狐狸/猫咪造型
- **绘制方式**: 代码绘制 (SwiftUI Canvas/Path)
- **可选形态**: Cat, Dog, Bunny, Bird, Dragon

### 5.2 宠物状态 (4 种)
| 状态 | 触发条件 | 视觉表现 |
|------|----------|----------|
| Happy/Excited | 完成任务、连续打卡 | 跳跃、闪烁眼睛 |
| Focused | 工作时间段 | 专注表情、安静动作 |
| Sleepy | 夜间时段 | 打哈欠、闭眼 |
| Missing | 长时间未互动 | 寻找姿态、期待表情 |

### 5.3 场景系统 (4 种)
| 场景 | 触发条件 | 背景元素 |
|------|----------|----------|
| Indoor/Home | 默认场景 | 室内家具、窗户 |
| Outdoor/Play | 休息时间、周末 | 草地、树木、阳光 |
| Night/Sleep | 晚间时段 (22:00-06:00) | 星空、月亮、床铺 |
| Work/Focus | 工作时间有任务 | 书桌、电脑、文具 |

### 5.4 场景触发机制
- **Combined**: 时间 + 任务状态综合判断
- 时间权重: 40%
- 任务状态权重: 60%

### 5.5 宠物成长 (MVP 简化版)
- **成长模式**: 线性成长 (非分支进化)
- **成长阶段**: Baby → Child → Teen → Adult → Elder
- **成长因素**: 任务完成数、连续打卡天数
- **属性变化**: 体重、身高、尾巴长度随成长增加

### 5.6 宠物命名
- **默认名称**: 系统提供默认名称
- **可编辑**: 用户可在设置中修改

### 5.7 宠物缺席行为
- **策略**: Gentle reminder (温和提醒)
- 长时间未互动时，宠物显示 Missing 状态
- 不使用负面惩罚机制

---

## 6. AI 功能

### 6.1 Haiku 生成
| 触发时机 | 内容特点 |
|----------|----------|
| 每日早晨 | 鼓励性、新一天的期待 |
| 完成任务时 | 庆祝性、成就感 |

### 6.2 AI 记忆范围
- **任务模式**: 用户的任务完成习惯、高效时段
- **交互历史**: 与宠物的互动记录
- **情感状态**: 用户的情绪变化趋势

### 6.3 任务交互模式
- **Combined**: 主动 + 按需 + 完成时
- 主动提醒即将到期的任务
- 用户可主动查看任务列表
- 完成任务时触发庆祝动画和 Haiku

---

## 7. UI/UX 设计

### 7.1 设计参考
- **参考产品**: Inku
- **原型图**: 作为参考，非严格遵循
- **视觉风格**: 按照原型图的暖色调风格

### 7.2 页面结构
| 页面 | 功能 |
|------|------|
| Home | 时间线视图、事件卡片、Haiku 展示 |
| Pet | 宠物展示、任务管理、连续打卡 |
| Settings | 主题选择、宠物形态、集成管理 |

### 7.3 主题系统
保留现有 5 种主题:
- Cream (默认)
- Sage
- Lavender
- Peach
- Sky

### 7.4 iOS Widget
- **类型**: Combined view (组合视图)
- **内容**: 宠物 + 今日任务 + 连续打卡天数
- **尺寸**: Small, Medium, Large

### 7.5 每日总结
- 按照原型图设计
- 显示当日完成情况、宠物状态变化、明日预览

---

## 8. Onboarding 流程

### 8.1 设计原则
- **角色**: 作为资深情感专家设计
- **目标**: 建立用户与宠物的情感连接
- **风格**: 故事驱动，温暖治愈

### 8.2 流程步骤
1. **欢迎页** - 产品介绍，设定期待
2. **宠物孵化** - 选择宠物形态，命名
3. **连接账户** - Google 授权，日历/任务同步
4. **功能介绍** - 核心功能引导
5. **开始旅程** - 进入主界面

### 8.3 音效
- **状态**: 需要寻找合适的音效资源
- **场景**: Onboarding 动画、任务完成、宠物互动

---

## 9. 硬件集成

### 9.1 当前状态
- **BLE 协议**: 开发中
- **优先级**: App 优先，硬件集成后续

### 9.2 E-Paper 页面设计
- **状态**: 未开始设计
- **核心页面**: 待定义

### 9.3 通知策略
- **策略**: Hardware-first
- 优先通过 E-Paper 设备显示通知
- 设备未连接时回退到 iOS 通知

---

## 10. 数据与隐私

### 10.1 数据分析
- **MVP 阶段**: 不集成分析服务
- **后续考虑**: 可选集成

### 10.2 崩溃报告
- **MVP 阶段**: 跳过
- **后续考虑**: Sentry 或 Firebase Crashlytics

### 10.3 隐私保护
- 最小化数据收集
- 本地优先存储
- 用户数据加密

---

## 11. 当前代码评估

### 11.1 需要重大修改的部分
| 模块 | 修改内容 |
|------|----------|
| UI 设计 | 按照原型图重新设计 |
| 数据模型 | 适配 Google API 数据结构 |
| Google APIs | 新增 Calendar + Tasks 集成 |
| 后端集成 | 新增 Supabase 集成 |

### 11.2 可保留的部分
- 基础架构 (SwiftUI + @Observable)
- 主题系统
- 部分 UI 组件

---

## 12. 开发里程碑

### Phase 1: 基础架构
- [ ] 项目结构重组
- [ ] 数据模型重构
- [ ] Supabase 集成
- [ ] 认证系统 (Apple + Google Sign In)

### Phase 2: 核心功能
- [ ] Google Calendar API 集成
- [ ] Google Tasks API 集成
- [ ] 任务同步逻辑
- [ ] 离线支持

### Phase 3: 宠物系统
- [ ] 宠物代码绘制
- [ ] 状态机实现
- [ ] 场景系统
- [ ] 成长系统

### Phase 4: AI 功能
- [ ] Haiku 生成集成
- [ ] AI 记忆系统
- [ ] 智能提醒

### Phase 5: UI/UX
- [ ] 按原型图重新设计
- [ ] Onboarding 流程
- [ ] iOS Widget
- [ ] 动画和音效

### Phase 6: 硬件集成
- [ ] BLE 通信
- [ ] E-Paper 页面设计
- [ ] 硬件通知

---

## 13. 附录

### 13.1 原型图参考
- `/Users/demon/vibecoding/outku3/1.jpg` - Home 页面
- `/Users/demon/vibecoding/outku3/2.jpg` - Haiku 区域
- `/Users/demon/vibecoding/outku3/3.jpg` - Pet 页面
- `/Users/demon/vibecoding/outku3/4.jpg` - Pet 状态详情
- `/Users/demon/vibecoding/outku3/5.jpg` - Settings 页面

### 13.2 参考资源
- [Inku App](https://inku.app) - 设计参考
- [Google Calendar API](https://developers.google.com/calendar)
- [Google Tasks API](https://developers.google.com/tasks)
- [Supabase Docs](https://supabase.com/docs)

---

*文档版本: 1.0*
*最后更新: 2026-01-24*
