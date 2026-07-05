//
//  OpenAPPViewController+TableView.swift
//  OpenAPPUI
//

#if canImport(UIKit)
import UIKit

// MARK: - Table View

extension OpenAPPViewController {
    func setupTableView() {
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.keyboardDismissMode = .interactive
        tableView.backgroundColor = OpenAPPAppearance.overlayBackground
        tableView.isHidden = true
        tableView.register(ChatMessageCell.self, forCellReuseIdentifier: ChatMessageCell.reuseIdentifier)
        view.addSubview(tableView)
    }

    func scrollToBottom(animated: Bool) {
        guard !chatMessages.isEmpty else { return }
        let indexPath = IndexPath(row: chatMessages.count - 1, section: 0)
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }
}

// MARK: - UITableViewDataSource

extension OpenAPPViewController: UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        chatMessages.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ChatMessageCell.reuseIdentifier, for: indexPath) as! ChatMessageCell
        cell.configure(with: chatMessages[indexPath.row])
        return cell
    }
}

#endif
