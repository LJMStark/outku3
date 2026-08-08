/**
 * Rebuilds the generated BLE decision report.
 * Requires Node.js and docx 9.6.1. To avoid adding a Node project to this Swift repository:
 *
 *   REPORT_DEPS_DIR="$(mktemp -d /tmp/kirole-docx-deps.XXXXXX)"
 *   npm install --prefix "$REPORT_DEPS_DIR" --no-save --ignore-scripts docx@9.6.1
 *   NODE_PATH="$REPORT_DEPS_DIR/node_modules" node scripts/generate_ble_build640_report.js
 *
 * The command above was verified on macOS from the repository root.
 */
const fs = require("fs");
const path = require("path");
const {
  AlignmentType,
  BorderStyle,
  Document,
  Footer,
  Header,
  HeadingLevel,
  LevelFormat,
  LineRuleType,
  PageNumber,
  Packer,
  Paragraph,
  ShadingType,
  Table,
  TableCell,
  TableRow,
  TextRun,
  VerticalAlign,
  WidthType,
} = require("docx");

const OUTPUT = path.resolve(
  __dirname,
  "../docs/Kirole_Build640到最新功能_最小固件改动与协议决策_2026-08-08.docx"
);

const COLORS = {
  blue: "0B72B9",
  darkBlue: "12405D",
  navy: "17324D",
  text: "243746",
  muted: "607584",
  lightBlue: "EAF5FC",
  paleBlue: "F5FAFD",
  lightGray: "F2F5F7",
  gray: "D8E0E5",
  amber: "FFF3D6",
  amberText: "825500",
  green: "E7F5EC",
  greenText: "176B3A",
  red: "FDECEC",
  redText: "9A2A2A",
  white: "FFFFFF",
};

// Use one font for every script. LibreOffice may ignore eastAsia fallback when a run also names
// a Latin-only hAnsi font, which turns Chinese into boxes in PDF export.
const FONT = "Hiragino Sans GB";

const borders = {
  top: { style: BorderStyle.SINGLE, size: 4, color: COLORS.gray },
  bottom: { style: BorderStyle.SINGLE, size: 4, color: COLORS.gray },
  left: { style: BorderStyle.SINGLE, size: 4, color: COLORS.gray },
  right: { style: BorderStyle.SINGLE, size: 4, color: COLORS.gray },
  insideHorizontal: { style: BorderStyle.SINGLE, size: 4, color: COLORS.gray },
  insideVertical: { style: BorderStyle.SINGLE, size: 4, color: COLORS.gray },
};

function textRun(text, options = {}) {
  return new TextRun({
    text,
    font: FONT,
    size: options.size || 21,
    bold: options.bold || false,
    color: options.color || COLORS.text,
    italics: options.italics || false,
    break: options.break,
  });
}

function paragraph(text, options = {}) {
  const children = Array.isArray(text)
    ? text
    : [textRun(text, {
        bold: options.bold,
        color: options.color,
        size: options.size,
        italics: options.italics,
      })];
  return new Paragraph({
    children,
    alignment: options.alignment,
    heading: options.heading,
    style: options.style,
    keepNext: options.keepNext,
    keepLines: options.keepLines,
    pageBreakBefore: options.pageBreakBefore,
    spacing: options.spacing || { after: 140, line: 300, lineRule: LineRuleType.AUTO },
    indent: options.indent,
    border: options.border,
    shading: options.shading,
  });
}

function heading1(text, pageBreakBefore = false) {
  return paragraph(text, {
    heading: HeadingLevel.HEADING_1,
    pageBreakBefore,
    keepNext: true,
    spacing: { before: 240, after: 180 },
  });
}

function heading2(text) {
  return paragraph(text, {
    heading: HeadingLevel.HEADING_2,
    keepNext: true,
    spacing: { before: 180, after: 120 },
  });
}

function bullet(text, level = 0) {
  return new Paragraph({
    children: [textRun(text)],
    numbering: { reference: "bullet-list", level },
    spacing: { after: 90, line: 290 },
  });
}

function numbered(text, level = 0) {
  return new Paragraph({
    children: [textRun(text)],
    numbering: { reference: "number-list", level },
    spacing: { after: 100, line: 290 },
  });
}

function labelParagraph(label, body, options = {}) {
  return paragraph([
    textRun(label, { bold: true, color: options.labelColor || COLORS.darkBlue }),
    textRun(body, { color: options.bodyColor || COLORS.text }),
  ], { spacing: { after: 110, line: 290 } });
}

function callout(title, body, fill = COLORS.lightBlue, titleColor = COLORS.blue) {
  return new Table({
    width: { size: 9200, type: WidthType.DXA },
    columnWidths: [9200],
    borders: {
      top: { style: BorderStyle.SINGLE, size: 10, color: titleColor },
      bottom: { style: BorderStyle.SINGLE, size: 4, color: titleColor },
      left: { style: BorderStyle.SINGLE, size: 10, color: titleColor },
      right: { style: BorderStyle.SINGLE, size: 4, color: titleColor },
      insideHorizontal: { style: BorderStyle.NONE, size: 0, color: fill },
      insideVertical: { style: BorderStyle.NONE, size: 0, color: fill },
    },
    rows: [
      new TableRow({
        cantSplit: true,
        children: [
          new TableCell({
            width: { size: 9200, type: WidthType.DXA },
            shading: { type: ShadingType.CLEAR, fill },
            margins: { top: 150, bottom: 150, left: 180, right: 180 },
            children: [
              paragraph(title, {
                bold: true,
                color: titleColor,
                size: 23,
                spacing: { after: 80 },
              }),
              paragraph(body, { spacing: { after: 0, line: 300 } }),
            ],
          }),
        ],
      }),
    ],
  });
}

function makeCell(content, options = {}) {
  const paragraphs = Array.isArray(content)
    ? content.map((item) => item instanceof Paragraph ? item : paragraph(String(item), {
        size: options.fontSize || 18,
        color: options.color || COLORS.text,
        bold: options.bold,
        spacing: { after: 60, line: 250 },
      }))
    : [paragraph(String(content), {
        size: options.fontSize || 18,
        color: options.color || COLORS.text,
        bold: options.bold,
        spacing: { after: 0, line: 250 },
      })];
  return new TableCell({
    width: options.width ? { size: options.width, type: WidthType.DXA } : undefined,
    shading: options.fill ? { type: ShadingType.CLEAR, fill: options.fill } : undefined,
    verticalAlign: VerticalAlign.CENTER,
    margins: { top: 100, bottom: 100, left: 100, right: 100 },
    children: paragraphs,
  });
}

function dataTable(headers, rows, widths, options = {}) {
  const headerRow = new TableRow({
    tableHeader: true,
    cantSplit: true,
    children: headers.map((header, index) => makeCell(header, {
      width: widths[index],
      fill: options.headerFill || COLORS.darkBlue,
      color: COLORS.white,
      bold: true,
      fontSize: options.headerFontSize || 18,
    })),
  });
  const dataRows = rows.map((row, rowIndex) => new TableRow({
    cantSplit: true,
    children: row.map((value, index) => makeCell(value, {
      width: widths[index],
      fill: rowIndex % 2 === 1 ? COLORS.paleBlue : COLORS.white,
      fontSize: options.fontSize || 17,
    })),
  }));
  return new Table({
    width: { size: widths.reduce((sum, value) => sum + value, 0), type: WidthType.DXA },
    columnWidths: widths,
    borders,
    rows: [headerRow, ...dataRows],
  });
}

function spacer(points = 120) {
  return paragraph("", { spacing: { after: points } });
}

const decisionRows = [
  [
    "进任务不卡死、墨水屏不连刷",
    "已有 0x10→0x11 和最终 0x10→0x1B。缺 5 秒兜底、latest-wins 缓存。",
    "只改固件等待和刷新状态机；不改 payload。",
    "不新增。仅补固件行为。",
  ],
  [
    "完成/跳过可重试且不重复执行",
    "已有 Device→App 0x11/0x12、App→Device 0x1B。缺跨断电 OperationID 和确认后删除规则。",
    "保留原 Type 和 v1 payload；补持久化、原样重发、匹配确认。",
    "不新增。补旧命令规则。",
  ],
  [
    "重连先回放离线动作",
    "已有 0x20/0x21，但 Build 640 只尽力处理。缺空批次、连接前屏障、顺序和队列上限。",
    "每个 0x20 对应一个完整逻辑 0x21；空 Count=0；整份待回放集合有界；任务动作永不淘汰，普通事件放不下时 best-effort 丢弃；不做分页游标。",
    "不新增。补旧命令规则。",
  ],
  [
    "设备本地保存完整当天任务",
    "DayPack 只有 3/5 条概览；0x11 只在选中任务后现场下发。缺最多 20 条完整任务、详情、三阶段文字、版本、CRC、提交结果。",
    "增加独立任务库事务，校验完成后原子替换旧库。",
    "新增 0x23。",
  ],
  [
    "设备本地保存当天日程和每日文字",
    "DayPack 已有日期、变长日程数组和部分每日文字，但当前 App 最多取 8 条，也没有独立版本和业务 ACK。",
    "只把日程提到 20 条时，保持 0x10 wire 结构，只改 App 上限和固件容量；最坏 payload 约从 3.4KB 增到 7KB，需真机确认；要完整离线文案、独立版本和原子提交时再用 0x24。",
    "只加条数：修改旧 0x10 规则；完整内容：新增 0x24。",
  ],
  [
    "断联后专注继续",
    "已有 0x10 EnterTaskIn、0x14 FocusStatus、0x20 RequestRefresh。缺本地任务资料、RTC 会话状态和重连恢复。",
    "继续复用三条旧命令；本地资料来自 0x23。断联不退页、不清零。",
    "不新增。依赖 0x23。",
  ],
  [
    "设备重启后自动对账",
    "29B 0x30 只报电量、固件和头像；0x1B 已有 Epoch/Revision。缺设备任务库与快照版本库存。",
    "0x1B payload 不变；版本写 NVS；实时 0x30 尾部扩展到 51B。",
    "扩展 0x30，不另造查询命令。",
  ],
  [
    "BLE 常开同时省电",
    "扫描、连接、GATT 都已有。缺低功耗配置、连接参数和实测门槛。",
    "只做 ESP32 电源管理和真机功耗验证。",
    "不新增；0x25 保持未分配。",
  ],
];

const missingRows = [
  ["产品范围：离线当天内容", "MVP 是否要求断网后仍有早/闲/晚多套对话、逐事件文案、屏保和结算全部内容。", "若要求，0x24 是必做；若只要最后一次在线页面，可暂存完整 DayPack 并用本地模板。"],
  ["产品范围：任务/快照自愈", "MVP 是否要求任务库和 0x1B 快照在设备清空、损坏或 App 重装后自动恢复。", "若要求，51B 0x30 库存必做；若测试期允许人工重置，可后置。"],
  ["当天内容丢失后的恢复", "0x24 分区丢失后，MVP 是否允许人工重置，还是必须自动恢复。", "51B 0x30 不含 0x24 库存。若必须自动恢复，MVP 优先让 App 每次重连幂等重发 0x24；暂不继续扩展 wire。"],
  ["固件真实基线", "当前固件版本、commit、产物哈希；哪些 v2.10.2 行为已经写进代码。", "避免把 Excel 中的定义误当成固件已完成。"],
  ["持久化容量", "任务库、当天内容、outbox、暂存区分别可用多少 NVS/LittleFS；擦写寿命目标。", "决定 20 条任务/日程和离线记录能否同时安全保存。"],
  ["最大逻辑消息", "设备能重组或边收边写的最大 payload、ATT MTU、单次最大传输时间。", "决定 0x23/0x24 以及一个完整 0x21 是否能在超时内完成。"],
  ["整份回放上限", "是否接受整份待回放集合的 MVP 建议 32 条和 4096B；若不接受，给出实测上限及原因。", "Count 虽是 1B，但单批无分页。未确认任务动作永不淘汰，普通事件只做 best-effort。"],
  ["原子提交方法", "双槽、临时文件加 rename，或其他方法；各阶段如何做强制掉电测试。", "不能出现版本是新的、内容却还是旧的。"],
  ["RTC 与跨日", "断联和重启后的时钟误差、时区来源、无时间同步时的行为。", "专注计时、三阶段文字和当天内容都依赖设备本地时间。"],
  ["EPD 忙碌状态", "busy 信号入口、一次刷新最长时间、保存最新完整包所需内存。", "决定 latest-wins 和最终只刷一次能否实现。"],
  ["低功耗目标", "屏保/连接中的电流、连接参数、24 小时稳定性和续航门槛。", "BLE 常开不是一句协议文字，必须用真机数据验收。"],
  ["存储满的页面反馈", "清完普通事件后任务 outbox 仍满时显示什么、是否允许用户先同步再操作。", "任务动作被拒绝必须让用户看见；普通事件丢弃则写串口日志。"],
];

const acceptanceRows = [
  ["P0-01", "Build 640", "核对 release/build-640-629-baseline、固件版本和实时 29B DeviceWake。"],
  ["P0-02", "Build 640", "0x10→0x11 在线进任务；断 BLE 立即本地可用；拦下 0x11 后 5 秒兜底。"],
  ["P0-03", "Build 640", "在线完成、跳过均为最终 0x10 只缓存，匹配 0x1B 后只刷新一次。"],
  ["P0-04", "Build 640", "EPD 忙时连续收到三个 DayPack，最终只显示最后一个完整版本。"],
  ["P0-05", "Build 636", "0x23 正常、坏 CRC、容量不足和掉电分支；错误时旧任务库不变。"],
  ["P0-06", "Build 636", "0x24 正常、跨日、坏 CRC 和掉电分支；错误时旧当天内容不变。"],
  ["P0-07", "Build 636", "空队列、普通事件挤压、任务 outbox 和满队列均只回一个有界 0x21；普通事件不挤掉未确认任务，匹配 0x1B 后才删任务记录。"],
  ["P0-08", "Build 636", "专注中断联跨阶段再重连：页面、时长、会话都连续；不再等 App 0x11。"],
  ["P0-09", "Build 636", "0x1B 版本写 NVS；实时 51B Wake 与 NVS 一致；损坏记录按 missing 恢复。"],
  ["P0-10", "Build 636", "屏保/低功耗下仍能连接和同步，功耗达到双方预先填写的门槛，抓包没有 0x25。"],
];

const productLossRows = [
  ["在线进任务、在线完成/跳过", "保留，可用于第一阶段联调。"],
  ["完整设备任务库和本地三阶段文字", "缺失；没有 0x23。"],
  ["当天日程与每日文案跨断电保存", "缺失；没有 0x24。"],
  ["断联后保持同一专注会话", "缺失；Build 640 只验证旧在线路径。"],
  ["离线完成/跳过跨断电、重连幂等回放", "缺失；0x20/0x21 在 Build 640 不是强制屏障。"],
  ["设备重启后的任务库和 0x1B 版本自动对账", "缺失；Wake 仍是 29B，没有任务库/快照库存。"],
  ["Build 636 的 App 同步、防重复和重试持久化修复", "Build 640 不包含；正式功能验收必须切回 Build 636。"],
];

const children = [];

children.push(
  spacer(650),
  paragraph("Kirole", {
    size: 28,
    bold: true,
    color: COLORS.blue,
    alignment: AlignmentType.CENTER,
    spacing: { after: 180 },
  }),
  paragraph("Build 640 到最新功能", {
    size: 48,
    bold: true,
    color: COLORS.navy,
    alignment: AlignmentType.CENTER,
    spacing: { after: 120 },
  }),
  paragraph("最小固件改动与协议决策", {
    size: 34,
    bold: true,
    color: COLORS.blue,
    alignment: AlignmentType.CENTER,
    spacing: { after: 340 },
  }),
  paragraph("给产品经理、App 团队和硬件团队", {
    size: 23,
    color: COLORS.muted,
    alignment: AlignmentType.CENTER,
    spacing: { after: 100 },
  }),
  paragraph("基线：Build 640 / BLE v2.10.1　　目标：Build 636 / BLE v2.18", {
    size: 20,
    color: COLORS.muted,
    alignment: AlignmentType.CENTER,
    spacing: { after: 80 },
  }),
  paragraph("2026-08-08", {
    size: 20,
    color: COLORS.muted,
    alignment: AlignmentType.CENTER,
    spacing: { after: 280 },
  }),
  callout(
    "一句话结论",
    "Build 640 可以继续做旧协议在线联调，但只改 App 达不到最新完整功能。最小升级不是重写全部协议：复用 0x11/0x12/0x1B/0x20/0x21，只新增 0x23 和 0x24，并把实时 0x30 从 29B 扩到 51B；0x25 不做。",
    COLORS.lightBlue,
    COLORS.blue
  )
);

children.push(
  heading1("一页结论", true),
  callout(
    "默认决定",
    "Build 640 保持不变，只做第一阶段在线联调；最新功能继续用 Build 636 App 验收。硬件以 v2.10.1 为施工起点逐项增加能力，不要求一次读完所有历史版本，也不在 App 主线长期维护双协议。",
    COLORS.green,
    COLORS.greenText
  ),
  spacer(90),
  bullet("只改固件行为、不动字节：5 秒兜底、EPD 忙时只留最新包、最终 0x10 + 0x1B 只刷一次、BLE 低功耗。"),
  bullet("复用旧命令并补清楚规则：0x11/0x12 的 OperationID、0x20→0x21 的空批次与单批回放、0x1B 的匹配确认和版本持久化。"),
  bullet("确实缺数据才新增：0x23 传完整任务库；0x24 传可离线保存的当天内容。"),
  bullet("已有命令只做尾部扩展：实时 0x30 从 29B 扩到 51B，报告任务库和 0x1B 快照库存。"),
  bullet("不做多页游标、不做 0x25、不做自动猜协议、不把 Build 640 补成量产包。"),
  spacer(80),
  labelParagraph("第一阶段通过代表：", "旧在线链路可联调。"),
  labelParagraph("第一阶段通过不代表：", "断联专注、离线动作、掉电恢复、任务库、当天内容或版本自愈已经完成。"),
  labelParagraph("第二阶段完成标准：", "Build 636 + BLE v2.18 的真机日志、十六进制数据、串口、EPD 录像、断电测试和功耗证据全部通过。"),
  heading2("如果产品还要继续缩 MVP 范围"),
  dataTable(
    ["路线", "固件范围", "App 代价", "会失去什么"],
    [
      ["完整 Build 636 对等（建议）", "0x23 + 0x24 + 51B 0x30；其余复用旧命令。", "沿用已经完成的 Build 636，不再另改协议。", "不失去本报告列出的最新能力。"],
      ["核心任务 MVP", "0x23 先只做 full + 单批回放 + 断联专注；固件保存最后完整 DayPack；51B 任务/快照自愈后置。", "必须另出一个单协议 App 构建：0x23 只发 full；取消 0x24 发送/ACK 硬门槛；回放后强制重发当天 0x10，必要时重发 0x16。若只要 20 条日程，可把现有 0x10 截取上限从 8 调到 20。不能直接用未改的 Build 636。", "只保留最后同步的一套气泡或本地模板；没有独立内容提交确认、早/闲/晚三套文字、逐事件伴侣文案和任务/快照选择性库存自愈。"],
      ["只停在 Build 640", "仅旧在线路径和 v2.10.2 行为。", "不用改 App。", "任务库、当天内容、断联专注、跨断电 outbox 和版本自愈都没有。"],
    ],
    [1750, 2500, 2850, 2100],
    { fontSize: 15 }
  ),
  spacer(90),
  paragraph("从整个系统的改动量看，默认仍建议第一条：0x24 和 51B App 代码已经完成并有测试；现在再删掉它们会产生一个新的中间协议和新的 App 构建。只有产品明确接受第二条所列损失时，才值得缩到核心任务 MVP。", {
    bold: true,
    color: COLORS.darkBlue,
  }),
  heading2("版本证据"),
  dataTable(
    ["对象", "证据"],
    [
      ["Build 640", "固定标签 release/build-640-629-baseline；commit 023b790；实现来自 Build 629 / BLE v2.10.1。"],
      ["Build 636", "固定归档 archive/build-636；commit fbd218b；当前 v2.18 App 能力基线。"],
      ["硬件 Excel", "Kirole_BLE协议命令字节表.xlsx，按 BLE v2.10.1 整理；没有 0x23/0x24，实时 DeviceWake 仍为 29B。"],
    ],
    [1800, 7000],
    { fontSize: 18 }
  )
);

children.push(
  heading1("1. “基于 Build 640”到底是什么意思", true),
  paragraph("这里的“基于 Build 640”是指：硬件先拿自己已经实现的 v2.10.1 当起点，按差异表增加能力。它不表示以后继续从 Build 640 的旧 App 代码开发。"),
  dataTable(
    ["阶段", "App", "目的", "不能证明什么"],
    [
      ["阶段 1", "Build 640", "跑通 0x10/0x11、在线完成/跳过、0x1B 和一次刷屏。", "不能证明 0x23、0x24、51B Wake、断联专注和跨断电恢复。"],
      ["阶段 2", "Build 636", "验收最新 App 已经发送和处理的 v2.18 能力。", "Swift 测试通过仍不能替代固件 Flash、RTC、EPD 和功耗证据。"],
    ],
    [1200, 1400, 3000, 3200],
    { fontSize: 17 }
  ),
  spacer(100),
  callout(
    "为什么不把兼容代码长期塞进 App",
    "Build 636 在连接前会做离线回放，也会发送 0x23/0x24，并已经停发 App→Device 0x11。长期同时维护两套连接、任务、专注和持久化状态机会增加回归风险。现在没有真实用户，最稳的做法是固定测试包配固定固件，阶段完成后统一切到新协议。",
    COLORS.amber,
    COLORS.amberText
  )
);

children.push(
  heading1("2. 从 Build 640 到最新功能：最小改动表", true),
  paragraph("下面按“已有数据够不够”决定改法。能复用的命令不另造；旧帧承载不了完整状态时才新增。"),
  dataTable(
    ["最新需求", "Build 640 已有 / 缺失", "最小做法", "协议决定"],
    decisionRows,
    [1850, 3350, 2500, 1400],
    { fontSize: 16, headerFontSize: 17 }
  ),
  spacer(120),
  callout(
    "最小 wire 变化总计",
    "若目标是完整匹配 Build 636：新增 2 个命令 0x23、0x24；扩展 1 个既有通知 0x30 29B→51B。若产品签字选择核心任务 MVP，可把 0x24 和 51B 任务/快照库存自愈后置，但必须另出一个去掉这些硬门槛的 App 构建。若产品只要求把日程从 8 条提高到 20 条，0x10 的数组格式本身不用新增命令，只需改 App 上限并确认固件容量。",
    COLORS.green,
    COLORS.greenText
  )
);

children.push(
  heading1("3. 为什么 0x23、0x24 要新增，其他命令不用", true),
  heading2("0x23：新增是必要的"),
  paragraph("Build 640 的 DayPack 只带 Overview 要显示的 3/5 条置顶任务；0x11 TaskInPage 只在用户选中任务后临时给一条详情。最新需求要求设备断网时也能从最多 20 条当天任务中读取标题、详情和三阶段文字，还要知道删除、版本、CRC 和整次提交是否成功。旧帧没有“完整任务库”的边界。"),
  bullet("把全部任务硬塞进 DayPack，会改变旧 DayPack 解析、让每次展示刷新重复传大量资料。"),
  bullet("循环发送多条 0x11，没有完整列表版本、删除规则和原子提交边界，掉电后容易留下半新半旧。"),
  bullet("所以独立 0x23 是更小、更稳的改动：只有任务库变化时发送，成功后一次替换。"),
  heading2("0x24：新增比继续扩 DayPack 更稳"),
  paragraph("DayPack 已经有日期、变长日程数组、SupportText、DaySummary 和结算文案，固件也可以在完整重组后原子保存最后一份。因此，如果产品只要求把日程从 8 条提高到 20 条，不需要新命令：保持 0x10 wire 结构，改 App 截取上限并确认固件容量即可。按现有字段上限估算，最坏 payload 约从 3.4KB 增到 7KB；分包格式不用改，但设备重组缓冲和落盘空间必须真机确认。旧 0x03 Schedule 是另一条命令，不会自动跟着变成 20 条。"),
  paragraph("只有产品还要求早间/空闲/收尾三套文字、逐事件 CompanionDialogue、屏保作者、独立版本/ACK，以及坏 CRC 或掉电时明确保留旧版本，0x24 才值得新增。把这些继续塞进高频 DayPack，反而会不断改变旧解析器。"),
  bullet("0x24 只在当天内容变化时提交，和任务库分开计版本。"),
  bullet("设备先校验完整包，再替换旧 committed；失败继续显示旧完整包。"),
  bullet("因此新增 0x24 是为了减少 DayPack 的变化，不是为了多造一层协议。"),
  heading2("0x30：扩展旧通知就够了"),
  paragraph("0x30 本来就是设备上线时报告库存的通知。把任务库和 0x1B 快照版本加在尾部，比新建查询命令少一次往返、少一个状态机。App 已按 payload 长度区分 29B、42B 和 51B。批次里的 0x30 记录仍只有 Type + BatteryLevel 两字节，不能扩成 51B。"),
  callout("边界提醒", "51B 0x30 没有 0x24 当天内容库存，所以它只解决任务库和 0x1B 快照的选择性自愈。当前 Build 636 在内容指纹没变时不会自动重发 0x24，不能把这项能力写成已经完成。若产品要求 0x24 分区丢失后也自动恢复，MVP 优先让 App 每次重连幂等重发当天 0x24，不继续扩展 wire；只有以后确实要减少重传流量时才考虑扩 0x30。", COLORS.amber, COLORS.amberText),
  heading2("0x11/0x12/0x1B/0x20/0x21：只补规则"),
  paragraph("这些帧已经带有动作、OperationID、任务 ID、时间、结果和版本。问题不在字段不足，而在固件是否把记录存进 Flash、是否按原顺序重发、是否收到匹配 0x1B 后才删除，以及空队列是否也明确回 0x21。这里不需要新命令。")
);

children.push(
  heading1("4. 现在还缺什么信息", true),
  paragraph("下面这些不是 App 可以猜出来的。固件团队填写后，双方只冻结一次容量和超时常量，再开工。"),
  dataTable(
    ["待确认", "硬件需要给出的答案", "为什么"],
    missingRows,
    [1650, 4300, 3150],
    { fontSize: 16 }
  ),
  spacer(100),
  callout(
    "当前建议值，不是假装已经确认的事实",
    "为了让 MVP 有边界，当前建议整份待回放集合最多 32 条、单个逻辑 0x21 payload 最多 4096B。wire 的 Count 是 1B，理论上可到 255。未确认 0x11/0x12 永不淘汰；普通事件放不下时只做 best-effort，并给任务动作让位。硬件需要用真实 Flash/RAM 和传输时间确认 32/4096；如果不支持，要在签收协议前给出实测数字和原因。",
    COLORS.amber,
    COLORS.amberText
  )
);

children.push(
  heading1("5. 最小施工顺序", true),
  numbered("先补 v2.10.2 的纯固件行为：无 BLE 立即可用、有 BLE 最多等 5 秒、EPD latest-wins、最终 0x10 + 0x1B 只刷一次。用 Build 640 验收。"),
  numbered("实现 0x23 任务库和原子提交。设备进入任务时仍发 0x10，但随后直接读本地任务库，不再等 App 的 0x11。"),
  numbered("在已有 0x11/0x12/0x1B/0x20/0x21 上补强一致任务 outbox、普通事件 best-effort、空批次、顺序回放和确认后删除。整份集合保持有界单批，不加分页游标。"),
  numbered("实现断联专注：本地 RTC 继续计时和切阶段；重连保持同一页面、同一时长、同一会话。"),
  numbered("实现 0x24 当天内容包，与 0x23 分开存储、分开提交、分开失败。"),
  numbered("把 0x1B 版本写入 NVS，并把实时 0x30 扩到 51B；最后做任务库/快照自愈、低功耗和 24 小时连接测试。0x24 丢失恢复按产品在第 4 节的选择单独处理。"),
  spacer(100),
  callout(
    "切换规则",
    "Build 640 和旧固件只负责步骤 1。完整路线从步骤 2 开始使用 Build 636 和新固件。若产品选择核心任务 MVP，必须给这个唯一协议另出一个新 App 构建，不能在一次连接里自动猜版本，也不长期保留双协议。测试设备可以清 App 本地数据和设备协议状态。",
    COLORS.lightBlue,
    COLORS.blue
  )
);

children.push(
  heading1("6. P0 真机验收", true),
  paragraph("每项必须有 App 日志、固件串口、实际十六进制数据和连续页面录像。涉及掉电和功耗的项目必须有真机证据。"),
  dataTable(
    ["编号", "测试包", "明确通过标准"],
    acceptanceRows,
    [1000, 1250, 6850],
    { fontSize: 16 }
  ),
  spacer(120),
  labelParagraph("阶段 1 通过：", "只代表 Build 640 在线基线可用，可以开始新固件施工。"),
  labelParagraph("阶段 2 通过：", "代表本报告的 BLE/固件 P0 门槛通过；整机量产仍需续航、老化、屏幕和发布验收。"),
  labelParagraph("范围例外：", "只有产品、App、固件三方签字选择“核心任务 MVP”时，才可把 0x24 与 51B 任务/快照自愈验收后置；同时必须记录新 App 构建号和被放弃的体验。"),
  labelParagraph("不通过：", "任一用例缺版本、帧、串口、录像或掉电证据，都按不通过，不写“基本通过”。", { labelColor: COLORS.redText })
);

children.push(
  heading1("7. 如果停在 Build 640，产品会失去什么", true),
  paragraph("Build 640 的作用是把旧在线路径先跑通。它不是 Build 636 的替代品。如果产品决定长期停在 640，下面这些最新能力和修复不会进入验收。"),
  dataTable(
    ["能力", "使用 Build 640 的结果"],
    productLossRows,
    [3650, 5450],
    { fontSize: 17 }
  ),
  spacer(120),
  callout(
    "给产品经理的选择",
    "短期可以用 Build 640 尽快看到在线页面和按键结果；如果要验收最新产品体验，仍要让固件补 0x23、0x24、51B Wake 和离线本地状态。两者不是二选一：640 是第一阶段，636/v2.18 是目标。",
    COLORS.green,
    COLORS.greenText
  )
);

children.push(
  heading1("8. 明确不做", true),
  bullet("不修改已发布的 Build 640；发现问题另建临时联调包。"),
  bullet("不在 Build 636 主线长期维护 legacyV2101 双协议状态机。"),
  bullet("不为完成、跳过和离线回放再造命令；继续用 0x11/0x12 + 0x20/0x21 + 0x1B。"),
  bullet("不做多页回放、连接内游标和额外终止帧；一个 0x20 只对应一个完整逻辑 0x21。"),
  bullet("不实现 0x25 DevicePowerControl；BLE 常开和省电靠设备电源管理与连接参数。"),
  bullet("不把模拟器或 Swift 测试写成固件已经完成；NVS、RTC、EPD、BLE 和断电必须真机验证。"),
  heading2("双方签字"),
  dataTable(
    ["角色", "姓名", "版本 / 产物", "结论", "日期"],
    [
      ["产品经理", "", "需求范围已确认", "通过 / 不通过", ""],
      ["App 负责人", "", "Build 640 / Build 636", "通过 / 不通过", ""],
      ["固件负责人", "", "固件版本 / commit", "通过 / 不通过", ""],
      ["测试见证人", "", "证据目录", "材料齐全 / 不齐", ""],
    ],
    [1600, 1450, 2600, 1900, 1550],
    { fontSize: 17 }
  ),
  heading2("参考文件"),
  bullet("docs/BLE通信协议规格文档.md — wire 协议唯一依据。"),
  bullet("docs/固件功能规格文档.md — 固件页面、存储、掉电和验收要求。"),
  bullet("docs/BLE两阶段联调与验收清单.md — 可直接填写的简版联调表。"),
  bullet("Kirole_BLE协议命令字节表.xlsx — 硬件团队的 BLE v2.10.1 基线输入。")
);

const header = new Header({
  children: [
    new Paragraph({
      children: [
        textRun("Kirole · Build 640 到最新功能 · MVP 协议决策", {
          size: 16,
          color: COLORS.muted,
        }),
      ],
      border: {
        bottom: { style: BorderStyle.SINGLE, size: 4, color: COLORS.gray },
      },
      spacing: { after: 60 },
    }),
  ],
});

const footer = new Footer({
  children: [
    new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [
        textRun("内部联调决策文件　·　第 ", { size: 16, color: COLORS.muted }),
        new TextRun({ children: [PageNumber.CURRENT], font: FONT, size: 16, color: COLORS.muted }),
        textRun(" 页", { size: 16, color: COLORS.muted }),
      ],
    }),
  ],
});

const document = new Document({
  creator: "Kirole App Team",
  title: "Kirole Build 640 到最新功能：最小固件改动与协议决策",
  description: "Build 640 / BLE v2.10.1 到 Build 636 / BLE v2.18 的 MVP 差异、缺失信息、协议选择和真机验收。",
  styles: {
    default: {
      document: {
        run: { font: FONT, size: 21, color: COLORS.text },
        paragraph: { spacing: { after: 140, line: 300, lineRule: LineRuleType.AUTO } },
      },
    },
    paragraphStyles: [
      {
        id: "Title",
        name: "Title",
        basedOn: "Normal",
        next: "Normal",
        run: { font: FONT, size: 48, bold: true, color: COLORS.navy },
        paragraph: { alignment: AlignmentType.CENTER, spacing: { after: 180 } },
      },
      {
        id: "Heading1",
        name: "Heading 1",
        basedOn: "Normal",
        next: "Normal",
        quickFormat: true,
        run: { font: FONT, size: 32, bold: true, color: COLORS.blue },
        paragraph: {
          spacing: { before: 260, after: 160 },
          keepNext: true,
          outlineLevel: 0,
        },
      },
      {
        id: "Heading2",
        name: "Heading 2",
        basedOn: "Normal",
        next: "Normal",
        quickFormat: true,
        run: { font: FONT, size: 25, bold: true, color: COLORS.darkBlue },
        paragraph: {
          spacing: { before: 180, after: 100 },
          keepNext: true,
          outlineLevel: 1,
        },
      },
    ],
  },
  numbering: {
    config: [
      {
        reference: "bullet-list",
        levels: [
          {
            level: 0,
            format: LevelFormat.BULLET,
            text: "•",
            alignment: AlignmentType.LEFT,
            style: { paragraph: { indent: { left: 500, hanging: 260 } } },
          },
          {
            level: 1,
            format: LevelFormat.BULLET,
            text: "–",
            alignment: AlignmentType.LEFT,
            style: { paragraph: { indent: { left: 900, hanging: 260 } } },
          },
        ],
      },
      {
        reference: "number-list",
        levels: [
          {
            level: 0,
            format: LevelFormat.DECIMAL,
            text: "%1.",
            alignment: AlignmentType.LEFT,
            style: { paragraph: { indent: { left: 560, hanging: 300 } } },
          },
        ],
      },
    ],
  },
  sections: [
    {
      properties: {
        page: {
          size: { width: 11906, height: 16838 },
          margin: { top: 1100, right: 1000, bottom: 1100, left: 1000, header: 500, footer: 500 },
        },
      },
      headers: { default: header },
      footers: { default: footer },
      children,
    },
  ],
});

fs.mkdirSync(path.dirname(OUTPUT), { recursive: true });
Packer.toBuffer(document)
  .then((buffer) => {
    fs.writeFileSync(OUTPUT, buffer);
    process.stdout.write(`${OUTPUT}\n`);
  })
  .catch((error) => {
    process.stderr.write(`${error.stack || error}\n`);
    process.exitCode = 1;
  });
