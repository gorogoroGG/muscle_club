import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: GymStore
    @State private var draft = ""
    @State private var isSending = false
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 16) {
                ScreenTitleView(
                    eyebrow: "CHAT",
                    title: "チャット",
                    subtitle: "全体に届くメッセージを送れます。@でメンションもできます。"
                )

                CardView(title: "GUIDE") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("・メッセージは全員に配信されます。")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                        Text("・@名前 でメンションできます。")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                    }
                }

                messageList
                    .frame(maxHeight: .infinity)

                composer
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .background(AppBackground())
        .onAppear {
            isComposerFocused = true
        }
    }

    private var messageList: some View {
        CardView(title: "MESSAGES") {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        if store.chatMessages.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "message.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(AppPalette.accentSecondary)
                                Text("まだメッセージはありません")
                                    .font(.headline)
                                    .foregroundStyle(AppPalette.textPrimary)
                                Text("最初の一言を送って、全体チャットを始めましょう。")
                                    .font(.subheadline)
                                    .foregroundStyle(AppPalette.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                        } else {
                            ForEach(store.chatMessages) { message in
                                ChatMessageRow(
                                    message: message,
                                    sender: sender(for: message),
                                    mentionedMembers: mentionedMembers(for: message),
                                    isCurrentUser: message.senderMemberID == store.currentUser.id
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    scrollToLatest(proxy)
                }
                .onChange(of: store.chatMessages.count) { _, _ in
                    scrollToLatest(proxy)
                }
            }
        }
    }

    private var composer: some View {
        CardView(title: "NEW MESSAGE") {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppPalette.surfaceStrong)
                        .frame(minHeight: 112)

                    if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("メッセージを入力")
                            .font(.subheadline)
                            .foregroundStyle(AppPalette.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }

                    TextEditor(text: $draft)
                        .focused($isComposerFocused)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(minHeight: 112, maxHeight: 144)
                        .foregroundStyle(AppPalette.textPrimary)
                }

                if let query = mentionQuery {
                    let suggestions = mentionSuggestions(for: query)
                    if !suggestions.isEmpty {
                        MentionSuggestionStrip(
                            title: query.isEmpty ? "メンション候補" : "候補",
                            members: suggestions
                        ) { member in
                            insertMention(member)
                            isComposerFocused = true
                        }
                    }
                }

                HStack {
                    Text("送信先は全員です。@で名前を入れるとメンションできます。")
                        .font(.caption)
                        .foregroundStyle(AppPalette.textSecondary)

                    Spacer()

                    Button {
                        Task {
                            guard !isSending else { return }
                            let messageText = draft
                            isSending = true
                            defer { isSending = false }

                            if await store.sendChatMessage(messageText) {
                                draft = ""
                                isComposerFocused = true
                            }
                        }
                    } label: {
                        Text(isSending ? "送信中" : "送信")
                    }
                    .buttonStyle(PrimaryActionButtonStyle(tint: AppPalette.accentSecondary))
                    .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .frame(width: 108)
                }

                if let error = store.lastErrorMessage, !error.isEmpty {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(AppPalette.danger)
                }
            }
        }
    }

    private var mentionQuery: String? {
        guard let atIndex = draft.lastIndex(of: "@") else { return nil }
        let query = String(draft[draft.index(after: atIndex)...])
        guard !query.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        return query
    }

    private func mentionSuggestions(for query: String) -> [Member] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.allMembers
            .filter { $0.id != store.currentUser.id }
            .filter { member in
                guard !trimmed.isEmpty else { return true }
                return member.name.localizedCaseInsensitiveContains(trimmed)
            }
            .prefix(5)
            .map { $0 }
    }

    private func insertMention(_ member: Member) {
        guard let atIndex = draft.lastIndex(of: "@") else {
            draft.append("@\(member.name) ")
            return
        }
        let prefix = draft[..<atIndex]
        draft = String(prefix) + "@\(member.name) "
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let lastID = store.chatMessages.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    private func sender(for message: ChatMessage) -> Member {
        store.members.first(where: { $0.id == message.senderMemberID }) ?? store.currentUser
    }

    private func mentionedMembers(for message: ChatMessage) -> [Member] {
        let mentionedIDs = Set(message.mentionedMemberIDs)
        return store.allMembers.filter { mentionedIDs.contains($0.id) }
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage
    let sender: Member
    let mentionedMembers: [Member]
    let isCurrentUser: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !isCurrentUser {
                AvatarView(member: sender, size: 38)
            } else {
                Spacer(minLength: 24)
            }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(isCurrentUser ? "あなた" : sender.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppPalette.textPrimary)

                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(AppPalette.textSecondary)
                }

                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.textPrimary)
                    .textSelection(.enabled)

                if !mentionedMembers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(mentionedMembers) { member in
                                AppBadgeView(text: "@\(member.name)", tint: AppPalette.accentSecondary)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isCurrentUser ? AppPalette.accentSecondary.opacity(0.14) : AppPalette.surfaceStrong)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isCurrentUser ? AppPalette.accentSecondary.opacity(0.24) : AppPalette.stroke, lineWidth: 1)
            )

            if isCurrentUser {
                AvatarView(member: sender, size: 38)
            } else {
                Spacer(minLength: 24)
            }
        }
    }
}

private struct MentionSuggestionStrip: View {
    let title: String
    let members: [Member]
    let onSelect: (Member) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(members) { member in
                        Button {
                            onSelect(member)
                        } label: {
                            HStack(spacing: 8) {
                                AvatarView(member: member, size: 28)
                                Text("@\(member.name)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppPalette.textPrimary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(AppPalette.surfaceStrong)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(AppPalette.stroke, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
