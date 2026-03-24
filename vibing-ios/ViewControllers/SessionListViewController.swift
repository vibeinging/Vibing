//
//  SessionListViewController.swift
//  Vibing (iOS)
//
//  连接到设备后，显示所有终端 Tab/Session
//

import UIKit

struct SessionInfo {
    let id: String
    let isActive: Bool
}

class SessionListViewController: UIViewController {

    private let serverURL: String
    private let sessionCode: String
    private(set) var wsClient: WebSocketClient?
    private var sessions: [SessionInfo] = []
    private var refreshTimer: Timer?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let statusLabel: UILabel = {
        let l = UILabel()
        l.text = L("sessions.connecting")
        l.textAlignment = .center
        l.textColor = .secondaryLabel
        l.font = .systemFont(ofSize: 15)
        return l
    }()
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(serverURL: String, sessionCode: String) {
        self.serverURL = serverURL
        self.sessionCode = sessionCode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("sessions.title")
        view.backgroundColor = .systemGroupedBackground
        setupUI()
        connect()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent {
            disconnect()
        }
    }

    // MARK: - Setup

    private func setupUI() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.clockwise"),
            style: .plain,
            target: self,
            action: #selector(refreshSessions)
        )

        let headerStack = UIStackView(arrangedSubviews: [spinner, statusLabel])
        headerStack.axis = .horizontal
        headerStack.spacing = 8
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerStack)
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            headerStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SessionCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        spinner.startAnimating()
    }

    // MARK: - WebSocket

    private func connect() {
        // DEBUG: 用假数据替代真实连接
        if sessionCode == "mock" {
            injectMockSessions()
            return
        }

        let client = WebSocketClient(serverURL: serverURL)
        self.wsClient = client

        client.onTextMessage = { [weak self] text in
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { return }

            if type == "session_list" {
                self?.handleSessionList(json)
            }
        }

        client.delegate = self
        client.connect()
    }

    private func injectMockSessions() {
        sessions = [
            SessionInfo(id: "sess_a1b2c3d4", isActive: true),
            SessionInfo(id: "sess_e5f6g7h8", isActive: true),
            SessionInfo(id: "sess_i9j0k1l2", isActive: true),
        ]
        spinner.stopAnimating()
        statusLabel.text = String(format: L("sessions.connectedCount"), sessions.count)
        statusLabel.textColor = .systemGreen
        tableView.reloadData()
    }

    private func disconnect() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        wsClient?.disconnect()
        wsClient = nil
    }

    @objc private func refreshSessions() {
        requestSessionList()
    }

    private func requestSessionList() {
        wsClient?.sendTextMessage(["type": "list_sessions"])
    }

    private func handleSessionList(_ data: [String: Any]) {
        guard let sessionsArray = data["sessions"] as? [[String: Any]] else { return }
        sessions = sessionsArray.compactMap { dict in
            guard let id = dict["id"] as? String else { return nil }
            let isActive = dict["is_active"] as? Bool ?? true
            return SessionInfo(id: id, isActive: isActive)
        }

        DispatchQueue.main.async {
            self.spinner.stopAnimating()
            self.statusLabel.text = String(format: L("sessions.connectedCount"), self.sessions.count)
            self.statusLabel.textColor = .systemGreen
            self.tableView.reloadData()
        }
    }
}

// MARK: - WebSocketClientDelegate

extension SessionListViewController: WebSocketClientDelegate {

    func webSocketDidConnect(_ client: WebSocketClient) {
        DispatchQueue.main.async {
            self.statusLabel.text = L("sessions.connected")
            self.statusLabel.textColor = .systemGreen
            self.spinner.stopAnimating()
        }
        requestSessionList()

        DispatchQueue.main.async {
            self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                self?.requestSessionList()
            }
        }
    }

    func webSocketDidDisconnect(_ client: WebSocketClient, error: Error?) {
        DispatchQueue.main.async {
            self.spinner.stopAnimating()
            self.statusLabel.text = L("sessions.disconnected")
            self.statusLabel.textColor = .systemRed
            self.refreshTimer?.invalidate()
        }
    }

    func webSocket(_ client: WebSocketClient, didReceiveFrame frame: Frame) {
        // Binary frames handled in SessionDetailVC
    }

    func webSocket(_ client: WebSocketClient, didReceiveError error: Error) {
        // Error handling
    }
}

// MARK: - UITableViewDataSource & Delegate

extension SessionListViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sessions.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        L("sessions.terminalSessions")
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SessionCell", for: indexPath)
        let session = sessions[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = String(format: L("sessions.sessionNumber"), indexPath.row + 1)
        config.secondaryText = session.id
        config.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        config.secondaryTextProperties.color = .tertiaryLabel
        config.image = UIImage(systemName: "terminal")
        config.imageProperties.tintColor = session.isActive ? .systemGreen : .tertiaryLabel
        cell.contentConfiguration = config
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let session = sessions[indexPath.row]
        let detailVC = SessionDetailViewController(
            sessionId: session.id,
            wsClient: wsClient
        )
        navigationController?.pushViewController(detailVC, animated: true)
    }
}
