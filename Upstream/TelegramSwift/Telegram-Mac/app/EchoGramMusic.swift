import AppKit
import SwiftUI
import WebKit

struct EchoGramMusicSidebarTab: Identifiable {
    let id: String
    let icon: CGImage
    let iconScale: CGFloat
    let title: String
    let selected: Bool
    let action: () -> Void
}

struct EchoGramMusicSidebarColors {
    let background: Color
    let foreground: Color
    let selectedForeground: Color
    let border: Color
    let hover: Color
    let selectedBackground: Color
    let selectedText: Color

    init(background: NSColor, foreground: NSColor, selectedForeground: NSColor, border: NSColor, hover: NSColor = .quaternaryLabelColor, selectedBackground: NSColor? = nil, selectedText: NSColor? = nil) {
        self.background = Color(nsColor: background)
        self.foreground = Color(nsColor: foreground)
        self.selectedForeground = Color(nsColor: selectedForeground)
        self.border = Color(nsColor: border)
        self.hover = Color(nsColor: hover)
        self.selectedBackground = Color(nsColor: selectedBackground ?? hover)
        self.selectedText = Color(nsColor: selectedText ?? foreground)
    }
}

private enum MusicProvider: String, CaseIterable, Identifiable {
    case soundCloud, spotify, yandexMusic

    var id: Self { self }
    var title: String {
        switch self {
        case .soundCloud: "SoundCloud"
        case .spotify: "Spotify"
        case .yandexMusic: "Яндекс Музыка"
        }
    }
    var iconAsset: String {
        switch self {
        case .soundCloud: "EchoGramSoundCloud"
        case .spotify: "EchoGramSpotify"
        case .yandexMusic: "EchoGramYandexMusic"
        }
    }
    var libraryURL: URL {
        switch self {
        case .soundCloud: URL(string: "https://soundcloud.com/you/library")!
        case .spotify: URL(string: "https://open.spotify.com/collection")!
        case .yandexMusic: URL(string: "https://music.yandex.ru/collection")!
        }
    }
    var signInURL: URL {
        switch self {
        case .soundCloud: URL(string: "https://soundcloud.com/signin")!
        case .spotify: loginURL("https://accounts.spotify.com/en/login", redirectParameter: "continue")
        case .yandexMusic: loginURL("https://passport.yandex.ru/auth", redirectParameter: "retpath")
        }
    }
    var profileID: UUID {
        switch self {
        case .soundCloud: UUID(uuidString: "689FDB99-8FE7-4BD8-84DF-4C8567580008")!
        case .spotify: UUID(uuidString: "BCE4415A-5A36-4451-AB1A-71415E4F2F85")!
        case .yandexMusic: UUID(uuidString: "B57C4A06-40A8-45F3-94D4-8E3B3BCE2030")!
        }
    }
    var minimumWebsiteWidth: CGFloat {
        switch self {
        case .soundCloud: 960
        case .spotify: 1120
        case .yandexMusic: 0
        }
    }

    func allows(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        switch self {
        case .soundCloud:
            return host == "soundcloud.com" || host.hasSuffix(".soundcloud.com")
                || ["appleid.apple.com", "www.facebook.com", "m.facebook.com"].contains(host)
        case .spotify:
            return host == "spotify.com" || host.hasSuffix(".spotify.com") || host == "appleid.apple.com"
        case .yandexMusic:
            return ["music.yandex.ru", "music.yandex.by", "music.yandex.com",
                    "passport.yandex.ru", "passport.yandex.by", "passport.yandex.com", "id.yandex.ru",
                    "id.yandex.com", "ya.ru", "passport.ya.ru", "id.ya.ru"].contains(host)
        }
    }

    private func loginURL(_ base: String, redirectParameter: String) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = [URLQueryItem(name: redirectParameter, value: libraryURL.absoluteString)]
        return components.url!
    }
}

@MainActor
private final class MusicWorkspace: ObservableObject {
    @Published private(set) var session: MusicWebSession
    @Published private(set) var isStreamerMode = false
    private var sessions: [MusicProvider: MusicWebSession]
    private var appearance: NSAppearance?
    var onSessionChanged: ((MusicWebSession) -> Void)?

    init() {
        let session = MusicWebSession(provider: .soundCloud)
        self.session = session
        self.sessions = [.soundCloud: session]
    }

    func select(_ provider: MusicProvider) {
        guard !isStreamerMode else { return }
        guard session.provider != provider else { return }
        session.deactivate()
        let next = sessions[provider] ?? MusicWebSession(provider: provider)
        sessions[provider] = next
        next.webView.appearance = appearance
        next.activate()
        next.start()
        session = next
        onSessionChanged?(next)
    }

    func setStreamerMode(_ active: Bool) {
        guard isStreamerMode != active else { return }
        isStreamerMode = active
        session.setStreamerMode(active)
    }

    func setAppearance(_ appearance: NSAppearance?) {
        self.appearance = appearance
        for session in sessions.values {
            session.webView.appearance = appearance
        }
    }
}

@MainActor
final class EchoGramMusicSurface {
    nonisolated static let minimumSidebarWidth: CGFloat = 88
    nonisolated static let labeledSidebarWidth: CGFloat = 248

    private let workspace: MusicWorkspace
    private let page: NSHostingView<EchoGramMusicPane>
    private let sidebar: NSHostingView<EchoGramMusicSidebar>
    private var bottom: NSLayoutConstraint?

    init() {
        let workspace = MusicWorkspace()
        self.workspace = workspace
        self.page = NSHostingView(rootView: EchoGramMusicPane(workspace: workspace, session: workspace.session, showToolbar: false))
        self.sidebar = NSHostingView(rootView: EchoGramMusicSidebar(
            workspace: workspace, selectedProvider: workspace.session.provider, tabs: [], bottomInset: 0,
            colors: .init(background: .windowBackgroundColor, foreground: .labelColor, selectedForeground: .labelColor, border: .separatorColor)
        ))
        page.sizingOptions = []
        page.wantsLayer = true
        page.layer?.cornerCurve = .continuous
        page.layer?.masksToBounds = true
        sidebar.sizingOptions = []
        workspace.onSessionChanged = { [weak self] session in
            guard let self else { return }
            page.rootView = EchoGramMusicPane(workspace: self.workspace, session: session, showToolbar: page.rootView.showToolbar)
            let currentSidebar = sidebar.rootView
            updateSidebar(tabs: currentSidebar.tabs, bottomInset: currentSidebar.bottomInset, colors: currentSidebar.colors)
        }
    }

    func attach(to tab: NSView, besideTabIn detail: NSView?, bottomInset: CGFloat) {
        let target = detail ?? tab
        let showToolbar = detail == nil
        if page.rootView.showToolbar != showToolbar {
            page.rootView = EchoGramMusicPane(workspace: workspace, session: workspace.session, showToolbar: showToolbar)
        }
        if #available(macOS 26, *) {
            page.layer?.cornerRadius = showToolbar ? 0 : 20
        } else {
            page.layer?.cornerRadius = showToolbar ? 0 : 8
        }
        let inset = showToolbar ? bottomInset : 0
        if page.superview !== target {
            bottom = mount(page, in: target, bottomInset: inset)
        } else {
            bottom?.constant = -inset
        }
        if detail == nil {
            sidebar.removeFromSuperview()
        } else if sidebar.superview !== tab {
            mount(sidebar, in: tab, bottomInset: 0)
        }
    }

    func updateSidebar(tabs: [EchoGramMusicSidebarTab], bottomInset: CGFloat, colors: EchoGramMusicSidebarColors) {
        sidebar.rootView = EchoGramMusicSidebar(workspace: workspace, selectedProvider: workspace.session.provider, tabs: tabs, bottomInset: bottomInset, colors: colors)
    }

    func detach() {
        page.removeFromSuperview()
        sidebar.removeFromSuperview()
        bottom = nil
    }

    func setStreamerMode(_ active: Bool) {
        workspace.setStreamerMode(active)
    }

    func setDarkAppearance(_ active: Bool) {
        let appearance = NSAppearance(named: active ? .darkAqua : .aqua)
        page.appearance = appearance
        sidebar.appearance = appearance
        workspace.setAppearance(appearance)
    }

    @discardableResult
    private func mount(_ child: NSView, in parent: NSView, bottomInset: CGFloat) -> NSLayoutConstraint {
        child.removeFromSuperview()
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child, positioned: .above, relativeTo: nil)
        let bottom = child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -bottomInset)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            bottom
        ])
        return bottom
    }
}

private struct EchoGramMusicSidebar: View {
    @ObservedObject var workspace: MusicWorkspace
    let selectedProvider: MusicProvider
    let tabs: [EchoGramMusicSidebarTab]
    let bottomInset: CGFloat
    let colors: EchoGramMusicSidebarColors
    private var compact: Bool { !tabs.isEmpty }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(alignment: compact ? .center : .leading, spacing: compact ? 4 : 1) {
                    MusicHeading(compact: compact)
                        .padding(.horizontal, compact ? 0 : 14)
                        .padding(.bottom, 8)
                    if !workspace.isStreamerMode {
                        ForEach(MusicProvider.allCases) { provider in
                            musicAction(provider.title, assetName: provider.iconAsset, selected: selectedProvider == provider, opensPage: true) {
                                workspace.select(provider)
                            }
                        }
                        separator
                            .padding(.horizontal, compact ? 6 : 14)
                            .padding(.vertical, 7)
                        musicAction("Обновить страницу", symbol: "arrow.clockwise", tint: .purple, action: workspace.session.retry)
                    }
                }
                .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            }
            if compact {
                separator
                VStack(spacing: 2) {
                    ForEach(tabs) { tab in
                        iconButton(tab.title, selected: tab.selected, action: tab.action) {
                            Image(decorative: tab.icon, scale: tab.iconScale)
                                .renderingMode(.template)
                        }
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(colors.foreground)
        .padding(.horizontal, compact ? 8 : 6)
        .padding(.top, 34)
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.background)
        .overlay(alignment: .trailing) {
            Capsule()
                .fill(colors.foreground.opacity(0.4))
                .frame(width: 3, height: 24)
                .padding(.trailing, 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var separator: some View {
        Rectangle().fill(colors.border).frame(height: 1)
    }

    private func musicAction(_ title: String, symbol: String = "", tint: Color = .clear, assetName: String? = nil, selected: Bool = false, opensPage: Bool = false, action: @escaping () -> Void) -> some View {
        MusicSidebarAction(
            title: title, symbol: symbol, tint: tint, assetName: assetName, compact: compact,
            selected: selected, opensPage: opensPage, colors: colors, action: action
        )
    }

    private func iconButton<Icon: View>(_ title: String, selected: Bool = false, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            icon()
                .foregroundStyle(selected ? colors.selectedForeground : colors.foreground)
                .frame(width: 48, height: 34)
                .overlay {
                    if selected {
                        Capsule().strokeBorder(colors.border, lineWidth: 1)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MusicSidebarAction: View {
    let title: String
    let symbol: String
    let tint: Color
    let assetName: String?
    let compact: Bool
    let selected: Bool
    let opensPage: Bool
    let colors: EchoGramMusicSidebarColors
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if let assetName {
                        Image(assetName)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(tint, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .accessibilityHidden(true)
                if !compact {
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundStyle(selected ? colors.selectedText : colors.foreground)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if opensPage && !selected {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(colors.foreground.opacity(0.38))
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, compact ? 0 : 14)
            .frame(maxWidth: .infinity, minHeight: compact ? 34 : 40, alignment: compact ? .center : .leading)
        }
        .buttonStyle(MusicSidebarButtonStyle(selected: selected, colors: colors))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MusicSidebarButtonStyle: ButtonStyle {
    let selected: Bool
    let colors: EchoGramMusicSidebarColors
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let highlighted = hovered || configuration.isPressed
        return configuration.label
            .background(selected ? colors.selectedBackground : highlighted ? colors.hover : .clear, in: Capsule())
            .contentShape(Capsule())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.1), value: highlighted)
            .animation(.easeOut(duration: 0.1), value: selected)
    }
}

private struct EchoGramMusicPane: View {
    @ObservedObject var workspace: MusicWorkspace
    let session: MusicWebSession
    let showToolbar: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showToolbar {
                HStack(spacing: 12) {
                    MusicHeading()
                    Spacer(minLength: 8)
                    if !workspace.isStreamerMode {
                        Button("Обновить страницу", systemImage: "arrow.clockwise", action: session.retry)
                            .labelStyle(.iconOnly)
                            .help("Обновить страницу")
                        Menu("Сервисы") {
                            ForEach(MusicProvider.allCases) { provider in
                                Button(provider.title) { workspace.select(provider) }
                            }
                        }
                    }
                }
                .padding(12)
                Divider()
            }

            if workspace.isStreamerMode {
                ContentUnavailableView("Режим стримера", systemImage: "eye.slash")
            } else {
                MusicWebPane(session: session)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private struct MusicWebPane: View {
    @ObservedObject var session: MusicWebSession

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let minimum = session.provider.minimumWebsiteWidth
                let zoom = width > 0 && minimum > 0 ? min(1, floor(width) / minimum) : 1
                MusicWebView(webView: session.webView, zoom: zoom)
            }
            if let error = session.error {
                ContentUnavailableView {
                    Label("Не удалось загрузить страницу", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(error)
                } actions: {
                    Button("Повторить", action: session.retry)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
            }
        }
        .onAppear(perform: session.start)
        .sheet(isPresented: Binding(
            get: { session.popup != nil },
            set: { if !$0 { session.closePopups() } }
        )) {
            MusicSignInSheet(session: session)
        }
    }
}

private struct MusicSignInSheet: View {
    @ObservedObject var session: MusicWebSession

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: session.provider.title).font(.headline)
                Spacer()
                Button("Закрыть", action: session.closePopups)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()
            if let popup = session.popup {
                MusicWebView(webView: popup.webView)
                    .id(ObjectIdentifier(popup.webView))
            }
        }
        .frame(minWidth: 520, minHeight: 530)
    }
}

private struct MusicHeading: View {
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.title2.weight(.semibold))
                .accessibilityHidden(true)
            if !compact {
                Text("Музыка").font(.headline)
            }
        }
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Музыка")
    }
}

private struct MusicWebView: NSViewRepresentable {
    let webView: WKWebView
    var zoom: CGFloat = 1

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ container: NSView, context: Context) {
        if webView.superview !== container {
            for child in container.subviews {
                child.removeFromSuperview()
            }
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.frame = container.bounds
            webView.autoresizingMask = [.width, .height]
            container.addSubview(webView)
        }
        if webView.pageZoom != zoom {
            webView.pageZoom = zoom
        }
    }
}

@MainActor
private final class SoundCloudBrowserSignIn: NSObject, WKScriptMessageHandler {
    static let name = "echoGramSoundCloudBrowserSignIn"
    static let contentWorld = WKContentWorld.world(name: "EchoGram.SoundCloud")
    static let script = """
        (() => {
            if (!["soundcloud.com", "www.soundcloud.com", "secure.soundcloud.com"].includes(location.hostname)) return;
            document.addEventListener("click", (event) => {
                if (!event.isTrusted) return;
                const button = event.composedPath().find(node =>
                    node instanceof Element && node.matches("button, a, [role=button]"));
                if (!button) return;
                const labels = [button.getAttribute("aria-label"), button.textContent];
                if (!labels.some(label => /^(continue with|sign in with|log in with) google$/i.test(
                    (label ?? "").trim().replace(/\\s+/g, " ")
                ))) return;
                event.preventDefault();
                event.stopImmediatePropagation();
                window.webkit.messageHandlers.echoGramSoundCloudBrowserSignIn.postMessage(true);
            }, true);
        })();
        """

    weak var session: MusicWebSession?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard message.name == Self.name, message.body as? Bool == true,
              origin.protocol == "https", origin.port == 0 || origin.port == 443,
              ["soundcloud.com", "www.soundcloud.com", "secure.soundcloud.com"].contains(origin.host.lowercased()),
              let webView = message.webView else { return }
        session?.openGoogleSignIn(from: webView)
    }
}

@MainActor
private final class MusicWebSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    struct Popup {
        let webView: WKWebView
    }

    let provider: MusicProvider

    private var isLoading = false
    @Published private(set) var error: String?
    @Published private var popups: [Popup] = []
    var popup: Popup? { popups.last }
    private(set) var isStreamerMode = false
    let webView: WKWebView

    private var started = false
    private var lastURL: URL

    init(provider: MusicProvider) {
        self.provider = provider
        self.lastURL = provider.libraryURL
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: provider.profileID)
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        if provider == .spotify {
            configuration.defaultWebpagePreferences.preferredContentMode = .desktop
            if let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari"),
               let safariVersion = Bundle(url: safariURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                configuration.applicationNameForUserAgent = "Version/\(safariVersion) Safari/605.1.15"
            }
        }
        let browserSignIn = provider == .soundCloud ? SoundCloudBrowserSignIn() : nil
        if let browserSignIn {
            let scripts = configuration.userContentController
            scripts.add(browserSignIn, contentWorld: SoundCloudBrowserSignIn.contentWorld, name: SoundCloudBrowserSignIn.name)
            scripts.addUserScript(WKUserScript(source: SoundCloudBrowserSignIn.script, injectionTime: .atDocumentStart,
                                               forMainFrameOnly: false, in: SoundCloudBrowserSignIn.contentWorld))
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        browserSignIn?.session = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func start() {
        guard !started, !isStreamerMode else { return }
        started = true
        openLibrary()
    }

    func setStreamerMode(_ active: Bool) {
        guard isStreamerMode != active else { return }
        webView.isHidden = active
        popup?.webView.isHidden = active
        isStreamerMode = active
        if active {
            closePopups()
            webView.pauseAllMediaPlayback(completionHandler: nil)
            webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        } else {
            webView.setAllMediaPlaybackSuspended(false, completionHandler: nil)
        }
    }

    func deactivate() {
        webView.isHidden = true
        closePopups()
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.setAllMediaPlaybackSuspended(true, completionHandler: nil)
    }

    func activate() {
        webView.isHidden = false
        webView.setAllMediaPlaybackSuspended(false, completionHandler: nil)
    }

    func openLibrary() {
        load(provider.libraryURL)
    }

    func openSignIn() {
        started = true
        closePopups()
        load(provider.signInURL)
    }

    func openGoogleSignIn(from sender: WKWebView) {
        guard provider == .soundCloud, !isStreamerMode,
              sender === webView || popups.contains(where: { $0.webView === sender }) else { return }
        NSWorkspace.shared.open(provider.libraryURL)
    }

    func retry() {
        guard !isStreamerMode else { return }
        if error != nil || webView.url == nil {
            load(lastURL)
        } else {
            webView.reload()
        }
    }

    func closePopups() {
        dismissPopups(from: popups.startIndex)
    }

    private func dismissPopups(from index: Int) {
        guard popups.indices.contains(index) else { return }
        let dismissed = Array(popups[index...])
        popups.removeSubrange(index...)
        for popup in dismissed.reversed() {
            popup.webView.stopLoading()
        }
    }

    private func setError(_ value: String?) {
        guard error != value else { return }
        error = value
    }

    private func load(_ url: URL) {
        guard !isStreamerMode else { return }
        lastURL = url
        setError(nil)
        isLoading = true
        webView.load(URLRequest(url: url))
    }

    func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else {
            decisionHandler(.cancel)
            return
        }
        if action.targetFrame?.isMainFrame != false, url.host?.lowercased() == "accounts.google.com" {
            decisionHandler(.cancel)
            showBrowserSignIn(from: view)
            return
        }
        if action.targetFrame?.isMainFrame == false {
            let allowed = ["https", "about", "blob", "data"].contains(url.scheme ?? "")
            decisionHandler(allowed ? .allow : .cancel)
        } else if provider.allows(url) || url.absoluteString == "about:blank" {
            if view === webView, action.targetFrame?.isMainFrame == true,
               provider.allows(url), action.request.httpMethod == "GET" {
                lastURL = url
            }
            decisionHandler(.allow)
        } else {
            if action.navigationType == .linkActivated && url.scheme == "https" {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }

    func webView(_ view: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if view === webView, response.isForMainFrame,
           let result = response.response as? HTTPURLResponse,
           result.statusCode >= 400, result.statusCode != 401 {
            isLoading = false
            setError("Сайт ответил ошибкой HTTP \(result.statusCode).")
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ view: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard view === webView else { return }
        setError(nil)
        isLoading = true
    }

    func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
        if view === webView { isLoading = false }
    }

    func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError failure: Error) {
        handleFailure(in: view, failure: failure)
    }

    func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError failure: Error) {
        handleFailure(in: view, failure: failure)
    }

    private func handleFailure(in view: WKWebView, failure: Error) {
        let details = failure as NSError
        if details.domain == NSURLErrorDomain, details.code == NSURLErrorCancelled { return }
        if view === webView {
            guard isLoading else { return }
            isLoading = false
            setError("Проверьте подключение и повторите загрузку.")
        } else if popup?.webView === view {
            closePopups()
            setError("Не удалось открыть окно входа. Попробуйте подключить сервис ещё раз.")
        }
    }

    func webViewWebContentProcessDidTerminate(_ view: WKWebView) {
        if view === webView {
            isLoading = false
            setError("Веб-страница остановлена. Загрузите её ещё раз.")
        } else {
            webViewDidClose(view)
        }
    }

    private func showBrowserSignIn(from sender: WKWebView) {
        if provider == .soundCloud {
            openGoogleSignIn(from: sender)
            setError("Продолжите вход через Google в открывшемся браузере.")
        } else {
            setError("Выберите другой способ входа на странице сервиса.")
        }
        closePopups()
        isLoading = false
    }

    func webView(_ view: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let origin = action.sourceFrame.securityOrigin
        guard !isStreamerMode, action.targetFrame == nil, popups.count < 3,
              view === webView || popup?.webView === view,
              origin.protocol == "https", origin.port == 0 || origin.port == 443,
              let originURL = URL(string: "https://\(origin.host)"), provider.allows(originURL),
              let url = action.request.url else { return nil }
        if url.host?.lowercased() == "accounts.google.com" {
            showBrowserSignIn(from: view)
            return nil
        }
        guard provider.allows(url) || url.absoluteString == "about:blank" else { return nil }
        let child = WKWebView(frame: .zero, configuration: configuration)
        child.navigationDelegate = self
        child.uiDelegate = self
        popups.append(Popup(webView: child))
        return child
    }

    func webViewDidClose(_ view: WKWebView) {
        guard let index = popups.firstIndex(where: { $0.webView === view }) else { return }
        dismissPopups(from: index)
    }
}
