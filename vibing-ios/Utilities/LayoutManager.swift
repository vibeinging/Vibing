//
//  LayoutManager.swift
//  VibeTerminal
//
//  响应式布局管理器 - 处理 iPhone/iPad 不同设备和方向的布局
//

import UIKit

class LayoutManager {

    // MARK: - Device Type

    enum DeviceType {
        case iPhonePortrait
        case iPhoneLandscape
        case iPadPortrait
        case iPadLandscape

        /// 是否为 iPad
        var isiPad: Bool {
            switch self {
            case .iPadPortrait, .iPadLandscape:
                return true
            default:
                return false
            }
        }

        /// 是否为横屏
        var isLandscape: Bool {
            switch self {
            case .iPhoneLandscape, .iPadLandscape:
                return true
            default:
                return false
            }
        }

        /// 是否为竖屏
        var isPortrait: Bool {
            return !isLandscape
        }
    }

    // MARK: - Device Detection

    /// 根据视图尺寸和特性集合检测设备类型
    static func deviceType(for size: CGSize, traitCollection: UITraitCollection) -> DeviceType {
        let isiPad = traitCollection.userInterfaceIdiom == .pad
        let isLandscape = size.width > size.height

        if isiPad {
            return isLandscape ? .iPadLandscape : .iPadPortrait
        } else {
            return isLandscape ? .iPhoneLandscape : .iPhonePortrait
        }
    }

    /// 从视图控制器获取当前设备类型
    static func deviceType(for viewController: UIViewController) -> DeviceType {
        return deviceType(for: viewController.view.bounds.size, traitCollection: viewController.traitCollection)
    }

    // MARK: - Keyboard Accessory Heights

    /// 键盘辅助视图的推荐高度
    static func keyboardAccessoryHeight(for deviceType: DeviceType) -> CGFloat {
        switch deviceType {
        case .iPhonePortrait:
            // iPhone 竖屏：3 行按钮，较紧凑
            return 160

        case .iPhoneLandscape:
            // iPhone 横屏：4 行按钮，利用更宽的屏幕
            return 120

        case .iPadPortrait:
            // iPad 竖屏：4 行按钮，更多功能键
            return 180

        case .iPadLandscape:
            // iPad 横屏：完整键盘辅助视图，多行功能键
            return 200
        }
    }

    /// 键盘辅助视图的最小高度
    static func keyboardAccessoryMinHeight(for deviceType: DeviceType) -> CGFloat {
        switch deviceType {
        case .iPhonePortrait:
            return 120
        case .iPhoneLandscape:
            return 100
        case .iPadPortrait:
            return 140
        case .iPadLandscape:
            return 160
        }
    }

    // MARK: - Terminal Insets

    /// 终端视图的边距
    static func terminalInsets(for deviceType: DeviceType) -> UIEdgeInsets {
        switch deviceType {
        case .iPhonePortrait:
            // iPhone 竖屏：较小的边距
            return UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)

        case .iPhoneLandscape:
            // iPhone 横屏：更大的底部边距（为键盘辅助视图留空间）
            return UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        case .iPadPortrait:
            // iPad 竖屏：居中显示需要更多边距
            return UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        case .iPadLandscape:
            // iPad 横屏：分屏布局
            return UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        }
    }

    // MARK: - Connection Banner Heights

    /// 连接状态横幅的高度
    static func connectionBannerHeight(for deviceType: DeviceType, isCompact: Bool = false) -> CGFloat {
        switch deviceType {
        case .iPhonePortrait:
            return isCompact ? 32 : 44

        case .iPhoneLandscape:
            return 32 // 横屏时更紧凑

        case .iPadPortrait:
            return isCompact ? 36 : 48

        case .iPadLandscape:
            return 40
        }
    }

    // MARK: - Sidebar (iPad)

    /// 是否显示侧边栏（仅 iPad）
    static func shouldShowSidebar(for deviceType: DeviceType) -> Bool {
        return deviceType.isiPad
    }

    /// 侧边栏宽度
    static func sidebarWidth(for deviceType: DeviceType) -> CGFloat {
        switch deviceType {
        case .iPadPortrait:
            return 280

        case .iPadLandscape:
            return 320

        default:
            return 0 // iPhone 不显示侧边栏
        }
    }

    // MARK: - Safe Area Handling

    /// 获取安全区域边距（处理刘海屏和 Home Indicator）
    static func safeAreaInsets(for viewController: UIViewController) -> UIEdgeInsets {
        if #available(iOS 11.0, *) {
            return viewController.view.safeAreaInsets
        }
        return UIEdgeInsets.zero
    }

    /// 调整后的终端边距（包含安全区域）
    static func adjustedTerminalInsets(for deviceType: DeviceType, safeAreaInsets: UIEdgeInsets) -> UIEdgeInsets {
        let baseInsets = terminalInsets(for: deviceType)

        return UIEdgeInsets(
            top: max(baseInsets.top, safeAreaInsets.top),
            left: max(baseInsets.left, safeAreaInsets.left),
            bottom: max(baseInsets.bottom, safeAreaInsets.bottom),
            right: max(baseInsets.right, safeAreaInsets.right)
        )
    }

    // MARK: - Font Sizes

    /// 终端字体大小
    static func terminalFontSize(for deviceType: DeviceType) -> CGFloat {
        switch deviceType {
        case .iPhonePortrait:
            return 13

        case .iPhoneLandscape:
            return 12

        case .iPadPortrait:
            return 15

        case .iPadLandscape:
            return 14
        }
    }

    /// 键盘辅助视图字体大小
    static func keyboardAccessoryFontSize(for deviceType: DeviceType) -> CGFloat {
        switch deviceType {
        case .iPhonePortrait:
            return 14

        case .iPhoneLandscape:
            return 13

        case .iPadPortrait:
            return 16

        case .iPadLandscape:
            return 15
        }
    }

    // MARK: - Terminal Grid Size

    /// 根据可用空间计算终端网格大小（列数和行数）
    static func calculateTerminalGridSize(
        availableSize: CGSize,
        deviceType: DeviceType,
        fontSize: CGFloat
    ) -> (cols: Int, rows: Int) {
        // 使用单字符宽度估算
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let charWidth = "X".size(withAttributes: [.font: font]).width
        let charHeight = font.lineHeight

        let insets = terminalInsets(for: deviceType)
        let availableWidth = availableSize.width - insets.left - insets.right
        let availableHeight = availableSize.height - insets.top - insets.bottom

        let cols = max(40, Int(availableWidth / charWidth))
        let rows = max(15, Int(availableHeight / charHeight))

        return (cols, rows)
    }

    // MARK: - Layout Configuration

    /// 布局配置
    struct LayoutConfiguration {
        let deviceType: DeviceType
        let keyboardAccessoryHeight: CGFloat
        let terminalInsets: UIEdgeInsets
        let connectionBannerHeight: CGFloat
        let showSidebar: Bool
        let sidebarWidth: CGFloat
        let fontSize: CGFloat
        let keyboardAccessoryFontSize: CGFloat

        /// 获取当前布局配置
        static func current(for viewController: UIViewController) -> LayoutConfiguration {
            let deviceType = LayoutManager.deviceType(for: viewController)

            return LayoutConfiguration(
                deviceType: deviceType,
                keyboardAccessoryHeight: LayoutManager.keyboardAccessoryHeight(for: deviceType),
                terminalInsets: LayoutManager.terminalInsets(for: deviceType),
                connectionBannerHeight: LayoutManager.connectionBannerHeight(for: deviceType),
                showSidebar: LayoutManager.shouldShowSidebar(for: deviceType),
                sidebarWidth: LayoutManager.sidebarWidth(for: deviceType),
                fontSize: LayoutManager.terminalFontSize(for: deviceType),
                keyboardAccessoryFontSize: LayoutManager.keyboardAccessoryFontSize(for: deviceType)
            )
        }
    }

    // MARK: - Animation

    /// 布局动画时长
    static func layoutAnimationDuration(for deviceType: DeviceType) -> TimeInterval {
        switch deviceType {
        case .iPhonePortrait, .iPhoneLandscape:
            return 0.25

        case .iPadPortrait, .iPadLandscape:
            return 0.3
        }
    }

    /// 旋转动画的弹簧阻尼
    static func rotationSpringDamping(for deviceType: DeviceType) -> CGFloat {
        switch deviceType {
        case .iPhonePortrait, .iPhoneLandscape:
            return 0.8

        case .iPadPortrait, .iPadLandscape:
            return 0.7
        }
    }
}

// MARK: - Layout State Preservation

/// 用于在横竖屏切换时保存终端状态
struct LayoutState {
    let cols: Int
    let rows: Int
    let scrollOffset: Int
    let cursorVisible: Bool

    /// 创建空状态
    static func empty() -> LayoutState {
        return LayoutState(cols: 80, rows: 24, scrollOffset: 0, cursorVisible: true)
    }
}
