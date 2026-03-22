//
//  UITextField+Extensions.swift
//  Vibing
//
//  UITextField 扩展
//

import UIKit

extension UITextField {
    /// 设置左侧内边距
    func setLeftPadding(_ padding: CGFloat) {
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: padding, height: bounds.height))
        leftView = paddingView
        leftViewMode = .always
    }

    /// 设置右侧内边距
    func setRightPadding(_ padding: CGFloat) {
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: padding, height: bounds.height))
        rightView = paddingView
        rightViewMode = .always
    }
}
