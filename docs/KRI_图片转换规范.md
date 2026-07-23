# PNG→ARGB8888 KRI 转换规范（iPhone App 预处理）

## 1. 目的与适用范围

KRI（Kirole Raw Image）是 Kirole 固件使用的无压缩图片格式。App 将 PNG 预先解码为设备可直接读取的 ARGB8888 裸像素，以减少 ESP32 端的 PNG 解码开销。

本文只定义一种转换结果：

```text
PNG
  ↓ 解码为左上角起始、逐行、直通 RGBA8888
  ↓ 每像素改为 B、G、R、A 字节顺序
12 字节 KRI v1 文件头 + ARGB8888 裸像素
  ↓ 分片或文件方式下发
ESP32 校验文件头和总长度后交给 LVGL
```

适用资源包括带透明度的角色、宠物和 UI 图标。本规范输出不适用于固件当前的全屏背景缓存入口；如需下发全屏背景，应另行与固件团队对齐资源格式和加载链路。

最重要的约束：

- KRI 没有压缩、行 padding、调色板、CRC 或尾部数据；
- 所有多字节整数均为小端序；
- 像素从左上角开始，按行从左到右、从上到下保存；
- 每个像素固定 4 字节，文件中的字节顺序为 **B、G、R、A**；
- Alpha 必须为直通/非预乘 alpha；
- KRI 阶段不做电子纸六色量化或抖动，这些处理由设备最终刷新时完成。

### 1.1 BLE 传输通道（v2.6.1 定案）

转换算法与传输协议是两层独立定义。BLE 传输通道已在《BLE通信协议规格文档》**v2.6.1 §4.12** 定案：

- **`CustomAvatarFrame (0x15)` SubVersion `0x03`** = 本文生成的完整 KRI v1 文件字节（≤2,240,012 B，尺寸封顶 800×700 即字节封顶），**默认 wire 格式，App 默认即发**；
- SubVersion `0x02`（PNG ≤1 MiB，固件保存为 `/assets/characters/custom/avatar.png`）保留为**联调回退通道**——App 调试开关切 OFF 时发送，供固件开发期同机 A/B 对拍；
- **不能**把 KRI bytes 放进 `0x02`——两个 SubVersion 载荷格式互斥，固件按首字节分发；
- 最大长度、目标路径（建议 `/assets/characters/custom/avatar.kri`）、完整性校验（本文 §7 + DeviceWake `AvatarCRC32` 格式无关口径）、提交时机（选用/换机/重连补推，复用既有推送机制）均已写入协议文档 §4.12「固件实现要点」。App 在 GATT 写完后仍保留待确认标记，收到匹配 `AvatarCRC32` 才停止重发。

App 侧已完整实现并默认启用：`KRIEncoder`（本文 §2–§5 的参考实现即其镜像）+ 发送前 §7 校验 + `BLEService.sendCustomAvatarKRIFrame` 发送；硬件调试开关「Avatar KRI Push」切 OFF 可临时回退 PNG 对拍。固件实现 `0x03` 前丢弃未知 SubVersion 帧即可，App 的退避重发会在固件就绪后自动补推。

## 2. KRI v1 文件格式

文件由固定 12 字节头和紧随其后的像素区组成。

| Offset | 长度 | 字段 | 固定值/说明 |
|---:|---:|---|---|
| `0` | 4 | Magic | `0x4B 0x52 0x49 0x01`，即 `KRI\x01` |
| `4` | 2 | Width | `UInt16`，小端，必须大于 0 |
| `6` | 2 | Height | `UInt16`，小端，必须大于 0 |
| `8` | 1 | Color format | 固定为 `1`，表示 ARGB8888 |
| `9` | 1 | Version | 固定为 `1` |
| `10` | 2 | Reserved | 固定为 `0x00 0x00` |
| `12` | 其余 | Pixel data | 左上到右下的连续 BGRA 像素 |

每行步长和文件总长度必须严格满足：

```text
bytesPerPixel = 4
stride        = width × 4
fileSize      = 12 + width × height × 4
```

设备上传校验要求实际文件长度与公式完全相等。多一个字节、少一个字节、存在行对齐填充或附加 CRC 都会被判为无效 KRI。

## 3. ARGB8888 像素编码

PNG 解码后的中间像素按 `R、G、B、A` 表示；写入 KRI 时，每个像素改为：

```text
B, G, R, A
```

名称 ARGB8888 描述的是 32 位颜色数值。在小端 CPU 上，将文件中的 4 字节作为 `UInt32` 解释，其数值为：

```text
0xAARRGGBB
```

例如，直通 RGBA 像素：

```text
R=200, G=100, B=50, A=128
```

写入 KRI 的 4 字节必须是：

```text
32 64 C8 80
```

### 3.1 Alpha 要求

Alpha 必须是**直通/非预乘 alpha（straight alpha）**。固件使用 `LV_COLOR_FORMAT_ARGB8888`，不是 `LV_COLOR_FORMAT_ARGB8888_PREMULTIPLIED`。

例如 `(R=200, G=100, B=50, A=128)` 仍然写 `B=50, G=100, R=200`，不能先把 RGB 乘以 `128/255`。如果把 iOS 常见的预乘 BGRA 缓冲区直接写入 KRI，透明边缘会出现暗边。

## 4. PNG→KRI 转换步骤

### 4.1 PNG 解码规范化

先将输入 PNG 解码为满足以下条件的像素缓冲区：

- `width`、`height` 均在 `1...65535` 范围内；
- 第一行是图片顶部，第一像素是左上角；
- 每像素为 8 位直通 RGBA；
- 保留 PNG alpha；
- 已应用上层图片对象携带的方向信息；
- 不保留解码器的行 padding；
- 不缩放、不裁剪、不旋转、不抖动。

如果 App 端需要与固件端得到逐字节一致的结果，建议复用 LodePNG，或确保所用解码器不会因 ICC profile / 色彩管理改变 RGB 样本值。

### 4.2 写入 KRI

1. 写入 12 字节 KRI v1 文件头；
2. `colorFormat` 固定写 `1`；
3. 遍历顺序固定为 `y=0..height-1`，每行 `x=0..width-1`；
4. 对每个直通 RGBA 像素依次写 `B、G、R、A`；
5. 不在行末添加 padding；
6. 不在像素区后追加任何数据；
7. 最终长度必须为 `12 + width × height × 4`。

## 5. Swift 参考编码器

下面的实现不负责 PNG 解码。调用方必须先提供“左上角起始、逐行、直通 RGBA8888”的缓冲区。

```swift
import Foundation

enum KRIError: Error {
    case invalidSize
    case invalidPixelBuffer
}

func encodeKRI(
    width: Int,
    height: Int,
    straightRGBA: [UInt8]
) throws -> Data {
    guard width > 0, width <= Int(UInt16.max),
          height > 0, height <= Int(UInt16.max) else {
        throw KRIError.invalidSize
    }

    let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
    let (rgbaSize, sizeOverflow) = pixelCount.multipliedReportingOverflow(by: 4)
    guard !pixelOverflow, !sizeOverflow, straightRGBA.count == rgbaSize else {
        throw KRIError.invalidPixelBuffer
    }

    var output = Data(capacity: 12 + rgbaSize)

    // KRI v1 header
    output.append(contentsOf: [0x4B, 0x52, 0x49, 0x01])
    output.append(UInt8(width & 0xFF))
    output.append(UInt8((width >> 8) & 0xFF))
    output.append(UInt8(height & 0xFF))
    output.append(UInt8((height >> 8) & 0xFF))
    output.append(0x01) // colorFormat: ARGB8888
    output.append(0x01) // version
    output.append(0x00) // reserved
    output.append(0x00) // reserved

    for i in 0..<pixelCount {
        let p = i * 4
        let r = straightRGBA[p]
        let g = straightRGBA[p + 1]
        let b = straightRGBA[p + 2]
        let a = straightRGBA[p + 3]

        // KRI/LVGL 的文件内存布局是 BGRA。
        output.append(b)
        output.append(g)
        output.append(r)
        output.append(a)
    }

    return output
}
```

### 5.1 iOS 解码侧注意事项

- `UIImage` 的逻辑方向可能由 `imageOrientation` 表示，不能只读取底层 `cgImage` 而忽略方向；
- Core Graphics 常见的 `.premultipliedFirst` / `.premultipliedLast` 会得到预乘像素；
- 应优先使用能直接输出 straight RGBA 的 PNG 解码器；
- 如果只能得到预乘数据，必须先反预乘，但这可能带来舍入损失；
- 确认输出第 0 行是图片顶部，不同图形 API 的坐标原点可能不同；
- 不要直接序列化平台相关的 32 位像素整数，应显式按 `B、G、R、A` 写入。

## 6. 2×2 标准测试向量

输入为以下 top-down RGBA 像素：

```text
第 0 行：红 (255,0,0,255)      绿 (0,255,0,255)
第 1 行：蓝 (0,0,255,255)      半透明白 (255,255,255,128)
```

生成的 KRI 共 28 字节：

```text
4B 52 49 01 02 00 02 00 01 01 00 00
00 00 FF FF  00 FF 00 FF
FF 00 00 FF  FF FF FF 80
```

建议 App 单元测试直接比较完整 `Data` 与以上字节串。该测试可以同时发现宽高端序、RGBA/BGRA 混淆、行方向和 alpha 处理错误。

## 7. App 端生成后校验

下发前至少执行以下检查：

1. 前 4 字节严格等于 `4B 52 49 01`；
2. `width > 0` 且 `height > 0`；
3. `colorFormat == 1`；
4. `version == 1`；
5. reserved 两字节均为 0；
6. `actualFileSize == 12 + width × height × 4`；
7. 抽查 `A=0`、`A=128`、`A=255` 的透明边缘，确认没有预乘造成的暗边；
8. 分片发送必须按文件 offset 顺序进行，重组后的内容与本地 KRI 完全相同。

可选但推荐：App 在传输层另外计算文件 SHA-256 或 CRC32，用于定位 BLE/Wi-Fi 分片问题。摘要只能作为传输协议元数据，不能追加在 KRI 文件尾部。

## 8. KRI 编码阶段不包含的处理

- 不预先映射为电子纸六色索引；
- 不执行 Atkinson/Floyd-Steinberg 抖动；
- 不添加任何行对齐或 padding；
- 不添加 PNG、zlib、RLE 或其他压缩；
- 不做 alpha 预乘；
- 不在 12 字节头与像素区之间插入额外元数据；
- 不在像素区后追加 CRC、摘要或其他尾部字段。

设备渲染链路会把 KRI 作为 LVGL ARGB8888 图片合成到页面，随后再针对实际屏幕统一做六色量化、抖动、旋转和 EPD 刷新。
