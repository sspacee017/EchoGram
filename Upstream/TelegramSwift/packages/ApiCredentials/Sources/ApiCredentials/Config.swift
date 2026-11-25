import Cocoa
import CompiledTelegramAPI
import Darwin

public final class ApiEnvironment {
    public static let bundleId = "dev.echogram.fork"
    public static let teamId = ""
    public static let group = "group.dev.echogram.fork"
    public static let keychainScope = bundleId
    public static let updatesEnabled = false
    public static let credentialFileName = "telegram-api.json"

    public enum CredentialStatus: Equatable {
        case missing, inaccessible, invalid, ready
    }

    private struct Credentials: Decodable {
        let apiId: Int32
        let apiHash: String

        enum CodingKeys: String, CodingKey {
            case apiId = "api_id"
            case apiHash = "api_hash"
        }
    }

    private static let credentialConfiguration = loadCredentials()

    public static var credentialStatus: CredentialStatus {
        return credentialConfiguration.status
    }

    public static var apiId: Int32 {
        return credentialConfiguration.credentials?.apiId ?? 0
    }

    public static var apiHash: String {
        return credentialConfiguration.credentials?.apiHash ?? ""
    }

    public static var credentialDirectory: URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return privateDirectory(support.appendingPathComponent(bundleId, isDirectory: true))
    }

    public static var containerURL: URL? {
        guard let parent = credentialDirectory else {
            return nil
        }
        return privateDirectory(parent.appendingPathComponent(prefix, isDirectory: true))
    }

    public static var legacyContainerURL: URL? {
        return credentialDirectory
    }

    private static func privateDirectory(_ url: URL) -> URL? {
        let path = url.path
        guard mkdir(path, 0o700) == 0 || errno == EEXIST else {
            return nil
        }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
            return nil
        }
        return url
    }

    private static func loadCredentials() -> (status: CredentialStatus, credentials: Credentials?) {
        let buildApiId = EchoGramCompiledApiId()
        if buildApiId > 0, let buildApiHash = EchoGramCompiledApiHash() {
            return (.ready, Credentials(apiId: buildApiId, apiHash: String(cString: buildApiHash)))
        }
        guard let directory = credentialDirectory else {
            return (.inaccessible, nil)
        }
        return readCredentials(at: directory.appendingPathComponent(credentialFileName))
    }

    private static func readCredentials(at url: URL) -> (status: CredentialStatus, credentials: Credentials?) {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            return (errno == ENOENT ? .missing : .inaccessible, nil)
        }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(),
              info.st_mode & 0o077 == 0 else {
            return (.inaccessible, nil)
        }
        var bytes = [UInt8](repeating: 0, count: 4097)
        let byteCount = bytes.withUnsafeMutableBytes { buffer in
            Darwin.read(descriptor, buffer.baseAddress, buffer.count)
        }
        guard byteCount > 0, byteCount < bytes.count, byteCount == info.st_size,
              let credentials = try? JSONDecoder().decode(Credentials.self, from: Data(bytes.prefix(byteCount))),
              credentials.apiId > 0,
              credentials.apiHash.utf8.count == 32,
              credentials.apiHash.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            return (.invalid, nil)
        }
        return (.ready, credentials)
    }

    public static var appData: Data {
        let apiData = evaluateApiData() ?? ""
        let dict:[String: String] = ["bundleId": bundleId, "data": apiData]
        return try! JSONSerialization.data(withJSONObject: dict, options: [])
    }
    public static var language: String {
        return "macos"
    }
    
    public static var prefixList:[String] {
        return ["debug", "stable", "appstore", "beta"]
    }
    
    public static var prefix: String {
        var prefix: String = ""
        switch Configuration.value(for: .source) {
        case "DEBUG":
            prefix = "debug"
        case "STABLE":
            prefix = "stable"
        case "APP_STORE":
            prefix = "appstore"
        default:
            prefix = "beta"
        }
        return prefix
    }
    
    public static var version: String {
        var suffix: String = ""
        
        suffix = Configuration.value(for: .source) ?? "DEBUG"
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? ""
        return "\(shortVersion) \(suffix)"
    }
    
}



