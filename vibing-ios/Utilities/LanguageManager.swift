//
//  LanguageManager.swift
//  Vibing (iOS)
//
//  多语言管理器 — 默认跟随系统，支持手动切换
//

import Foundation

class LanguageManager {

    static let shared = LanguageManager()

    /// 支持的语言
    enum Language: String, CaseIterable {
        case system = "system"
        case english = "en"
        case chinese = "zh-Hans"

        var displayName: String {
            switch self {
            case .system: return L("settings.followSystem")
            case .english: return "English"
            case .chinese: return "简体中文"
            }
        }
    }

    private static let key = "app_language"
    private var bundle: Bundle?

    /// 当前选择（system 或具体语言）
    var current: Language {
        get {
            let raw = UserDefaults.standard.string(forKey: Self.key) ?? "system"
            return Language(rawValue: raw) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.key)
            loadBundle()
            NotificationCenter.default.post(name: .languageDidChange, object: nil)
        }
    }

    private init() {
        loadBundle()
    }

    private func loadBundle() {
        let lang = current
        if lang == .system {
            bundle = nil // 使用系统默认
        } else if let path = Bundle.main.path(forResource: lang.rawValue, ofType: "lproj"),
                  let b = Bundle(path: path) {
            bundle = b
        } else {
            bundle = nil
        }
    }

    /// 获取本地化字符串
    func localizedString(_ key: String) -> String {
        if let bundle = bundle {
            return bundle.localizedString(forKey: key, value: nil, table: nil)
        }
        return NSLocalizedString(key, comment: "")
    }
}

// MARK: - Notification

extension Notification.Name {
    static let languageDidChange = Notification.Name("languageDidChange")
}

// MARK: - 便捷全局函数

func L(_ key: String) -> String {
    LanguageManager.shared.localizedString(key)
}
