import SwiftUI

/// Settings → Proxy: app-wide HTTP/SOCKS5 proxy for the app's own network
/// requests (AI providers) and the terminal.
///
/// WKWebView (in-app browser) cannot take a per-app proxy on iOS — it
/// follows the iOS system proxy settings. The page says so.
struct ProxySettingsView: View {
    @AppStorage("proxyEnabled") private var proxyEnabled = false
    @AppStorage("proxyType") private var proxyTypeRaw: String = ProxyStore.ProxyType.http.rawValue
    @AppStorage("proxyHost") private var proxyHost: String = ""
    @AppStorage("proxyPort") private var proxyPort: Int = ProxyStore.defaultPort

    @State private var testResult: String?
    @State private var testing = false

    private var proxyType: ProxyStore.ProxyType {
        get { ProxyStore.ProxyType(rawValue: proxyTypeRaw) ?? .http }
        set { proxyTypeRaw = newValue.rawValue }
    }

    var body: some View {
        List {
            Section {
                Toggle("Enable Proxy", isOn: $proxyEnabled)
            } footer: {
                Text("When on, the app's network requests and the terminal go through this proxy. Long-lived streaming connections pick it up after an app restart.")
            }

            Section("Proxy Server") {
                Picker("Type", selection: Binding(
                    get: { proxyType },
                    set: { proxyType = $0 }
                )) {
                    ForEach(ProxyStore.ProxyType.allCases, id: \.self) { t in
                        Text(t.title).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Host")
                    Spacer()
                    TextField("127.0.0.1", text: $proxyHost)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("", value: $proxyPort, format: .number)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }
            }

            Section {
                Button {
                    testProxy()
                } label: {
                    if testing {
                        HStack {
                            Text("Testing…")
                            Spacer()
                            ProgressView()
                        }
                    } else {
                        Text("Test Connection")
                    }
                }
                .disabled(testing || !ProxyStore.isActive)
                if let testResult {
                    Text(testResult)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Fetches api.github.com through the proxy.")
            }

            Section("Note") {
                Text("The in-app browser follows the iOS system proxy (Settings → WLAN → HTTP Proxy, or a VPN app) and cannot use this proxy. Everything else in Minis — AI requests and the terminal — uses it.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Proxy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func testProxy() {
        testing = true
        testResult = nil
        Task {
            let result: String
            do {
                var req = URLRequest(url: URL(string: "https://api.github.com")!)
                req.timeoutInterval = 15
                let (_, resp) = try await AppNetwork.shared.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                result = code == 200 || code == 403
                    ? "OK — GitHub is reachable through the proxy (HTTP \(code))."
                    : "GitHub returned HTTP \(code) — proxy works but GitHub responded oddly."
            } catch {
                result = "Failed: \(error.localizedDescription)"
            }
            await MainActor.run {
                testResult = result
                testing = false
            }
        }
    }
}
