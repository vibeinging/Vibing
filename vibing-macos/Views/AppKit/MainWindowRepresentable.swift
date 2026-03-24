//
//  MainWindowRepresentable.swift
//  VibeTerminal
//
//  SwiftUI → AppKit 桥接层（薄包装）
//

import SwiftUI
import AppKit

struct MainWindowRepresentable: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> MainWindowController {
        return MainWindowController()
    }

    func updateNSViewController(_ nsViewController: MainWindowController, context: Context) {}
}
