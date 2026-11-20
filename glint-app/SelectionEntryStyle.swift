import AppKit

enum SelectionEntryMarkerShape: Equatable {
    case roundedSquare
}

enum SelectionEntryMarkerFillRole: Equatable {
    case terracotta
}

struct SelectionEntryMarkerStyle: Equatable {
    let shape: SelectionEntryMarkerShape
    let visibleSize: NSSize
    let hitSize: NSSize
    let cornerRadius: CGFloat
    let fillRole: SelectionEntryMarkerFillRole
    let showsInteriorGlyph: Bool
    let borderWidth: CGFloat
    let shadowOpacity: CGFloat
    let shadowBlurRadius: CGFloat
    let shadowOffset: NSSize

    static let `default` = SelectionEntryMarkerStyle(
        shape: .roundedSquare,
        visibleSize: NSSize(width: 10, height: 10),
        hitSize: NSSize(width: 22, height: 22),
        cornerRadius: 2.5,
        fillRole: .terracotta,
        showsInteriorGlyph: false,
        borderWidth: 0.75,
        shadowOpacity: 0.18,
        shadowBlurRadius: 2.5,
        shadowOffset: NSSize(width: 0, height: -1)
    )
}
