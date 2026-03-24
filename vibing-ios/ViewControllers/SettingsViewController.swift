//
//  SettingsViewController.swift
//  VibeTerminal
//
//  综合设置视图控制器
//

import UIKit

// MARK: - Settings Enum
enum SettingSection: Int, CaseIterable {
    case account
    case language
    case connection
    case terminal
    case cursor
    case advanced
    case reset

    var title: String {
        switch self {
        case .account: return L("settings.account")
        case .language: return L("settings.language")
        case .connection: return L("settings.connection")
        case .terminal: return L("settings.terminal")
        case .cursor: return L("settings.cursor")
        case .advanced: return L("settings.advanced")
        case .reset: return L("settings.reset")
        }
    }
}

enum AccountRow: Int, CaseIterable {
    case username
    case signOut

    var title: String {
        switch self {
        case .username: return L("settings.username")
        case .signOut: return L("settings.signOut")
        }
    }
}

enum ConnectionRow: Int, CaseIterable {
    case serverAddress
    case autoReconnect

    var title: String {
        switch self {
        case .serverAddress: return "服务器地址"
        case .autoReconnect: return "自动重连"
        }
    }
}

enum TerminalRow: Int, CaseIterable {
    case fontSize
    case colorTheme

    var title: String {
        switch self {
        case .fontSize: return "字体大小"
        case .colorTheme: return "颜色主题"
        }
    }
}

enum CursorRow: Int, CaseIterable {
    case style

    var title: String {
        switch self {
        case .style: return "光标样式"
        }
    }
}

enum AdvancedRow: Int, CaseIterable {
    case heartbeatInterval

    var title: String {
        switch self {
        case .heartbeatInterval: return "心跳间隔"
        }
    }
}

enum ResetRow: Int, CaseIterable {
    case resetDefaults

    var title: String {
        switch self {
        case .resetDefaults: return "恢复默认设置"
        }
    }
}

// MARK: - Color Theme
enum TerminalColorTheme: String, CaseIterable {
    case dark = "深色"
    case light = "浅色"

    var rawValue: String {
        switch self {
        case .dark: return "dark"
        case .light: return "light"
        }
    }
}

// MARK: - Cursor Style
enum TerminalCursorStyle: String, CaseIterable {
    case block = "方块"
    case underline = "下划线"
    case bar = "竖线"

    var rawValue: String {
        switch self {
        case .block: return "block"
        case .underline: return "underline"
        case .bar: return "bar"
        }
    }
}

// MARK: - Settings Delegate
protocol SettingsDelegate: AnyObject {
    func didUpdateSettings()
}

// MARK: - Main Settings View Controller
class SettingsViewController: UIViewController {

    weak var delegate: SettingsDelegate?

    // MARK: - Properties
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    // Connection Settings
    private var serverAddress: String {
        get { UserDefaults.standard.string(forKey: "serverAddress") ?? "ws://192.168.1.100:8765" }
        set {
            UserDefaults.standard.set(newValue, forKey: "serverAddress")
            delegate?.didUpdateSettings()
        }
    }

    private var autoReconnect: Bool {
        get { UserDefaults.standard.bool(forKey: "autoReconnect") }
        set {
            UserDefaults.standard.set(newValue, forKey: "autoReconnect")
            delegate?.didUpdateSettings()
        }
    }

    // Terminal Settings
    private var fontSize: Int {
        get { UserDefaults.standard.integer(forKey: "fontSize") != 0 ? UserDefaults.standard.integer(forKey: "fontSize") : 14 }
        set {
            UserDefaults.standard.set(newValue, forKey: "fontSize")
            delegate?.didUpdateSettings()
        }
    }

    private var colorTheme: TerminalColorTheme {
        get {
            let raw = UserDefaults.standard.string(forKey: "colorTheme") ?? TerminalColorTheme.dark.rawValue
            return TerminalColorTheme.allCases.first { $0.rawValue == raw } ?? .dark
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "colorTheme")
            delegate?.didUpdateSettings()
        }
    }

    // Cursor Settings
    private var cursorStyle: TerminalCursorStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: "cursorStyle") ?? TerminalCursorStyle.block.rawValue
            return TerminalCursorStyle.allCases.first { $0.rawValue == raw } ?? .block
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "cursorStyle")
            delegate?.didUpdateSettings()
        }
    }

    // Advanced Settings
    private var heartbeatInterval: Int {
        get { UserDefaults.standard.integer(forKey: "heartbeatInterval") != 0 ? UserDefaults.standard.integer(forKey: "heartbeatInterval") : 30 }
        set {
            UserDefaults.standard.set(newValue, forKey: "heartbeatInterval")
            delegate?.didUpdateSettings()
        }
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        title = L("settings.title")
        view.backgroundColor = .systemGroupedBackground

        setupTableView()
        setupNavigationBar()
    }

    // MARK: - Setup
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .singleLine

        // Register cell classes
        tableView.register(TextFieldCell.self, forCellReuseIdentifier: TextFieldCell.identifier)
        tableView.register(SwitchCell.self, forCellReuseIdentifier: SwitchCell.identifier)
        tableView.register(OptionCell.self, forCellReuseIdentifier: OptionCell.identifier)
        tableView.register(SliderCell.self, forCellReuseIdentifier: SliderCell.identifier)
        tableView.register(ButtonCell.self, forCellReuseIdentifier: ButtonCell.identifier)

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupNavigationBar() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )
    }

    // MARK: - Actions
    @objc private func doneTapped() {
        dismiss(animated: true)
    }

    // MARK: - Validation
    private func validateServerAddress(_ address: String) -> Bool {
        // 检查 ws:// 或 wss:// 前缀
        guard address.hasPrefix("ws://") || address.hasPrefix("wss://") else {
            return false
        }

        // 提取主机和端口部分
        let pattern = "^wss?://([^:]+)(?::(\\d+))?$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: address, range: NSRange(address.startIndex..., in: address)) else {
            return false
        }

        // 检查端口范围
        if let portRange = Range(match.range(at: 2), in: address),
           let port = Int(address[portRange]) {
            return (1...65535).contains(port)
        }

        return true
    }

    private func showInvalidAddressAlert() {
        let alert = UIAlertController(
            title: "无效的地址",
            message: "请输入有效的服务器地址，格式为 ws://host:port 或 wss://host:port，端口号范围为 1-65535",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func resetToDefaults() {
        let alert = UIAlertController(
            title: "恢复默认设置",
            message: "确定要将所有设置恢复为默认值吗？",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "恢复", style: .destructive) { [weak self] _ in
            self?.performReset()
        })

        present(alert, animated: true)
    }

    private func performReset() {
        // 清除所有自定义设置的 UserDefaults
        let defaults = [
            "serverAddress", "autoReconnect", "fontSize",
            "colorTheme", "cursorStyle", "heartbeatInterval"
        ]

        defaults.forEach { UserDefaults.standard.removeObject(forKey: $0) }

        // 刷新表格
        tableView.reloadData()

        delegate?.didUpdateSettings()

        // 显示确认提示
        let alert = UIAlertController(
            title: "已恢复",
            message: "所有设置已恢复为默认值",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension SettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return SettingSection.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = SettingSection(rawValue: section) else { return 0 }

        switch sectionType {
        case .account: return AccountRow.allCases.count
        case .language: return 1
        case .connection: return ConnectionRow.allCases.count
        case .terminal: return TerminalRow.allCases.count
        case .cursor: return CursorRow.allCases.count
        case .advanced: return AdvancedRow.allCases.count
        case .reset: return ResetRow.allCases.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sectionType = SettingSection(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch sectionType {
        case .account:
            return cellForAccountRow(row: AccountRow(rawValue: indexPath.row) ?? .username, tableView: tableView, indexPath: indexPath)

        case .language:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = L("settings.language")
            cell.detailTextLabel?.text = LanguageManager.shared.current.displayName
            cell.detailTextLabel?.textColor = .systemBlue
            cell.accessoryType = .disclosureIndicator
            return cell

        case .connection:
            return cellForConnectionRow(row: ConnectionRow(rawValue: indexPath.row) ?? .serverAddress, tableView: tableView, indexPath: indexPath)

        case .terminal:
            return cellForTerminalRow(row: TerminalRow(rawValue: indexPath.row) ?? .fontSize, tableView: tableView, indexPath: indexPath)

        case .cursor:
            return cellForCursorRow(row: CursorRow(rawValue: indexPath.row) ?? .style, tableView: tableView, indexPath: indexPath)

        case .advanced:
            return cellForAdvancedRow(row: AdvancedRow(rawValue: indexPath.row) ?? .heartbeatInterval, tableView: tableView, indexPath: indexPath)

        case .reset:
            return cellForResetRow(row: ResetRow(rawValue: indexPath.row) ?? .resetDefaults, tableView: tableView, indexPath: indexPath)
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return SettingSection(rawValue: section)?.title
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch SettingSection(rawValue: section) {
        case .account:
            return L("settings.accountFooter")
        case .connection:
            return "输入 WebSocket 服务器地址以建立连接"
        case .advanced:
            return "心跳间隔单位为秒，建议范围 10-60 秒"
        default:
            return nil
        }
    }

    // MARK: - Cell Factory Methods
    private func cellForConnectionRow(row: ConnectionRow, tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        switch row {
        case .serverAddress:
            let cell = tableView.dequeueReusableCell(withIdentifier: TextFieldCell.identifier, for: indexPath) as! TextFieldCell
            cell.configure(title: row.title, value: serverAddress, placeholder: "ws://192.168.1.100:8765")
            cell.onValueChange = { [weak self] newValue in
                guard let self = self else { return }

                if self.validateServerAddress(newValue) || newValue.isEmpty {
                    self.serverAddress = newValue
                } else {
                    self.showInvalidAddressAlert()
                    cell.updateValue(self.serverAddress)
                }
            }
            cell.keyboardType = .URL
            cell.autocapitalizationType = .none
            cell.autocorrectionType = .no
            return cell

        case .autoReconnect:
            let cell = tableView.dequeueReusableCell(withIdentifier: SwitchCell.identifier, for: indexPath) as! SwitchCell
            cell.configure(title: row.title, isOn: autoReconnect)
            cell.onValueChange = { [weak self] isOn in
                self?.autoReconnect = isOn
            }
            return cell
        }
    }

    private func cellForTerminalRow(row: TerminalRow, tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        switch row {
        case .fontSize:
            let cell = tableView.dequeueReusableCell(withIdentifier: SliderCell.identifier, for: indexPath) as! SliderCell
            cell.configure(title: row.title, value: fontSize, range: 10...24, unit: "pt")
            cell.onValueChange = { [weak self] newValue in
                self?.fontSize = newValue
            }
            return cell

        case .colorTheme:
            let cell = tableView.dequeueReusableCell(withIdentifier: OptionCell.identifier, for: indexPath) as! OptionCell
            let options = TerminalColorTheme.allCases.map { $0.rawValue }
            cell.configure(title: row.title, options: options, selectedIndex: TerminalColorTheme.allCases.firstIndex(of: colorTheme) ?? 0)
            cell.onValueChange = { [weak self] index in
                self?.colorTheme = TerminalColorTheme.allCases[index]
            }
            return cell
        }
    }

    private func cellForCursorRow(row: CursorRow, tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        switch row {
        case .style:
            let cell = tableView.dequeueReusableCell(withIdentifier: OptionCell.identifier, for: indexPath) as! OptionCell
            let options = TerminalCursorStyle.allCases.map { $0.rawValue }
            cell.configure(title: row.title, options: options, selectedIndex: TerminalCursorStyle.allCases.firstIndex(of: cursorStyle) ?? 0)
            cell.onValueChange = { [weak self] index in
                self?.cursorStyle = TerminalCursorStyle.allCases[index]
            }
            return cell
        }
    }

    private func cellForAdvancedRow(row: AdvancedRow, tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        switch row {
        case .heartbeatInterval:
            let cell = tableView.dequeueReusableCell(withIdentifier: SliderCell.identifier, for: indexPath) as! SliderCell
            cell.configure(title: row.title, value: heartbeatInterval, range: 10...120, unit: "秒", step: 5)
            cell.onValueChange = { [weak self] newValue in
                self?.heartbeatInterval = newValue
            }
            return cell
        }
    }

    private func cellForResetRow(row: ResetRow, tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        switch row {
        case .resetDefaults:
            let cell = tableView.dequeueReusableCell(withIdentifier: ButtonCell.identifier, for: indexPath) as! ButtonCell
            cell.configure(title: row.title, action: { [weak self] in
                self?.resetToDefaults()
            })
            return cell
        }
    }

    private func cellForAccountRow(row: AccountRow, tableView: UITableView, indexPath: IndexPath) -> UITableViewCell {
        let account = AccountManager.shared

        switch row {
        case .username:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            cell.textLabel?.text = row.title
            cell.detailTextLabel?.text = account.username ?? "—"
            cell.detailTextLabel?.textColor = .systemBlue
            cell.selectionStyle = .none
            return cell

        case .signOut:
            let cell = tableView.dequeueReusableCell(withIdentifier: ButtonCell.identifier, for: indexPath) as! ButtonCell
            cell.configure(title: row.title, action: { [weak self] in
                self?.signOut()
            })
            return cell
        }
    }

    private func showLanguagePicker() {
        let alert = UIAlertController(title: L("settings.languageTitle"), message: nil, preferredStyle: .actionSheet)

        for lang in LanguageManager.Language.allCases {
            let action = UIAlertAction(title: lang.displayName, style: .default) { [weak self] _ in
                LanguageManager.shared.current = lang
                // Reload entire settings to reflect new language
                self?.tableView.reloadData()
                self?.title = L("settings.title")
            }
            if lang == LanguageManager.shared.current {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: L("common.cancel"), style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }

    private func signOut() {
        let alert = UIAlertController(title: "退出登录", message: "确定要退出当前账号吗？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "退出", style: .destructive) { _ in
            AccountManager.shared.signOut()
            // Navigate back to login
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let sceneDelegate = scene.delegate as? SceneDelegate {
                sceneDelegate.showLogin()
            }
        })
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDelegate
extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if SettingSection(rawValue: indexPath.section) == .language {
            showLanguagePicker()
        }
    }
}

// MARK: - Custom Cell Classes

// MARK: - TextField Cell
class TextFieldCell: UITableViewCell {

    static let identifier = "TextFieldCell"

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let textField: UITextField = {
        let field = UITextField()
        field.font = UIFont.systemFont(ofSize: 17)
        field.textAlignment = .right
        field.textColor = .systemBlue
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    var onValueChange: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCell() {
        contentView.addSubview(titleLabel)
        contentView.addSubview(textField)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            textField.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textField.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
    }

    func configure(title: String, value: String, placeholder: String) {
        titleLabel.text = title
        textField.text = value
        textField.placeholder = placeholder
    }

    func updateValue(_ value: String) {
        textField.text = value
    }

    var keyboardType: UIKeyboardType {
        get { textField.keyboardType }
        set { textField.keyboardType = newValue }
    }

    var autocapitalizationType: UITextAutocapitalizationType {
        get { textField.autocapitalizationType }
        set { textField.autocapitalizationType = newValue }
    }

    var autocorrectionType: UITextAutocorrectionType {
        get { textField.autocorrectionType }
        set { textField.autocorrectionType = newValue }
    }

    @objc private func textFieldDidChange() {
        onValueChange?(textField.text ?? "")
    }
}

// MARK: - Switch Cell
class SwitchCell: UITableViewCell {

    static let identifier = "SwitchCell"

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let toggleSwitch: UISwitch = {
        let `switch` = UISwitch()
        `switch`.translatesAutoresizingMaskIntoConstraints = false
        return `switch`
    }()

    var onValueChange: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCell() {
        contentView.addSubview(titleLabel)
        contentView.addSubview(toggleSwitch)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            toggleSwitch.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            toggleSwitch.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        toggleSwitch.addTarget(self, action: #selector(switchDidChange), for: .valueChanged)
    }

    func configure(title: String, isOn: Bool) {
        titleLabel.text = title
        toggleSwitch.isOn = isOn
    }

    @objc private func switchDidChange() {
        onValueChange?(toggleSwitch.isOn)
    }
}

// MARK: - Option Cell
class OptionCell: UITableViewCell {

    static let identifier = "OptionCell"

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let valueLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17)
        label.textColor = .systemBlue
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private var options: [String] = []
    private var selectedIndex: Int = 0
    var onValueChange: ((Int) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCell() {
        contentView.addSubview(titleLabel)
        contentView.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 16),
            valueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            valueLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    func configure(title: String, options: [String], selectedIndex: Int) {
        titleLabel.text = title
        self.options = options
        self.selectedIndex = selectedIndex
        valueLabel.text = options[selectedIndex]
    }

    func tap() {
        guard !options.isEmpty else { return }

        let alert = UIAlertController(title: titleLabel.text, message: nil, preferredStyle: .actionSheet)

        for (index, option) in options.enumerated() {
            let action = UIAlertAction(title: option, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.selectedIndex = index
                self.valueLabel.text = option
                self.onValueChange?(index)
            }
            if index == selectedIndex {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "取消", style: .cancel))

        // iPad support
        if let popover = alert.popoverPresentationController {
            popover.sourceView = contentView
            popover.sourceRect = contentView.bounds
        }

        window?.rootViewController?.present(alert, animated: true)
    }
}

// MARK: - Slider Cell
class SliderCell: UITableViewCell {

    static let identifier = "SliderCell"

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let valueLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        label.textColor = .systemBlue
        label.textAlignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let slider: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        return slider
    }()

    private var range: ClosedRange<Int> = 0...100
    private var step: Int = 1
    var onValueChange: ((Int) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCell() {
        contentView.addSubview(titleLabel)
        contentView.addSubview(valueLabel)
        contentView.addSubview(slider)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -8),

            valueLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),

            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            slider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            slider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            slider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])

        slider.addTarget(self, action: #selector(sliderDidChange), for: .valueChanged)
    }

    func configure(title: String, value: Int, range: ClosedRange<Int>, unit: String, step: Int = 1) {
        titleLabel.text = title
        self.range = range
        self.step = step
        valueLabel.text = "\(value) \(unit)"

        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.value = Float(value)
    }

    @objc private func sliderDidChange() {
        // 应用步进
        let steppedValue = Int(round(Float(step) * round(Float(slider.value) / Float(step))))
        let clampedValue = max(range.lowerBound, min(range.upperBound, steppedValue))

        valueLabel.text = formatValue(clampedValue)
        onValueChange?(clampedValue)
    }

    private func formatValue(_ value: Int) -> String {
        // 从当前文本中提取单位
        if let currentText = valueLabel.text,
           let unit = currentText.components(separatedBy: " ").last {
            return "\(value) \(unit)"
        }
        return "\(value)"
    }
}

// MARK: - Button Cell
class ButtonCell: UITableViewCell {

    static let identifier = "ButtonCell"

    private let actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitleColor(.systemRed, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17)
        button.contentHorizontalAlignment = .center
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCell() {
        contentView.addSubview(actionButton)

        NSLayoutConstraint.activate([
            actionButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            actionButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            actionButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
        ])

        actionButton.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
    }

    func configure(title: String, action: @escaping () -> Void) {
        actionButton.setTitle(title, for: .normal)
        self.action = action
    }

    private var action: (() -> Void)?

    @objc private func buttonTapped() {
        action?()
    }
}
