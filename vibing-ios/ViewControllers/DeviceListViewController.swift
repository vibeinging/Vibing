//
//  DeviceListViewController.swift
//  Vibing (iOS)
//
//  登录后主页 — 设备列表，Apple Home 风格
//

import UIKit

class DeviceListViewController: UIViewController {

    private let account = AccountManager.shared

    private let collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { section, env in
            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(80))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            let group = NSCollectionLayoutGroup.vertical(layoutSize: itemSize, subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 1
            section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 20, bottom: 20, trailing: 20)

            // Section header
            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44))
            let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize, elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
            section.boundarySupplementaryItems = [header]

            // Round the section
            let bg = NSCollectionLayoutDecorationItem.background(elementKind: "sectionBg")
            bg.contentInsets = NSDirectionalEdgeInsets(top: 44, leading: 20, bottom: 0, trailing: 20)
            section.decorationItems = [bg]

            return section
        }
        layout.register(SectionBackgroundView.self, forDecorationViewOfKind: "sectionBg")

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.alwaysBounceVertical = true
        cv.translatesAutoresizingMaskIntoConstraints = false
        return cv
    }()

    private let refreshControl = UIRefreshControl()

    private let emptyView: UIView = {
        let v = UIView()
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("devices.title")
        view.backgroundColor = VibingColor.pageBg
        navigationController?.navigationBar.prefersLargeTitles = true
        setupNav()
        setupCollectionView()
        setupEmpty()
        loadDevices()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadDevices()
    }

    // MARK: - Setup

    private func setupNav() {
        let settingsBtn = UIBarButtonItem(
            image: UIImage(systemName: "person.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)),
            style: .plain,
            target: self,
            action: #selector(settingsTapped)
        )
        settingsBtn.tintColor = VibingColor.accent
        navigationItem.rightBarButtonItem = settingsBtn

        // 左侧留空，不需要手动连接入口
    }

    private func setupCollectionView() {
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(DeviceCell.self, forCellWithReuseIdentifier: DeviceCell.id)
        collectionView.register(SectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: SectionHeaderView.id)

        refreshControl.tintColor = VibingColor.accent
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        collectionView.refreshControl = refreshControl

        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupEmpty() {
        let icon = UIImageView(image: UIImage(systemName: "desktopcomputer.trianglebadge.exclamationmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .thin)))
        icon.tintColor = .tertiaryLabel
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = L("devices.noDevices")
        title.font = VibingFont.title3()
        title.textColor = .secondaryLabel
        title.textAlignment = .center

        let sub = UILabel()
        sub.text = L("devices.noDevicesHint")
        sub.font = VibingFont.subheadline()
        sub.textColor = .tertiaryLabel
        sub.textAlignment = .center
        sub.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, title, sub])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        emptyView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: emptyView.leadingAnchor, constant: 40),
        ])

        view.addSubview(emptyView)
        NSLayoutConstraint.activate([
            emptyView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            emptyView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Data

    private func loadDevices() {
        Task {
            try? await account.fetchDevices()
            await MainActor.run {
                refreshControl.endRefreshing()
                emptyView.isHidden = !account.devices.isEmpty
                collectionView.reloadData()
            }
        }
    }

    @objc private func refresh() { loadDevices() }

    @objc private func settingsTapped() {
        let settingsVC = SettingsViewController()
        let nav = UINavigationController(rootViewController: settingsVC)
        present(nav, animated: true)
    }

    private func showNoSessionAlert() {
        let alert = UIAlertController(title: nil, message: L("devices.noDevicesHint"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("common.ok"), style: .default))
        present(alert, animated: true)
    }

    private func connectToDevice(relayURL: String, sessionCode: String) {
        let vc = TerminalViewerController(serverURL: relayURL, sessionCode: sessionCode)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func connectToOnlineDevice(_ device: DeviceInfo) {
        // DEBUG: mock 模式直接连接
        if account.authToken == "mock_token" {
            connectToDevice(relayURL: "ws://mock", sessionCode: "mock")
            return
        }

        Task {
            do {
                let sessions = try await account.fetchRelaySessions()
                let matching = sessions.filter { $0.device_id == device.id && $0.role == "host" }

                await MainActor.run {
                    if let session = matching.first {
                        let relayURL = (UserDefaults.standard.string(forKey: "relayServerURL") ?? "http://127.0.0.1:8766")
                            .replacingOccurrences(of: "http://", with: "ws://")
                            .replacingOccurrences(of: "https://", with: "wss://")
                        self.connectToDevice(relayURL: relayURL, sessionCode: session.session_id)
                    } else {
                        self.showNoSessionAlert()
                    }
                }
            } catch {
                await MainActor.run {
                    self.showNoSessionAlert()
                }
            }
        }
    }
}

// MARK: - Collection View

extension DeviceListViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        account.devices.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DeviceCell.id, for: indexPath) as! DeviceCell
        let device = account.devices[indexPath.row]
        let isLast = indexPath.row == account.devices.count - 1
        cell.configure(device: device, isFirst: indexPath.row == 0, isLast: isLast)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: SectionHeaderView.id, for: indexPath) as! SectionHeaderView
        header.label.text = L("devices.yourDevices")
        return header
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let device = account.devices[indexPath.row]
        guard device.is_online else { return }
        connectToOnlineDevice(device)
    }
}

// MARK: - Device Cell

class DeviceCell: UICollectionViewCell {
    static let id = "DeviceCell"

    private let iconContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 12
        v.layer.cornerCurve = .continuous
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = VibingFont.headline()
        l.textColor = .label
        return l
    }()
    private let statusLabel: UILabel = {
        let l = UILabel()
        l.font = VibingFont.footnote()
        return l
    }()
    private let statusDot: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 4
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 8).isActive = true
        v.heightAnchor.constraint(equalToConstant: 8).isActive = true
        return v
    }()
    private let chevron: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)))
        iv.tintColor = .tertiaryLabel
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let divider: UIView = {
        let v = UIView()
        v.backgroundColor = VibingColor.separator
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildLayout() {
        backgroundColor = VibingColor.cardBg

        iconContainer.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
        ])

        let statusStack = UIStackView(arrangedSubviews: [statusDot, statusLabel])
        statusStack.axis = .horizontal
        statusStack.spacing = 5
        statusStack.alignment = .center

        let textStack = UIStackView(arrangedSubviews: [nameLabel, statusStack])
        textStack.axis = .vertical
        textStack.spacing = 2

        let mainStack = UIStackView(arrangedSubviews: [iconContainer, textStack, chevron])
        mainStack.axis = .horizontal
        mainStack.spacing = 14
        mainStack.alignment = .center
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(mainStack)
        contentView.addSubview(divider)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 44),
            iconContainer.heightAnchor.constraint(equalToConstant: 44),

            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),

            divider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 74),
            divider.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    func configure(device: DeviceInfo, isFirst: Bool, isLast: Bool) {
        nameLabel.text = device.name
        statusDot.backgroundColor = device.is_online ? VibingColor.online : .tertiaryLabel
        statusLabel.text = device.is_online ? L("devices.online") : L("devices.offline")
        statusLabel.textColor = device.is_online ? VibingColor.online : .tertiaryLabel
        chevron.isHidden = !device.is_online

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        iconView.image = UIImage(systemName: device.typeIcon, withConfiguration: symbolConfig)

        if device.is_online {
            iconContainer.backgroundColor = VibingColor.accentSubtle
            iconView.tintColor = VibingColor.accent
        } else {
            iconContainer.backgroundColor = UIColor.tertiarySystemFill
            iconView.tintColor = .tertiaryLabel
        }

        divider.isHidden = isLast

        // Corner masking for first/last cell in group
        layer.cornerRadius = 0
        layer.maskedCorners = []
        if isFirst && isLast {
            layer.cornerRadius = 12
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        } else if isFirst {
            layer.cornerRadius = 12
            layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        } else if isLast {
            layer.cornerRadius = 12
            layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        layer.cornerCurve = .continuous
        clipsToBounds = true
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.contentView.alpha = self.isHighlighted ? 0.6 : 1
            }
        }
    }
}

// MARK: - Section Header

class SectionHeaderView: UICollectionReusableView {
    static let id = "SectionHeader"
    let label: UILabel = {
        let l = UILabel()
        l.font = VibingFont.caption()
        l.textColor = .secondaryLabel
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Section Background

class SectionBackgroundView: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = VibingColor.cardBg
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
    }
    required init?(coder: NSCoder) { fatalError() }
}
