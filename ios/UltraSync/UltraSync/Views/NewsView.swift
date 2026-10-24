import SwiftUI

/// NEWS panel: source-filter chips, headline search, unread dots, and
/// an in-app reader — the native counterpart of the GUI news panel.
struct NewsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeManager: ThemeManager
    @State private var sourceFilter: String? = nil
    @State private var searchText = ""
    @State private var selected: NewsArticle? = nil

    var body: some View {
        let theme = themeManager.theme
        NavigationStack {
            ZStack {
                theme.bgColor.ignoresSafeArea()
                PanelStateView(state: store.newsState,
                               retry: { Task { await store.refreshNews() } }) { resp in
                    VStack(spacing: 0) {
                        filterBar(sources: resp.sources, theme: theme)
                        articleList(resp.articles, theme: theme)
                    }
                }
            }
            .navigationTitle("ULTRASYNC · NEWS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refreshNewsFromServer() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .tint(theme.primaryColor)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Mark all read") { store.markAllRead() }
                        .font(Retro.font(11, weight: .bold))
                        .tint(theme.accent1Color)
                }
            }
            .searchable(text: $searchText, prompt: "Search headlines")
            .refreshable { await store.refreshNews() }
            .sheet(item: $selected) { article in
                ArticleReaderView(article: article)
            }
        }
        .task { if store.newsState.value == nil { await store.refreshNews() } }
    }

    private func filterBar(sources: [String], theme: ThemePalette) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "ALL", active: sourceFilter == nil, theme: theme) {
                    sourceFilter = nil
                }
                ForEach(sources, id: \.self) { source in
                    chip(label: source, active: sourceFilter == source, theme: theme) {
                        sourceFilter = sourceFilter == source ? nil : source
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func chip(label: String, active: Bool, theme: ThemePalette,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Retro.font(11, weight: .bold))
                .foregroundColor(active ? theme.bgColor : theme.primaryColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(active ? theme.primaryColor : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(theme.primaryColor.opacity(0.7), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func articleList(_ articles: [NewsArticle], theme: ThemePalette) -> some View {
        let filtered = articles.filter { a in
            (sourceFilter == nil || a.source == sourceFilter) &&
            (searchText.isEmpty ||
             a.headline.localizedCaseInsensitiveContains(searchText) ||
             a.summary.localizedCaseInsensitiveContains(searchText))
        }
        return List {
            if filtered.isEmpty {
                Text("No articles match.")
                    .font(Retro.font(Retro.bodySize))
                    .foregroundColor(theme.dimColor)
                    .listRowBackground(Color.clear)
            }
            ForEach(filtered) { article in
                Button {
                    store.markRead(article)
                    selected = article
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(article.source.uppercased())
                                .font(Retro.font(9, weight: .bold))
                                .foregroundColor(theme.accent2Color)
                            Text(article.headline)
                                .font(Retro.font(Retro.bodySize,
                                                 weight: article.isUnread ? .bold : .regular))
                                .foregroundColor(theme.primaryColor)
                                .multilineTextAlignment(.leading)
                            if !article.summary.isEmpty {
                                Text(article.summary)
                                    .font(Retro.font(Retro.smallSize))
                                    .foregroundColor(theme.primaryColor.opacity(0.65))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer()
                        if article.isUnread {
                            Circle()
                                .fill(theme.accent1Color)
                                .frame(width: 8, height: 8)
                                .padding(.top, 5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(theme.panelColor)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

/// In-app article reader. Backend mode fetches the server's cleaned
/// paragraphs (GET /api/news/article); standalone mode presents the
/// feed summary plus the original link.
struct ArticleReaderView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    let article: NewsArticle
    @State private var paragraphs: [String]? = nil
    @State private var loading = false

    var body: some View {
        let theme = themeManager.theme
        NavigationStack {
            ZStack {
                theme.bgColor.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(article.source.uppercased())
                            .font(Retro.font(10, weight: .bold))
                            .foregroundColor(theme.accent2Color)
                        Text(article.headline)
                            .font(Retro.font(18, weight: .bold))
                            .foregroundColor(theme.primaryColor)
                            .phosphorGlow(theme, radius: 4)
                        Divider().background(theme.dimColor)
                        if loading {
                            ProgressView().tint(theme.primaryColor)
                        } else if let paragraphs, !paragraphs.isEmpty {
                            ForEach(paragraphs, id: \.self) { p in
                                Text(p)
                                    .font(Retro.font(Retro.bodySize))
                                    .foregroundColor(theme.primaryColor.opacity(0.9))
                            }
                        } else if !article.summary.isEmpty {
                            Text(article.summary)
                                .font(Retro.font(Retro.bodySize))
                                .foregroundColor(theme.primaryColor.opacity(0.9))
                        }
                        if let url = article.url {
                            Link(destination: url) {
                                Text("OPEN ORIGINAL ↗")
                                    .font(Retro.font(12, weight: .bold))
                                    .foregroundColor(theme.accent1Color)
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(theme.primaryColor)
                }
            }
        }
        .task {
            guard store.mode == .backend, let base = store.backendBaseURL else { return }
            loading = true
            defer { loading = false }
            if let text = try? await store.client.backendArticle(base: base, link: article.link) {
                paragraphs = text.paragraphs
            }
        }
    }
}
