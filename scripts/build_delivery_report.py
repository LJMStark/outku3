#!/usr/bin/env python3
"""生成《智能 E-Paper 桌面伴侣 MVP 项目交付报告》docx。

数据来源均为可核验事实：
  - 合同条款：智能E-Paper桌面伴侣MVP开发服务合同(最终版)
  - 上架状态：App Store Connect API + iTunes Lookup（2026-09-04 查询）
  - 工程数据：本仓库 git / swift test 全量回归
"""

from pathlib import Path

from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

CN_FONT = "微软雅黑"
ACCENT = RGBColor(0x1F, 0x3A, 0x5F)
MUTED = RGBColor(0x59, 0x59, 0x59)
HEADER_FILL = "E8EDF3"
BORDER_COLOR = "9AA7B4"

OUT = Path(__file__).resolve().parents[1] / "docs" / "delivery" / "Kirole_MVP项目交付报告_2026-09-04.docx"


# ---------------------------------------------------------------- helpers
def set_cn(run, name=CN_FONT):
    run.font.name = name
    run._element.rPr.rFonts.set(qn("w:eastAsia"), name)


def style_doc(doc):
    normal = doc.styles["Normal"]
    normal.font.name = CN_FONT
    normal.font.size = Pt(10.5)
    normal.element.rPr.rFonts.set(qn("w:eastAsia"), CN_FONT)
    pf = normal.paragraph_format
    pf.line_spacing = 1.45
    pf.space_after = Pt(4)


def title(doc, text, sub=None):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run(text)
    r.bold = True
    r.font.size = Pt(20)
    r.font.color.rgb = ACCENT
    set_cn(r)
    if sub:
        p2 = doc.add_paragraph()
        p2.alignment = WD_ALIGN_PARAGRAPH.CENTER
        r2 = p2.add_run(sub)
        r2.font.size = Pt(11)
        r2.font.color.rgb = MUTED
        set_cn(r2)


def h1(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(14)
    p.paragraph_format.space_after = Pt(6)
    r = p.add_run(text)
    r.bold = True
    r.font.size = Pt(13.5)
    r.font.color.rgb = ACCENT
    set_cn(r)


def h2(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(9)
    p.paragraph_format.space_after = Pt(3)
    r = p.add_run(text)
    r.bold = True
    r.font.size = Pt(11)
    set_cn(r)


def para(doc, text, size=10.5, color=None, italic=False, indent=True):
    p = doc.add_paragraph()
    if indent:
        p.paragraph_format.first_line_indent = Pt(21)
    r = p.add_run(text)
    r.font.size = Pt(size)
    r.italic = italic
    if color:
        r.font.color.rgb = color
    set_cn(r)
    return p


def bullet(doc, text, size=10.5):
    p = doc.add_paragraph(style="List Bullet")
    p.paragraph_format.space_after = Pt(2)
    r = p.add_run(text)
    r.font.size = Pt(size)
    set_cn(r)
    return p


def set_table_borders(t):
    """显式写入 tblBorders，不依赖样式表 —— WPS / 部分阅读器不渲染样式级边框。"""
    tbl_pr = t._tbl.tblPr
    borders = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "single")
        el.set(qn("w:sz"), "6")
        el.set(qn("w:space"), "0")
        el.set(qn("w:color"), BORDER_COLOR)
        borders.append(el)
    tbl_pr.append(borders)


def shade_cell(cell, fill):
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), fill)
    cell._tc.get_or_add_tcPr().append(shd)


def repeat_header(row):
    tr_pr = row._tr.get_or_add_trPr()
    el = OxmlElement("w:tblHeader")
    el.set(qn("w:val"), "true")
    tr_pr.append(el)


def table(doc, headers, rows, widths=None, font=9.5, shade_header=True):
    t = doc.add_table(rows=1, cols=len(headers))
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    set_table_borders(t)
    hdr = t.rows[0].cells
    for i, htext in enumerate(headers):
        hdr[i].text = ""
        p = hdr[i].paragraphs[0]
        p.paragraph_format.space_before = Pt(2)
        p.paragraph_format.space_after = Pt(2)
        r = p.add_run(htext)
        r.bold = True
        r.font.size = Pt(font)
        r.font.color.rgb = ACCENT
        set_cn(r)
        if shade_header:
            shade_cell(hdr[i], HEADER_FILL)
    repeat_header(t.rows[0])
    for row in rows:
        cells = t.add_row().cells
        for i, val in enumerate(row):
            cells[i].text = ""
            p = cells[i].paragraphs[0]
            p.paragraph_format.line_spacing = 1.2
            p.paragraph_format.space_before = Pt(2)
            p.paragraph_format.space_after = Pt(2)
            r = p.add_run(str(val))
            r.font.size = Pt(font)
            set_cn(r)
    if widths:
        for row in t.rows:
            for i, w in enumerate(widths):
                row.cells[i].width = Cm(w)
    return t


# ---------------------------------------------------------------- document
doc = Document()
style_doc(doc)
for s in doc.sections:
    s.top_margin = Cm(2.2)
    s.bottom_margin = Cm(2.2)
    s.left_margin = Cm(2.4)
    s.right_margin = Cm(2.4)

title(
    doc,
    "智能 E-Paper 桌面伴侣 MVP 项目交付报告",
    "合同编号：PROJ-20251224-MVP　|　报告日期：2026 年 9 月 4 日　|　用途：尾款结算依据",
)

# ---- 一、结论
h1(doc, "一、交付结论")
para(
    doc,
    "截至本报告出具之日，本项目合同第二条约定的全部核心交付模块已完成并交付；"
    "产品 iOS 客户端已于 2026 年 9 月 3 日通过 Apple 审核并在 App Store 正式上架，"
    "面向公众可下载安装。据此，合同第三条 3.2 款约定的尾款支付触发条件（“App Store 上架”）已经成就。",
)
para(
    doc,
    "同时，依据合同第四条 4.3 款“视为验收”之约定，交付物已实际投入演示与商用发布，"
    "本阶段交付视为验收通过。乙方现依约提请甲方支付合同尾款人民币 26,400 元（合同总价的 30%）。",
)

h2(doc, "上架事实凭证")
table(
    doc,
    ["项目", "内容"],
    [
        ["应用名称", "Kirole: E-Ink Companion"],
        ["Apple ID", "6759663377"],
        ["Bundle ID", "com.kirole.app"],
        ["App Store 链接", "https://apps.apple.com/us/app/kirole-e-ink-companion/id6759663377"],
        ["上架状态", "READY FOR SALE（已上架销售）"],
        ["上架版本", "2.0（构建号 655）"],
        ["正式上架日期", "2026 年 9 月 3 日"],
        ["运行环境", "iOS 17.0 及以上，免费下载，分类：效率（Productivity）"],
        ["后续版本", "2.0.1（构建号 659）已于 2026 年 9 月 4 日提交审核，属上架后常规迭代"],
    ],
    widths=[3.6, 12.4],
)
para(
    doc,
    "注：以上状态于 2026 年 9 月 4 日经 App Store Connect 官方接口与 App Store 公开商店接口双向核验，甲方可自行复核。",
    size=9,
    color=MUTED,
)

# ---- 二、合同与结算信息
h1(doc, "二、合同与结算信息")
table(
    doc,
    ["项目", "内容"],
    [
        ["项目名称", "智能 E-Paper 桌面伴侣 MVP（Smart E-Paper AI Companion – Kickstarter MVP）"],
        ["合同编号 / 报价日期", "PROJ-20251224-MVP　/　2025 年 12 月 30 日"],
        ["甲方", "深圳市诺瓦晨星科技有限公司"],
        ["乙方", "佛山市高明立木标准化服务有限公司"],
        ["合同总价", "人民币 88,000 元"],
        ["付款方式", "4-3-3（启动款 40% / 阶段验收款 30% / 尾款 30%）"],
        ["启动款", "人民币 35,200 元（合同签署后支付）—— 已完成"],
        ["阶段验收款", "人民币 26,400 元（App 核心开发 + TestFlight 测试包 + 首轮软硬件联调）—— 已完成"],
        ["尾款", "人民币 26,400 元（App Store 上架后 5 个工作日内）—— 本次请款"],
    ],
    widths=[3.6, 12.4],
)

# ---- 三、逐项对照
doc.add_page_break()
h1(doc, "三、合同交付物逐项对照（对应合同第二条 2.1）")
table(
    doc,
    ["模块", "合同约定交付物", "状态", "交付内容与证据"],
    [
        [
            "产品交互与\nUI 视觉设计",
            "原型 / 信息架构、UI 设计稿（含切图 / 标注）、关键动效源文件",
            "已交付",
            "E-Paper 屏页面与状态信息架构、App 辅助路径交互流程文档；"
            "App 全量界面视觉稿与三套主题规范；"
            "63 组图片资产（含伴侣形象多姿态、场景插画、图标）；"
            "屏幕像素切图规范《PNG→ARGB8888 KRI 转换规范》；"
            "伴侣动作序列帧源文件（sprite sheet）",
        ],
        [
            "iOS 客户端开发",
            "TestFlight 安装包、源代码、构建说明",
            "已交付",
            "App Store 正式版 2.0 已上架；TestFlight 内部（硬件验收）与外部（公测）双通道在运行；"
            "SwiftUI + Swift 6 全量源代码 246 个源文件 / 约 50,500 行；"
            "本地存储与离线可用；"
            "构建说明、密钥配置模板与发布操作手册，及自动化发布流水线",
        ],
        [
            "BLE 离线引擎\n与联调",
            "联调文档、关键协议实现、演示模式",
            "已交付",
            "《BLE 通信协议规格文档》v2.13.3（与硬件固件 Ver 1.3.1 对齐）；"
            "《BLE 初次联调指南》《全协议模拟报告》及命令字节表；"
            "App→设备 21 条命令、设备→App 18 类事件全部实现；"
            "离线指令队列、事件批量补传、断线重连与专注状态仲裁、运输模式、固件升级通道；"
            "脱离硬件的 E-Paper 屏模拟器演示通道",
        ],
        [
            "AI 核心与\n云原生后端",
            "后端 / AI 代码、部署脚本或说明、数据库结构说明",
            "已交付",
            "自托管 Supabase 云端（认证、数据同步、REST 网关）；"
            "4 个 Edge Function（第三方授权换取，密钥不下发客户端）；"
            "数据库结构定义文件 Config/supabase-schema.sql 及部署说明；"
            "AI 陪伴文案生成与结构化校验、宠物记忆与结算反馈；"
            "提示词注入防护与内容安全净化层",
        ],
        [
            "上线 / 交付与支持",
            "交付清单、账号 / 权限移交材料、支持记录",
            "已交付\n（移交待甲方确认）",
            "App Store 上架完成；配套官网、隐私政策、服务条款与审核证据材料已上线；"
            "发布边界校验脚本确保对外版本不含内部调试能力；"
            "交付与移交清单见本报告第六节；"
            "全周期共 799 次版本提交，变更记录可追溯",
        ],
    ],
    widths=[2.4, 3.4, 1.8, 8.4],
    font=9,
)

# ---- 四、关键能力
h1(doc, "四、关键能力交付说明")

h2(doc, "4.1 E-Paper 硬件核心体验")
bullet(doc, "日程包（DayPack）：每日任务、日程、天气、时间与伴侣文案一次性打包下发至墨水屏。")
bullet(doc, "任务流转：设备端可直接完成、跳过、进入任务，App 为任务状态的最终权威来源。")
bullet(doc, "专注模式：硬件点击任务反向触发 App 专注会话，支持能量瓶激励、打断检测与统计。")
bullet(doc, "场景与形象：多套显示场景、伴侣形象状态展示，支持自定义形象下发（BLE 与 WiFi 双通道）。")

h2(doc, "4.2 硬件连接与离线能力")
bullet(doc, "分时同步策略：白天每小时、夜间每四小时，配合后台唤醒与设备主动请求，兼顾续航与实时性。")
bullet(doc, "离线可用：设备离线期间的操作本地入队，重连后批量补传并原子提交，操作不丢失。")
bullet(doc, "断线重连仲裁：专注状态在断连后不被误清除，重连后按协议裁决真实状态。")
bullet(doc, "容错设计：写入闸门、限流、幂等操作编号、CRC 校验与分包重组，保证弱网 / 异常下的稳定性。")

h2(doc, "4.3 AI 陪伴与数据层")
bullet(doc, "伴侣人格化文案随时段变化（晨间问候、任务鼓励、当日结算），并同步下发至硬件显示。")
bullet(doc, "任务与日程作为上下文驱动对话，支持 Apple 日历 / 提醒事项、Google 日历 / 任务等数据源接入。")
bullet(doc, "结构化输出与校验：AI 生成内容经格式校验、长度预算与字符集净化后才允许上屏，避免乱码与越界。")
bullet(doc, "数据主权：用户数据、交互记录与“宠物记忆”存储于甲方自有云端实例，所有权归甲方。")

h2(doc, "4.4 质量保障")
table(
    doc,
    ["指标", "结果"],
    [
        ["自动化测试", "1,306 项测试 / 157 个测试套件，2026 年 9 月 4 日全量回归全部通过"],
        ["测试覆盖重点", "BLE 协议编解码、离线同步、断线重连仲裁、专注状态机、同步策略、AI 文案安全"],
        ["协议一致性", "字节级模拟解码器对协议帧做双向校验，防止 App 与固件实现漂移"],
        ["发布合规", "自动化边界校验：对外版本不含内部调试工具与调试日志，上架前强制通过"],
        ["版本可追溯", "799 次提交，覆盖 2026 年 1 月至 9 月完整开发周期"],
    ],
    widths=[3.6, 12.4],
)

# ---- 五、里程碑
doc.add_page_break()
h1(doc, "五、项目里程碑")
table(
    doc,
    ["时间", "里程碑"],
    [
        ["2025-12-30", "《开发方案 / 报价单》确认（PROJ-20251224-MVP）"],
        ["2025-12-31", "合同签署"],
        ["2026-01-24", "项目启动，代码仓库初始化，产品与信息架构基线确立"],
        ["2026-02-13", "硬件需求与固件规格交叉核对，BLE 通信协议规格文档建立"],
        ["2026-04-19", "App 核心功能完成，首批 TestFlight 内测包交付"],
        ["2026-05-08", "《BLE 初次联调指南》交付，进入软硬件联调阶段（阶段验收款条件达成）"],
        ["2026-05 至 07", "多轮软硬件联调；离线运行协议、专注状态重连协议随硬件版本迭代对齐"],
        ["2026-07", "专注打断检测重做上线；E-Paper 显示需求终态确认并全部落地"],
        ["2026-08", "App Store 上架材料准备、合规边界隔离、发布通道拆分与审核问题修复"],
        ["2026-09-03", "iOS 客户端 2.0 通过 Apple 审核，App Store 正式上架"],
        ["2026-09-04", "2.0.1 迭代版本提交审核；本交付报告出具"],
    ],
    widths=[3.0, 13.0],
)
para(
    doc,
    "关于工期：合同第三条 3.3 款约定，因硬件端固件不稳定、协议变更、设计稿调整、硬件寄送延迟等导致联调阻塞的，"
    "工期相应顺延且不视为乙方违约。本项目实际周期长于初始预估，主要源于软硬件协议在联调过程中经历多轮版本迭代"
    "（离线运行协议 Ver 1.1.0 至专注状态重连协议 Ver 1.3.1），以及 App Store 审核环节的合规问题修复；"
    "上述调整均经双方沟通确认，属合同约定的顺延情形。",
    size=9.5,
    color=MUTED,
)

# ---- 六、交付清单与移交
h1(doc, "六、交付清单与账号权限移交")

h2(doc, "6.1 已交付资产清单")
table(
    doc,
    ["类别", "内容"],
    [
        ["源代码", "iOS 客户端完整工程（App 壳 + 功能包 + 专注监测扩展）、云端 Edge Function 源码、E-Paper 屏模拟器"],
        ["设计资产", "界面视觉稿、图片资产与切图、伴侣动作序列帧源文件、屏幕像素转换规范"],
        [
            "协议与文档",
            "BLE 通信协议规格文档、命令字节表、联调指南、全协议模拟报告、硬件需求与固件规格、架构说明、发布运维手册",
        ],
        ["后端配置", "数据库结构定义文件、云端部署说明、密钥配置模板"],
        ["上线材料", "App Store 商店文案与截图、隐私政策与服务条款、官网及审核证据页面"],
        ["构建与发布", "自动化发布流水线（含内部 / 外部双通道）、发布边界校验脚本、版本记录"],
    ],
    widths=[3.0, 13.0],
)

h2(doc, "6.2 待甲方确认的移交事项")
para(
    doc,
    "以下事项需甲方指定接收人后配合完成，不影响本次尾款支付条件的成就（合同 3.2 款尾款条件为"
    "“App Store 上架 或 按甲方要求完成源码 / 权限移交”，二者满足其一即可）：",
    size=10,
)
bullet(doc, "代码仓库所有权与访问权限移交至甲方指定账号。", size=10)
bullet(doc, "云端实例（数据库、Edge Function、对象存储）管理权限移交，并交接部署与运维说明。", size=10)
bullet(doc, "第三方服务凭据（日历 / 任务数据源授权、AI 推理服务、云服务器）切换至甲方主体账户。", size=10)
bullet(
    doc,
    "当前 App Store 上架主体为开发期使用的开发者账号；如甲方需迁移至公司主体，"
    "可通过 Apple 官方 App 转移流程办理，乙方配合完成资料准备与技术交接。",
    size=10,
)

# ---- 七、边界与后续
h1(doc, "七、服务边界与后续支持")

h2(doc, "7.1 不在本期范围（合同 2.2）")
para(
    doc,
    "硬件端固件开发、硬件结构与包装设计、苹果开发者账号年费、多数据源同时接入及跨源统一同步层建设、"
    "后续新增或更换第二数据源等，均不在本期服务范围内；如有需要，双方可另行评估并签署补充协议。",
    size=10,
)

h2(doc, "7.2 首季度资源包（合同 8.2）")
para(
    doc,
    "自项目上线起 3 个月内（2026 年 9 月 3 日至 2026 年 12 月 3 日），乙方按预估合理用量"
    "（支持不超过 3,000 名活跃用户）承担 AI 推理服务额度及云服务器费用。"
    "自第 4 个月起，乙方协助甲方绑定其自有的服务支付方式，后续费用由甲方直接向服务商结算。",
    size=10,
)

h2(doc, "7.3 维护与支持（合同 8.1）")
para(
    doc,
    "在交付期及双方约定的支持期内，乙方对因自身代码缺陷导致的问题提供修复支持。"
    "支持期结束后的持续迭代需求（如金币经济系统、装饰商店等二期功能），双方另行评估；"
    "依合同 5.1 款，甲方承诺在 MVP 交付后六个月内启动二期开发的，乙方在同等条件下享有优先合作洽谈权。",
    size=10,
)

# ---- 八、尾款
h1(doc, "八、尾款结算说明")
table(
    doc,
    ["项目", "内容"],
    [
        ["请款事项", "合同尾款（合同总价 30%）"],
        ["请款金额", "人民币 26,400 元（大写：贰万陆仟肆佰元整）"],
        ["合同依据", "合同第三条 3.2 款；第四条 4.3 款（视为验收）"],
        ["条件成就日", "2026 年 9 月 3 日（App Store 正式上架日）"],
        ["约定付款期限", "上架后 5 个工作日内，即不晚于 2026 年 9 月 10 日"],
        ["收款户名", "佛山市高明立木标准化服务有限公司"],
        ["开户行", "中国工商银行股份有限公司佛山高明支行"],
        ["账号", "2013028109200145320"],
    ],
    widths=[3.6, 12.4],
)
para(
    doc,
    "依据合同第六条 6.1 款，甲方支付完毕全部款项（含尾款）后，本合同项下交付物的著作权、使用权、"
    "转让权等由甲方永久、独占享有；乙方仅保留为履行合同所需的署名权及经甲方同意的案例展示权。",
    size=9.5,
    color=MUTED,
)

# ---- 签署
h1(doc, "九、双方确认")
para(doc, "甲方确认已收到上述交付物，本阶段交付验收通过，并按合同约定支付尾款。", size=10, indent=False)
doc.add_paragraph()
sign = table(
    doc,
    ["甲方（盖章）", "乙方（盖章）"],
    [
        ["深圳市诺瓦晨星科技有限公司", "佛山市高明立木标准化服务有限公司"],
        ["授权代表签字：", "授权代表签字："],
        ["日期：　　年　　月　　日", "日期：　　年　　月　　日"],
    ],
    widths=[8.0, 8.0],
    font=10,
)
for row in sign.rows[1:]:
    for cell in row.cells:
        cell.paragraphs[0].paragraph_format.space_before = Pt(10)
        cell.paragraphs[0].paragraph_format.space_after = Pt(10)

doc.add_paragraph()
para(
    doc,
    "本报告所列上架状态、测试结果与工程数据均于 2026 年 9 月 4 日采集自 Apple 官方接口及项目代码仓库，可随时复核。",
    size=8.5,
    color=MUTED,
    indent=False,
)

OUT.parent.mkdir(parents=True, exist_ok=True)
doc.save(OUT)
print("written:", OUT)
