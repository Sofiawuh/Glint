import AppKit

// ============================================================
// 浮窗定位的纯几何逻辑(不碰 NSScreen/NSEvent,便于单测:见 geometry_tests.swift)
// ============================================================

let kScreenEdgeGap: CGFloat = 6   // 浮窗与可视区边缘的最小间距
let kCursorOffsetX: CGFloat = 8   // 浮窗左缘相对光标向右偏移
let kCursorOffsetY: CGFloat = 8   // 浮窗上缘相对光标向下偏移

let kSelectionEntryExpansionGap: CGFloat = 4
let kSelectionEntryHitSize: CGFloat = 22

enum SelectionEntryExpansionDirection: Equatable {
    case left
    case right
}

struct SelectionEntryLayout: Equatable {
    let markerFrame: NSRect
    let markerHitFrame: NSRect
    let expandedFrame: NSRect
    let expansionDirection: SelectionEntryExpansionDirection
    let continuousHitRegion: NSRect
}

// 将任意浮窗矩形严格夹紧在屏幕可视区 visibleFrame 内(四边保留 kScreenEdgeGap 间距)。
func clampRectToVisible(_ rect: NSRect, visible vf: CGRect) -> NSRect {
    var r = rect
    r.origin.x = min(max(r.origin.x, vf.minX + kScreenEdgeGap), vf.maxX - r.width - kScreenEdgeGap)
    r.origin.y = min(max(r.origin.y, vf.minY + kScreenEdgeGap), vf.maxY - r.height - kScreenEdgeGap)
    return r
}

// 划词气泡定位(AppKit 左下原点坐标):
// 浮窗左上角 (minX, maxY) 精确落在鼠标光标 pt 的右下角 (pt.x + kCursorOffsetX, pt.y - kCursorOffsetY),
// 随后展开的翻译/解释浮窗保持该左上角锚点向右、向下生长,全程不遮挡光标左上方已选中的文本。
func rectAtCursorBottomRight(_ pt: NSPoint, visible vf: CGRect, w: CGFloat, h: CGFloat) -> NSRect {
    let x = pt.x + kCursorOffsetX
    let y = pt.y - kCursorOffsetY - h
    return clampRectToVisible(NSRect(x: x, y: y, width: w, height: h), visible: vf)
}

// 兼容入口:同 rectAtCursorBottomRight
func rectNearPoint(_ pt: NSPoint, visible vf: CGRect, w: CGFloat, h: CGFloat) -> NSRect {
    return rectAtCursorBottomRight(pt, visible: vf, w: w, h: h)
}

// 文本选区微型入口定位。选区边界优先；调用方在 AX 无边界时传入以 releasePoint 为原点的零尺寸矩形。
// 可见 marker 默认以选区右下角为中心；屏幕边缘只向可视区内侧偏置，绝不翻到选区左下侧。
func selectionEntryLayout(
    selectionBounds: NSRect,
    releasePoint: NSPoint,
    visible vf: CGRect,
    markerSize: NSSize,
    expandedSize: NSSize
) -> SelectionEntryLayout {
    let anchor = selectionBounds.isEmpty
        ? NSRect(origin: releasePoint, size: .zero)
        : selectionBounds
    let safe = vf.insetBy(dx: kScreenEdgeGap, dy: kScreenEdgeGap)
    let corner = NSPoint(x: anchor.maxX, y: anchor.minY)

    var marker = NSRect(
        x: corner.x - markerSize.width / 2,
        y: corner.y - markerSize.height / 2,
        width: markerSize.width,
        height: markerSize.height
    )
    if marker.maxX > vf.maxX {
        marker.origin.x = corner.x - marker.width
    } else if marker.minX < vf.minX {
        marker.origin.x = corner.x
    }
    if marker.minY < vf.minY {
        marker.origin.y = corner.y
    } else if marker.maxY > vf.maxY {
        marker.origin.y = corner.y - marker.height
    }
    marker.origin.x = min(max(marker.minX, vf.minX), vf.maxX - marker.width)
    marker.origin.y = min(max(marker.minY, vf.minY), vf.maxY - marker.height)

    var markerHitFrame = NSRect(
        x: corner.x - kSelectionEntryHitSize / 2,
        y: corner.y - kSelectionEntryHitSize / 2,
        width: kSelectionEntryHitSize,
        height: kSelectionEntryHitSize
    )
    markerHitFrame.origin.x = min(
        max(markerHitFrame.minX, vf.minX),
        vf.maxX - markerHitFrame.width
    )
    markerHitFrame.origin.y = min(
        max(markerHitFrame.minY, vf.minY),
        vf.maxY - markerHitFrame.height
    )

    let leftExpanded = NSRect(
        x: markerHitFrame.minX - kSelectionEntryExpansionGap - expandedSize.width,
        y: markerHitFrame.midY - expandedSize.height / 2,
        width: expandedSize.width,
        height: expandedSize.height
    )
    let rightExpanded = NSRect(
        x: markerHitFrame.maxX + kSelectionEntryExpansionGap,
        y: markerHitFrame.midY - expandedSize.height / 2,
        width: expandedSize.width,
        height: expandedSize.height
    )

    let direction: SelectionEntryExpansionDirection
    let expanded: NSRect
    if leftExpanded.minX >= safe.minX {
        direction = .left
        expanded = clampRectToVisible(leftExpanded, visible: vf)
    } else {
        direction = .right
        expanded = clampRectToVisible(rightExpanded, visible: vf)
    }

    let bridge = NSUnionRect(markerHitFrame, expanded)
    return SelectionEntryLayout(
        markerFrame: marker,
        markerHitFrame: markerHitFrame,
        expandedFrame: expanded,
        expansionDirection: direction,
        continuousHitRegion: bridge
    )
}

// 多屏框选截图坐标转换:
// 将某一显示器全屏遮罩窗口内的局部选区 localRect(左下原点,相对于该屏幕窗口 frame)
// 转换为 CGWindowListCreateImage 所需的全局 Quartz 坐标(以主屏左上角为原点,Y 轴向下)。
func captureQuartzRect(localRect: NSRect, screenFrame: NSRect, primaryScreenHeight: CGFloat) -> CGRect {
    let globalMinX = screenFrame.minX + localRect.minX
    let globalMaxY = screenFrame.minY + localRect.maxY
    return CGRect(
        x: globalMinX,
        y: primaryScreenHeight - globalMaxY,
        width: localRect.width,
        height: localRect.height
    )
}

func appKitPoint(fromQuartz point: CGPoint, primaryScreenHeight: CGFloat) -> NSPoint {
    NSPoint(x: point.x, y: primaryScreenHeight - point.y)
}

func appKitRect(fromQuartz rect: CGRect, primaryScreenHeight: CGFloat) -> NSRect {
    NSRect(
        x: rect.minX,
        y: primaryScreenHeight - rect.maxY,
        width: rect.width,
        height: rect.height
    )
}

