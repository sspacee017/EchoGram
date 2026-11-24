import AppKit
import SwiftUI
import QuartzCore
import class TGUIKit.ViewController
import WebKit

enum EchoGramBrowserRouting {
    static var presenter: ((URL, NSWindow?) -> Bool)?

    static func open(_ url: URL, window: NSWindow?) -> Bool {
        guard Thread.isMainThread,
              EchoGramBrowserSession.isWebURL(url),
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: {
                  $0.name.caseInsensitiveCompare("autologin_token") == .orderedSame
              }) != true else { return false }
        return presenter?(url, window) ?? false
    }
}

@available(macOS 15.0, *)
final class EchoGramBrowserController: ViewController {
    private let workspace: EchoGramBrowserWorkspace

    init(onClose: @escaping () -> Void, onWidthChanged: @escaping (Bool) -> Void) {
        self.workspace = MainActor.assumeIsolated {
            EchoGramBrowserWorkspace(onClose: onClose, onWidthChanged: onWidthChanged)
        }
        super.init()
        bar = .init(height: 0)
    }

    var preferredWidth: CGFloat {
        MainActor.assumeIsolated { workspace.preferredWidth }
    }

    func open(_ url: URL) {
        MainActor.assumeIsolated { workspace.open(url) }
    }

    override func defaultInitializer() -> NSView {
        MainActor.assumeIsolated {
            EchoGramBrowserWorkspaceView(workspace: workspace)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        readyOnce()
    }
}

@MainActor
private final class EchoGramBrowserWorkspace {
    struct Page: Identifiable {
        let id = UUID()
        let session: EchoGramBrowserSession
        var width: CGFloat = 350
    }

    static let horizontalInset: CGFloat = 3
    static let gap: CGFloat = 6

    private(set) var pages: [Page] = []
    private(set) var revealPage: UUID?
    var onLayoutChanged: ((Bool) -> Void)?
    private let onClose: () -> Void
    private let onWidthChanged: (Bool) -> Void

    init(onClose: @escaping () -> Void, onWidthChanged: @escaping (Bool) -> Void) {
        self.onClose = onClose
        self.onWidthChanged = onWidthChanged
    }

    var preferredWidth: CGFloat {
        pages.reduce(Self.horizontalInset * 2) { $0 + $1.width } + CGFloat(max(0, pages.count - 1)) * Self.gap
    }

    func open(_ url: URL) {
        let session = EchoGramBrowserSession()
        session.openInNewPage = { [weak self] url in self?.open(url) }
        session.show(url)
        let page = Page(session: session)
        let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        pages.append(page)
        revealPage = page.id
        onLayoutChanged?(animated)
        onWidthChanged(animated)
    }

    func close(_ id: UUID) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[index].session.webView.stopLoading()
        if pages.count == 1 {
            onClose()
        } else {
            pages.remove(at: index)
            let animated = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            onLayoutChanged?(animated)
            onWidthChanged(animated)
        }
    }

    func resize(_ id: UUID, width: CGFloat) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        let width = max(160, width)
        guard pages[index].width != width else { return }
        pages[index].width = width
        onLayoutChanged?(false)
        onWidthChanged(false)
    }

    func swap(_ id: UUID, with destination: Int) {
        guard let index = pages.firstIndex(where: { $0.id == id }),
              pages.indices.contains(destination), index != destination else { return }
        pages.swapAt(index, destination)
        onLayoutChanged?(!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

@MainActor
private final class EchoGramBrowserWorkspaceView: NSView {
    private final class DocumentView: NSView {
        override var isFlipped: Bool { true }
    }

    private let workspace: EchoGramBrowserWorkspace
    private let scroll = NSScrollView()
    private let document = DocumentView()
    private var panes: [UUID: NSHostingView<BrowserCard>] = [:]
    private var revealedPage: UUID?
    private var dragLastX: CGFloat?
    private var lastSwapX: CGFloat?
    private var lastSwapDirection: CGFloat = 0
    private var resizeStart: CGFloat?

    init(workspace: EchoGramBrowserWorkspace) {
        self.workspace = workspace
        super.init(frame: .zero)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        scroll.documentView = document
        scroll.autoresizingMask = [.width, .height]
        addSubview(scroll)
        workspace.onLayoutChanged = { [weak self] animated in self?.layoutPages(animated: animated) }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        if scroll.frame != bounds { scroll.frame = bounds }
        layoutPages(animated: false)
    }

    private func layoutPages(animated: Bool) {
        let viewport = scroll.contentView.bounds.size
        guard viewport.height > 0, viewport.width > 0 else { return }
        let ids = Set(workspace.pages.map(\.id))
        for id in Array(panes.keys) where !ids.contains(id) {
            panes.removeValue(forKey: id)?.removeFromSuperview()
        }

        let size = NSSize(width: max(viewport.width, workspace.preferredWidth), height: viewport.height)
        if document.frame.size != size { document.setFrameSize(size) }

        var x = EchoGramBrowserWorkspace.horizontalInset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for page in workspace.pages {
            let frame = NSRect(x: x, y: 0, width: page.width, height: max(0, viewport.height - 4))
            if let pane = panes[page.id] {
                if pane.frame != frame {
                    let visualX = pane.frame.minX + (pane.layer?.presentation()?.transform.m41 ?? 0)
                    pane.layer?.removeAnimation(forKey: "browserReorder")
                    pane.frame = frame
                    if animated, abs(visualX - frame.minX) > 0.5 {
                        let move = CABasicAnimation(keyPath: "transform.translation.x")
                        move.fromValue = visualX - frame.minX
                        move.toValue = 0
                        move.duration = 0.25
                        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.82, 0.30, 1)
                        pane.layer?.add(move, forKey: "browserReorder")
                    }
                }
            } else {
                let pane = makePane(page)
                pane.frame = frame
                panes[page.id] = pane
                document.addSubview(pane)
            }
            x = frame.maxX + EchoGramBrowserWorkspace.gap
        }
        CATransaction.commit()

        if let id = workspace.revealPage, revealedPage != id, let pane = panes[id] {
            revealedPage = id
            pane.scrollToVisible(pane.bounds)
        }
    }

    private func makePane(_ page: EchoGramBrowserWorkspace.Page) -> NSHostingView<BrowserCard> {
        let id = page.id
        let pane = NSHostingView(rootView: BrowserCard(
            browser: page.session,
            onClose: { [weak self] in self?.workspace.close(id) },
            headerPointer: BrowserPointerSurface(cursor: .openHand, drag: { [weak self] start, point in
                self?.reorder(id, start: start, point: point)
            }, end: { [weak self] _, _ in self?.endReorder() }),
            resizePointer: BrowserPointerSurface(cursor: .resizeLeftRight, drag: { [weak self] start, point in
                self?.resize(id, start: start, point: point)
            }, end: { [weak self] start, point in
                guard let self, resizeStart != nil else { return }
                resize(id, start: start, point: point)
                resizeStart = nil
            }),
            moveLeft: { [weak self] in self?.move(id, by: -1) },
            moveRight: { [weak self] in self?.move(id, by: 1) },
            adjustWidth: { [weak self] delta in
                guard let self, let page = workspace.pages.first(where: { $0.id == id }) else { return }
                workspace.resize(id, width: page.width + delta)
            }
        ))
        pane.sizingOptions = []
        pane.wantsLayer = true
        pane.layer?.cornerRadius = 10
        pane.layer?.masksToBounds = true
        return pane
    }

    private func move(_ id: UUID, by step: Int) {
        guard let index = workspace.pages.firstIndex(where: { $0.id == id }) else { return }
        workspace.swap(id, with: index + step)
    }

    private func reorder(_ id: UUID, start: CGPoint, point: CGPoint) {
        guard resizeStart == nil, abs(point.x - start.x) >= 4 || dragLastX != nil,
              let index = workspace.pages.firstIndex(where: { $0.id == id }) else { return }
        let direction = point.x - (dragLastX ?? start.x)
        dragLastX = point.x
        if let lastSwapX, direction * lastSwapDirection < 0, abs(point.x - lastSwapX) < 12 { return }

        let location = document.convert(point, from: nil)
        guard scroll.contentView.documentVisibleRect.contains(location),
              let destination = workspace.pages.indices.first(where: { target in
                  ((direction > 0 && target > index) || (direction < 0 && target < index))
                      && (panes[workspace.pages[target].id]?.frame.contains(location) ?? false)
              }) else { return }
        lastSwapX = point.x
        lastSwapDirection = direction
        workspace.swap(id, with: destination)
    }

    private func endReorder() {
        dragLastX = nil
        lastSwapX = nil
        lastSwapDirection = 0
    }

    private func resize(_ id: UUID, start: CGPoint, point: CGPoint) {
        guard dragLastX == nil, let page = workspace.pages.first(where: { $0.id == id }) else { return }
        if resizeStart == nil { resizeStart = page.width }
        workspace.resize(id, width: (resizeStart ?? page.width) + start.x - point.x)
    }
}

private struct BrowserCard: SwiftUI.View {
    let browser: EchoGramBrowserSession
    let onClose: () -> Void
    let headerPointer: BrowserPointerSurface
    let resizePointer: BrowserPointerSurface
    let moveLeft: () -> Void
    let moveRight: () -> Void
    let adjustWidth: (CGFloat) -> Void

    var body: some View {
        EchoGramBrowserPane(
            browser: browser, onClose: onClose, headerPointer: headerPointer,
            moveLeft: moveLeft, moveRight: moveRight
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.primary.opacity(0.12))
                .allowsHitTesting(false)
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(.secondary.opacity(0.55))
                .frame(width: 3, height: 26)
                .frame(width: 12, height: 64)
                .overlay { resizePointer }
                .help("Изменить ширину страницы") //TODOLANG
                .accessibilityLabel("Ширина страницы") //TODOLANG
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: adjustWidth(40)
                    case .decrement: adjustWidth(-40)
                    @unknown default: break
                    }
                }
        }
    }
}

@available(macOS 15.0, *)
@MainActor
private struct EchoGramBrowserPane: SwiftUI.View {
    @ObservedObject var browser: EchoGramBrowserSession
    let onClose: () -> Void
    let headerPointer: BrowserPointerSurface
    let moveLeft: () -> Void
    let moveRight: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal")
                        .accessibilityHidden(true)
                    Text(browser.addressLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityLabel("Адрес страницы") //TODOLANG
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .overlay { headerPointer }
                .help("Перетащить страницу") //TODOLANG
                .accessibilityAction(named: Text("Переместить влево"), moveLeft) //TODOLANG
                .accessibilityAction(named: Text("Переместить вправо"), moveRight) //TODOLANG

                action("Назад", icon: "chevron.left", perform: browser.back) //TODOLANG
                    .disabled(!browser.canGoBack)
                action("Вперёд", icon: "chevron.right", perform: browser.forward) //TODOLANG
                    .disabled(!browser.canGoForward)
                action("Обновить", icon: "arrow.clockwise", perform: browser.reload) //TODOLANG
                    .disabled(browser.address == nil)
                action("Открыть в браузере", icon: "arrow.up.right.square", perform: browser.openExternally) //TODOLANG
                    .disabled(browser.address == nil)
                action("Закрыть страницу", icon: "xmark", perform: onClose) //TODOLANG
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ZStack(alignment: .top) {
                BrowserSurface(webView: browser.webView)
                    .accessibilityHidden(browser.error != nil)

                if browser.loading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Загрузка страницы") //TODOLANG
                }

                if let error = browser.error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("Не удалось открыть страницу") //TODOLANG
                            .font(.headline)
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if browser.address != nil {
                            Button("Повторить", action: browser.reload) //TODOLANG
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }
    }

    private func action(_ title: String, icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: icon)
                .labelStyle(.iconOnly)
                .frame(width: 23, height: 24)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct BrowserPointerSurface: NSViewRepresentable {
    let cursor: NSCursor
    let drag: (CGPoint, CGPoint) -> Void
    let end: (CGPoint, CGPoint) -> Void

    func makeNSView(context: Context) -> PointerView { PointerView() }

    func updateNSView(_ view: PointerView, context: Context) {
        view.cursor = cursor
        view.drag = drag
        view.end = end
    }

    final class PointerView: NSView {
        var cursor: NSCursor = .arrow
        var drag: ((CGPoint, CGPoint) -> Void)?
        var end: ((CGPoint, CGPoint) -> Void)?
        private var start: CGPoint?
        private var eventMonitor: Any?

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: cursor)
        }

        override func mouseDown(with event: NSEvent) {
            stopTracking()
            start = event.locationInWindow
            if cursor == NSCursor.openHand { NSCursor.closedHand.set() }
            let windowNumber = event.windowNumber
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
                guard let self, event.windowNumber == windowNumber else { return event }
                if event.type == .leftMouseUp {
                    self.mouseUp(with: event)
                } else {
                    self.mouseDragged(with: event)
                }
                return nil
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start else { return }
            drag?(start, event.locationInWindow)
        }

        override func mouseUp(with event: NSEvent) {
            guard let start else { return }
            stopTracking()
            end?(start, event.locationInWindow)
            cursor.set()
        }

        private func stopTracking() {
            start = nil
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
        }

        deinit {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        }
    }
}

private struct BrowserSurface: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

@MainActor
private final class EchoGramBrowserSession: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView

    private struct State: Equatable {
        var address: URL?
        var loading = false
        var error: String?
        var canGoBack = false
        var canGoForward = false
    }

    @Published private var state = State()

    var address: URL? { state.address }
    var loading: Bool { state.loading }
    var error: String? { state.error }
    var canGoBack: Bool { state.canGoBack }
    var canGoForward: Bool { state.canGoForward }

    var openInNewPage: ((URL) -> Void)?
    private var activeNavigation: WKNavigation?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    var addressLabel: String {
        guard let address, let host = address.host else { return "Веб‑страница" } //TODOLANG
        let path = address.path == "/" ? "" : address.path
        return host + path
    }

    func show(_ url: URL) {
        guard address != url || error != nil else { return }
        load(url)
    }

    func back() {
        guard let target = webView.backForwardList.backItem else { return }
        begin(target.url)
        activeNavigation = webView.go(to: target)
    }

    func forward() {
        guard let target = webView.backForwardList.forwardItem else { return }
        begin(target.url)
        activeNavigation = webView.go(to: target)
    }

    func reload() {
        guard let address else { return }
        if error != nil || address != webView.url {
            load(address)
        } else {
            begin(address)
            activeNavigation = webView.reload()
        }
    }

    func openExternally() {
        guard let address, Self.isWebURL(address) else { return }
        NSWorkspace.shared.open(address)
    }

    private func load(_ url: URL) {
        guard Self.isWebURL(url) else {
            webView.stopLoading()
            updateState { $0.address = nil }
            showError("В этой панели открываются страницы HTTP и HTTPS.") //TODOLANG
            return
        }
        begin(url)
        activeNavigation = webView.load(URLRequest(url: url))
    }

    private func begin(_ url: URL) {
        updateState {
            $0.address = url
            $0.error = nil
            $0.loading = true
        }
    }

    private func syncHistory() {
        updateState {
            $0.canGoBack = webView.canGoBack
            $0.canGoForward = webView.canGoForward
        }
    }

    private func showError(_ message: String) {
        updateState {
            $0.loading = false
            $0.error = message
            $0.canGoBack = webView.canGoBack
            $0.canGoForward = webView.canGoForward
        }
    }

    private func updateState(_ update: (inout State) -> Void) {
        var next = state
        update(&next)
        if next != state { state = next }
    }

    nonisolated static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return false }
        return url.user == nil && url.password == nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url else {
            decisionHandler(.cancel)
            return
        }

        if action.targetFrame?.isMainFrame == false,
           ["about", "blob", "data"].contains(url.scheme?.lowercased() ?? "") {
            decisionHandler(.allow)
            return
        }

        guard Self.isWebURL(url) else {
            decisionHandler(.cancel)
            return
        }

        if action.targetFrame == nil {
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated { openInNewPage?(url) }
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor response: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard response.isForMainFrame else {
            decisionHandler(.allow)
            return
        }

        guard let responseURL = response.response.url, Self.isWebURL(responseURL) else {
            showError("Сайт перенаправил страницу на неподдерживаемый адрес.") //TODOLANG
            decisionHandler(.cancel)
            return
        }
        updateState { $0.address = responseURL }

        if let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
            showError("Сайт вернул ошибку HTTP \(http.statusCode).") //TODOLANG
            decisionHandler(.cancel)
            return
        }

        if !response.canShowMIMEType {
            showError("Этот файл можно открыть во внешнем браузере.") //TODOLANG
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activeNavigation = navigation
        if let url = webView.url, Self.isWebURL(url) { begin(url) }
        syncHistory()
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        if let url = webView.url, Self.isWebURL(url) { updateState { $0.address = url } }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let url = webView.url, Self.isWebURL(url) { updateState { $0.address = url } }
        syncHistory()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard activeNavigation === navigation else { return }
        if let url = webView.url, Self.isWebURL(url) { updateState { $0.address = url } }
        updateState { $0.loading = false }
        syncHistory()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleFailure(navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(navigation, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showError("Страница закрылась. Загрузите её снова.") //TODOLANG
    }

    private func handleFailure(_ navigation: WKNavigation?, error: Error) {
        guard activeNavigation === navigation, self.error == nil else { return }
        let failure = error as NSError
        if failure.domain == NSURLErrorDomain,
           failure.code == NSURLErrorCancelled {
            updateState { $0.loading = false }
            syncHistory()
            return
        }
        if let failedURL = failure.userInfo[NSURLErrorFailingURLErrorKey] as? URL,
           Self.isWebURL(failedURL) {
            updateState { $0.address = failedURL }
        }
        if failure.domain == NSURLErrorDomain,
           failure.code == NSURLErrorNotConnectedToInternet || failure.code == NSURLErrorNetworkConnectionLost {
            showError("Проверьте подключение к интернету и повторите попытку.") //TODOLANG
        } else {
            showError("Проверьте адрес или откройте страницу во внешнем браузере.") //TODOLANG
        }
    }
}
