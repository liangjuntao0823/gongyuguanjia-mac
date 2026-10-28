import Foundation
import CryptoKit
import CoreImage
import AVFoundation
import UniformTypeIdentifiers
import AppKit

// MARK: - 钥匙串键（与 iOS 版保持一致，方便同机迁移）

enum KeychainKey {
    static let bucket = "cos.bucket"
    static let region = "cos.region"
    static let secretId = "cos.secretId"
    static let secretKey = "cos.secretKey"
    static let customDomain = "cos.customDomain"
    static let shareName = "share.name"
    static let sharePhone = "share.phone"
    static let adminPassword = "cloud.adminPassword"
}

// MARK: - 分享模式

enum ShareMode: String {
    case masked = "masked"
    case full = "full"

    var pageSuffix: String {
        switch self {
        case .masked: return "share"
        case .full: return "share-full"
        }
    }

    var modeLabel: String {
        switch self {
        case .masked: return "脱敏版"
        case .full: return "完整版"
        }
    }
}

// MARK: - 分享数据值类型（Task 内安全传递 + 缓存 JSON 编解码）

struct ShareMediaFile: Hashable, Codable {
    let name: String
    let kind: String
}

struct ShareHouseInfo: Equatable, Codable {
    let displayRoomNo: String
    let towerLabel: String
    let layout: String
    let statusLabel: String
    let priceText: String
    let landlord: String
    let password: String
    let remark: String
    let name: String?
    let phone: String?
}

struct ShareCollectionItem: Hashable, Codable {
    let roomKey: String
    let displayRoomNo: String
    let towerLabel: String
    let layout: String
    let statusLabel: String
    let priceText: String
    let landlord: String
    let password: String
    let remark: String
    let mediaFiles: [ShareMediaFile]
}

// MARK: - 名片微信二维码（本地存储：DataRoot.qrcodeURL）

enum QrcodeStore {
    static let fileName = "qrcode.png"

    static var fileURL: URL { DataRoot.qrcodeURL }

    @discardableResult
    static func save(_ data: Data) -> Bool {
        do {
            try data.write(to: fileURL)
            return true
        } catch { return false }
    }

    static func loadData() -> Data? {
        FileManager.default.fileExists(atPath: fileURL.path) ? try? Data(contentsOf: fileURL) : nil
    }

    static func exists() -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - COS 配置

struct CosConfig {
    let bucket: String
    let region: String
    let secretId: String
    let secretKey: String
    let customDomain: String

    var isValid: Bool {
        !bucket.isEmpty && !region.isEmpty && !secretId.isEmpty && !secretKey.isEmpty
    }

    static func load() -> CosConfig? {
        let trimSet = CharacterSet.whitespacesAndNewlines
        let bucket = (KeychainStore.load(KeychainKey.bucket) ?? "").trimmingCharacters(in: trimSet)
        let region = (KeychainStore.load(KeychainKey.region) ?? "").trimmingCharacters(in: trimSet)
        let secretId = (KeychainStore.load(KeychainKey.secretId) ?? "").trimmingCharacters(in: trimSet)
        let secretKey = (KeychainStore.load(KeychainKey.secretKey) ?? "").trimmingCharacters(in: trimSet)
        let customDomain = (KeychainStore.load(KeychainKey.customDomain) ?? "").trimmingCharacters(in: trimSet)
        let config = CosConfig(bucket: bucket, region: region, secretId: secretId, secretKey: secretKey, customDomain: customDomain)
        return config.isValid ? config : nil
    }

    static func save(_ config: CosConfig) {
        _ = KeychainStore.save(config.bucket, for: KeychainKey.bucket)
        _ = KeychainStore.save(config.region, for: KeychainKey.region)
        _ = KeychainStore.save(config.secretId, for: KeychainKey.secretId)
        _ = KeychainStore.save(config.secretKey, for: KeychainKey.secretKey)
        _ = KeychainStore.save(config.customDomain, for: KeychainKey.customDomain)
    }

    static func clear() {
        for key in [KeychainKey.bucket, KeychainKey.region, KeychainKey.secretId, KeychainKey.secretKey, KeychainKey.customDomain] {
            KeychainStore.delete(key)
        }
    }

    static func exists() -> Bool { load() != nil }
}

// MARK: - 腾讯云 COS V5 预签名（HMAC-SHA1，零第三方依赖，与 iOS 版算法完全一致）

enum CosUploader {

    static let shareLinkExpires: Int = 3650 * 86400

    /// v1.25：HTML 模板版本号。修改 H5 模板后必须 +1（缓存校验用）
    static let htmlTemplateVersion = 5

    enum CosError: LocalizedError {
        case invalidConfig
        case missingMedia
        case customDomainMissing
        case uploadFailed(String)
        case responseInvalid

        var errorDescription: String? {
            switch self {
            case .invalidConfig:
                return "云存储配置不完整，请先在设置页填写并保存验证"
            case .missingMedia:
                return "这套房源还没有照片或视频，先编辑添加素材再分享"
            case .customDomainMissing:
                return "未填写自定义域名，分享链接会被微信识别成文件而不是卡片。请到设置页填入自定义域名并保存"
            case .uploadFailed(let msg):
                return "上传失败：" + msg
            case .responseInvalid:
                return "上传服务返回异常，请稍后重试"
            }
        }
    }

    // MARK: - Host

    /// 配置了自定义域名就用它；未配置回退 COS 默认域名（仅兜底，微信可能识别成文件）
    internal static func host(for config: CosConfig) -> String {
        var domain = config.customDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        if !domain.isEmpty {
            for prefix in ["https://", "http://"] where domain.lowercased().hasPrefix(prefix) {
                domain = String(domain.dropFirst(prefix.count))
            }
            while domain.hasSuffix("/") { domain.removeLast() }
            return domain
        }
        return "\(config.bucket).cos.\(config.region).myqcloud.com"
    }

    // MARK: - 预签名

    internal static func presignedPutURL(for path: String, contentType: String, config: CosConfig) throws -> URL {
        try presignedURL(for: path, method: "PUT", expires: 3600, headers: [("content-type", contentType)], config: config)
    }

    internal static func presignedGetURL(for path: String, expires: Int, config: CosConfig) throws -> URL {
        try presignedURL(for: path, method: "GET", expires: expires, headers: [], config: config)
    }

    internal static func presignedDeleteURL(for path: String, config: CosConfig) throws -> URL {
        try presignedURL(for: path, method: "DELETE", expires: 600, headers: [], config: config)
    }

    /// COS V5 签名（与 iOS 版逐字节一致）：
    /// HttpString = method\nrawPath\nparams\nheaders\n；签名用未编码路径，请求 URL 用编码路径
    internal static func presignedURL(for path: String, method: String, expires: Int, headers: [(String, String)], params: [(String, String)] = [], config: CosConfig) throws -> URL {
        let now = Int(Date().timeIntervalSince1970)
        let signTime = "\(now);\(now + expires)"
        let keyTime = signTime

        let hostValue = host(for: config)
        let rawPath = "/" + path
        let encodedPath = rawPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawPath

        var pairs = headers.map { (key: $0.0.lowercased(), value: urlEncode($0.1)) }
        pairs.append(("host", hostValue.lowercased()))
        pairs.sort { $0.key < $1.key }
        let headerList = pairs.map(\.key).joined(separator: ";")
        let headerValue = pairs.map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        let sortedParams = params.map { (key: $0.0.lowercased(), value: urlEncode($0.1)) }.sorted { $0.key < $1.key }
        let paramList = sortedParams.map(\.key).joined(separator: ";")
        let paramValue = sortedParams.map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        let signKey = HMAC_SHA1(key: config.secretKey, message: keyTime)
        let httpString = "\(method.lowercased())\n\(rawPath)\n\(paramValue)\n\(headerValue)\n"
        let sha1Http = SHA1(hexString: httpString)
        let stringToSign = "sha1\n\(signTime)\n\(sha1Http)\n"
        let signature = HMAC_SHA1(key: signKey, message: stringToSign)

        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = hostValue
        comps.percentEncodedPath = encodedPath
        var queryParts = sortedParams.map { "\($0.key)=\($0.value)" }
        queryParts.append("q-sign-algorithm=sha1&q-ak=\(config.secretId)&q-sign-time=\(signTime)&q-key-time=\(keyTime)&q-header-list=\(headerList)&q-url-param-list=\(paramList)&q-signature=\(signature)")
        comps.percentEncodedQuery = queryParts.joined(separator: "&")
        guard let url = comps.url else { throw CosError.invalidConfig }
        return url
    }

    /// RFC 3986 严格百分号编码（保留 A-Z a-z 0-9 - _ . ~）
    private static func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")) ?? s
    }

    // MARK: - 加密原语

    private static func HMAC_SHA1(key: String, message: String) -> String {
        let keyData = Data(key.utf8)
        let msgData = Data(message.utf8)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: msgData, using: SymmetricKey(data: keyData))
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    private static func SHA1(hexString: String) -> String {
        let data = Data(hexString.utf8)
        return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 上传 / 下载 / 列表 / 删除

    internal static func upload(data: Data, to remotePath: String, contentType: String, config: CosConfig) async throws {
        let url = try presignedPutURL(for: remotePath, contentType: contentType, config: config)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (respData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CosError.uploadFailed("HTTP \(code) " + extractCosError(from: respData))
        }
    }

    internal static func uploadWithProgress(data: Data, to remotePath: String, contentType: String, config: CosConfig, progress: @escaping (Double) -> Void) async throws {
        let url = try presignedPutURL(for: remotePath, contentType: contentType, config: config)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let delegate = CosUploadProgressDelegate(onProgress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (respData, response) = try await session.data(for: request)
        session.finishTasksAndInvalidate()
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CosError.uploadFailed("HTTP \(code) " + extractCosError(from: respData))
        }
    }

    /// 读取桶内对象；404 抛 CosObjectNotFoundError，其他错误上抛（绝不吞错当「云端没有」）
    static func fetchObjectData(path: String, config: CosConfig) async throws -> Data {
        let url = try presignedGetURL(for: path, expires: 300, config: config)
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse else {
            throw NSError(domain: "CosUploader", code: -1, userInfo: [NSLocalizedDescriptionKey: "读取云端对象失败: \(path)"])
        }
        if http.statusCode == 404 { throw CosObjectNotFoundError(path: path) }
        guard http.statusCode == 200 else {
            throw NSError(domain: "CosUploader", code: -1, userInfo: [NSLocalizedDescriptionKey: "读取云端对象失败: \(path)（HTTP \(http.statusCode)）"])
        }
        return data
    }

    static func remoteObjectExists(path: String, config: CosConfig) async -> Bool {
        guard let url = try? presignedURL(for: path, method: "HEAD", expires: 300, headers: [], config: config) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        guard let (_, resp) = try? await URLSession.shared.data(for: request),
              let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    static func deleteObject(path: String, config: CosConfig) async throws {
        let url = try presignedDeleteURL(for: path, config: config)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        let (_, resp) = try await URLSession.shared.data(for: request)
        if let http = resp as? HTTPURLResponse, http.statusCode == 404 {
            return // 对象本就不存在，视为删除成功
        }
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw CosError.uploadFailed("删除失败 HTTP \(code)")
        }
    }

    /// ListObjectsV2（前缀 + 分页）
    static func listObjects(prefix: String, delimiter: String? = nil, config: CosConfig) async throws -> [(name: String, size: Int64, date: Date)] {
        var result: [(name: String, size: Int64, date: Date)] = []
        var continuationToken: String?
        repeat {
            var params: [(String, String)] = [("list-type", "2"), ("prefix", prefix), ("encoding-type", "url")]
            if let delimiter = delimiter { params.append(("delimiter", delimiter)) }
            if let token = continuationToken { params.append(("continuation-token", token)) }
            let url = try presignedURL(for: "", method: "GET", expires: 300, headers: [], params: params, config: config)
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw CosError.uploadFailed("云端列表获取失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）" + extractCosError(from: data))
            }
            guard let xml = String(data: data, encoding: .utf8) else { break }
            let blocks = extractContentsBlocks(from: xml)
            for block in blocks {
                guard let key = tagValue("Key", in: block) else { continue }
                let size = Int64(tagValue("Size", in: block) ?? "0") ?? 0
                let date = parseCOSDate(tagValue("LastModified", in: block))
                result.append((name: percentDecode(key), size: size, date: date))
            }
            if let truncated = tagValue("IsTruncated", in: xml), truncated == "true",
               let next = tagValue("NextContinuationToken", in: xml), !next.isEmpty {
                continuationToken = percentDecode(next)
            } else {
                continuationToken = nil
            }
        } while continuationToken != nil
        return result
    }

    private static func extractContentsBlocks(from xml: String) -> [String] {
        var blocks: [String] = []
        var rest = xml[...]
        while let start = rest.range(of: "<Contents>"), let end = rest[start.upperBound...].range(of: "</Contents>") {
            blocks.append(String(rest[start.upperBound..<end.lowerBound]))
            rest = rest[end.upperBound...]
        }
        return blocks
    }

    /// 目录式列出（对齐 iOS fetchAll：listObjects delimiter 目录式）
    /// 只返回 CommonPrefixes 子目录前缀（如 "h/2334上/"），不列对象/媒体文件
    static func listDirectoryPrefixes(prefix: String, delimiter: String, config: CosConfig) async throws -> [String] {
        var result: [String] = []
        var continuationToken: String?
        repeat {
            var params: [(String, String)] = [("list-type", "2"), ("prefix", prefix), ("encoding-type", "url")]
            params.append(("delimiter", delimiter))
            if let token = continuationToken { params.append(("continuation-token", token)) }
            let url = try presignedURL(for: "", method: "GET", expires: 300, headers: [], params: params, config: config)
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw CosError.uploadFailed("云端目录列表获取失败（HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)）" + extractCosError(from: data))
            }
            guard let xml = String(data: data, encoding: .utf8) else { break }
            for block in extractCommonPrefixBlocks(from: xml) {
                if let p = tagValue("Prefix", in: block), !p.isEmpty, p != prefix {
                    result.append(percentDecode(p))
                }
            }
            if let truncated = tagValue("IsTruncated", in: xml), truncated == "true",
               let next = tagValue("NextContinuationToken", in: xml), !next.isEmpty {
                continuationToken = percentDecode(next)
            } else { break }
        } while true
        return result
    }

    private static func extractCommonPrefixBlocks(from xml: String) -> [String] {
        var blocks: [String] = []
        var rest = xml[...]
        while let start = rest.range(of: "<CommonPrefixes>"), let end = rest[start.upperBound...].range(of: "</CommonPrefixes>") {
            blocks.append(String(rest[start.upperBound..<end.lowerBound]))
            rest = rest[end.upperBound...]
        }
        return blocks
    }

    private static func tagValue(_ tag: String, in xml: String) -> String? {
        guard let start = xml.range(of: "<\(tag)>")?.upperBound,
              let end = xml[start...].range(of: "</\(tag)>")?.lowerBound else { return nil }
        return String(xml[start..<end])
    }

    private static func parseCOSDate(_ text: String?) -> Date {
        guard let text = text, !text.isEmpty else { return .distantPast }
        let iso = ISO8601DateFormatter()
        return iso.date(from: text) ?? .distantPast
    }

    private static func percentDecode(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }

    /// 从 COS 错误响应 XML 提取错误信息
    internal static func extractCosError(from data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else { return "" }
        func value(of tag: String) -> String? {
            guard let start = text.range(of: "<\(tag)>")?.upperBound,
                  let end = text[start...].range(of: "</\(tag)>")?.lowerBound else { return nil }
            return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let code = value(of: "Code") ?? ""
        let message = value(of: "Message") ?? ""
        if code.isEmpty { return "" }
        return message.isEmpty ? "错误码 \(code)" : "错误码 \(code)：\(message)"
    }

    // MARK: - 连接验证

    /// 验证配置：尝试 GET 桶根（空 key）200 即通过
    static func verifyConnection(config: CosConfig) async throws -> String {
        let url = try presignedURL(for: "", method: "GET", expires: 300, headers: [], params: [("list-type", "2"), ("max-keys", "1")], config: config)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw CosError.uploadFailed("HTTP \(code) " + extractCosError(from: data))
        }
        return "连接成功：\(host(for: config))"
    }

    // MARK: - 云函数

    /// 调用云函数（GET 带参），返回 Data
    static func cloudCall(params: [(String, String)], config: CosConfig? = nil) async throws -> Data {
        let base = CloudConfig.functionURL
        guard !base.isEmpty, let baseURL = URL(string: base) else {
            throw NSError(domain: "Cloud", code: -1, userInfo: [NSLocalizedDescriptionKey: "未配置云函数地址"])
        }
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var items = params.map { URLQueryItem(name: $0.0, value: $0.1) }
        if let existing = comps.queryItems { items = existing + items }
        comps.queryItems = items
        guard let url = comps.url else {
            throw NSError(domain: "Cloud", code: -1, userInfo: [NSLocalizedDescriptionKey: "云函数地址无效"])
        }
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "Cloud", code: -1, userInfo: [NSLocalizedDescriptionKey: "云函数请求失败（HTTP \(code)）"])
        }
        return data
    }

    /// 云函数通用 JSON 响应 { ok, ... }
    static func cloudJSON(params: [(String, String)]) async throws -> [String: Any] {
        let data = try await cloudCall(params: params)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Cloud", code: -1, userInfo: [NSLocalizedDescriptionKey: "云函数返回格式异常"])
        }
        return obj
    }

    // MARK: - 媒体上传（房源）

    /// 上传房源媒体：h/<roomKey>/<fileName>（媒体永远进共享区，与 iOS 互通）
    /// v1.2 修复：本地路径带 roomKey（Mac 独有 bug）+ 桶内幂等跳过（防重复刷流量）
    static func uploadHouseMedia(fileName: String, kind: String, roomKey: String, config: CosConfig, compress: Bool) async throws {
        let localURL = MediaStore.fileURL(fileName: fileName, roomKey: roomKey)
        guard FileManager.default.fileExists(atPath: localURL.path) else {
            throw CosError.uploadFailed("本地文件不存在：\(fileName)")
        }
        let contentType = mimeType(for: kind, name: fileName)
        // 视频统一转 mp4（安卓/微信可播），云端路径 .mp4
        let remoteName = (kind == "video") ? cloudVideoName(for: fileName) : fileName
        let remotePath = "h/\(roomKey)/\(remoteName)"
        // 幂等跳过：桶内已有同名对象不再重复上传（与 iOS 一致）
        if await remoteObjectExists(path: remotePath, config: config) { return }

        if kind == "video" {
            // 压缩开关
            if compress {
                if let mp4 = await compressedVideoData(from: localURL) {
                    try await upload(data: mp4, to: remotePath, contentType: "video/mp4", config: config)
                } else {
                    try await uploadFileAsIs(localURL: localURL, to: remotePath, contentType: contentType, config: config)
                }
            } else {
                // 不压缩：仍转 mp4 封装（保兼容），用 passthrough
                if let mp4 = await mp4ContainerData(from: localURL) {
                    try await upload(data: mp4, to: remotePath, contentType: "video/mp4", config: config)
                } else {
                    try await uploadFileAsIs(localURL: localURL, to: remotePath, contentType: contentType, config: config)
                }
            }
            // 视频首帧图（分享页封面用）：与 iOS 一致放用户区 users/<用户名>/shares/<roomKey>/
            if let thumb = makeVideoThumbJPEG(from: localURL) {
                let thumbPath = "\(CloudUser.sharePagePrefix)\(roomKey)/\(cloudVideoName(for: fileName)).vthumb.jpg"
                try? await upload(data: thumb, to: thumbPath, contentType: "image/jpeg", config: config)
            }
        } else {
            if compress, let jpeg = compressedImageData(from: localURL) {
                try await upload(data: jpeg, to: remotePath, contentType: "image/jpeg", config: config)
            } else {
                try await uploadFileAsIs(localURL: localURL, to: remotePath, contentType: contentType, config: config)
            }
        }
    }

    private static func uploadFileAsIs(localURL: URL, to remotePath: String, contentType: String, config: CosConfig) async throws {
        let data = try Data(contentsOf: localURL)
        try await upload(data: data, to: remotePath, contentType: contentType, config: config)
    }

    // MARK: - 云函数配置 / 用户 / 操作记录

    static func mimeType(for kind: String, name: String) -> String {
        if kind == "video" { return "video/mp4" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        default: return "image/jpeg"
        }
    }

    /// 视频云端文件名：统一 .mp4
    static func cloudVideoName(for localName: String) -> String {
        let ns = localName as NSString
        let base = ns.deletingPathExtension
        return "\(base).mp4"
    }

    // MARK: - 图片处理（CGImage，macOS）

    /// 等比缩放 + JPEG 压缩
    static func scaledJPEGData(from data: Data, maxSide: CGFloat, quality: CGFloat) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard w > 0, h > 0 else { return nil }
        let scale = min(maxSide / max(w, h), 1)
        let targetW = max(Int(w * scale), 1), targetH = max(Int(h * scale), 1)
        guard let ctx = CGContext(data: nil, width: targetW, height: targetH, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        guard let out = ctx.makeImage() else { return nil }
        let dest = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(dest as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dst, out, opts as CFDictionary)
        guard CGImageDestinationFinalize(dst) else { return nil }
        return dest as Data
    }

    /// 本地图片文件压缩（压缩上传用）
    static func compressedImageData(from url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return scaledJPEGData(from: data, maxSide: 1600, quality: 0.82)
    }

    /// 微信 og:image 压缩封面：最长边 400px、JPEG q0.72
    private static func makeCoverJPEG(from url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return scaledJPEGData(from: data, maxSide: 400, quality: 0.72)
    }

    /// 名片二维码压缩图：居中裁剪正方形 → 长边 400px、JPEG q0.85
    static func makeQRCodeJPEG() -> Data? {
        guard let data = QrcodeStore.loadData(),
              let src = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let side = min(w, h)
        guard side > 0 else { return nil }
        // 居中裁剪正方形
        let x = (w - side) / 2, y = (h - side) / 2
        let cropRect = CGRect(x: x, y: y, width: side, height: side)
        guard let cropped = image.cropping(to: cropRect) else { return nil }
        // 缩到 400
        let scale = min(400 / side, 1)
        let targetW = max(Int(side * scale), 1), targetH = max(Int(side * scale), 1)
        guard let ctx = CGContext(data: nil, width: targetW, height: targetH, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        guard let out = ctx.makeImage() else { return nil }
        let dest = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(dest as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, out, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(dst) else { return nil }
        return dest as Data
    }

    // MARK: - 视频处理（AVFoundation，macOS 同样可用）

    /// 视频首帧 JPEG（最长边 480，q0.7）
    static func makeVideoThumbJPEG(from url: URL) -> Data? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 480, height: 480)
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        guard let cg = try? gen.copyCGImage(at: time, actualTime: nil) else { return nil }
        let dest = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(dest as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, cg, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(dst) else { return nil }
        return dest as Data
    }

    /// 等待 AVAssetExportSession 导出完成（兼容 macOS 14 部署目标）
    private static func awaitExport(_ session: AVAssetExportSession) async -> Bool {
        await withCheckedContinuation { cont in
            session.exportAsynchronously {
                cont.resume(returning: session.status == .completed)
            }
        }
    }

    /// 视频压缩转 mp4（MediumQuality，慢但省流量）
    static func compressedVideoData(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) else { return nil }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: out)
        session.outputURL = out
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        let ok = await awaitExport(session)
        defer { try? FileManager.default.removeItem(at: out) }
        guard ok else { return nil }
        return try? Data(contentsOf: out)
    }

    /// 不压缩：转封装 mp4（passthrough，快速、不损画质）
    static func mp4ContainerData(from url: URL) async -> Data? {
        let ext = (url.path as NSString).pathExtension.lowercased()
        if ext == "mp4" { return try? Data(contentsOf: url) }
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { return nil }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: out)
        session.outputURL = out
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        let ok = await awaitExport(session)
        defer { try? FileManager.default.removeItem(at: out) }
        guard ok else { return nil }
        return try? Data(contentsOf: out)
    }

    // MARK: - 分享记录（云端，按用户名隔离）

    static func appendShareRecord(roomKey: String, displayRoomNo: String, mode: ShareMode, url: String, config: CosConfig) async throws {
        let path = CloudUser.shareRecordPath
        var records: [[String: String]] = []
        if let data = try? await fetchObjectData(path: path, config: config),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            records = arr
        } else if let data = try? await fetchObjectData(path: CloudUser.legacyShareRecordPath, config: config),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            records = arr
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        df.locale = Locale(identifier: "zh_CN")
        records.append([
            "roomKey": roomKey,
            "room": displayRoomNo,
            "mode": mode.modeLabel,
            "time": df.string(from: Date()),
            "url": url
        ])
        if records.count > 500 { records = Array(records.suffix(500)) }
        guard let json = try? JSONSerialization.data(withJSONObject: records) else { return }
        try await upload(data: json, to: path, contentType: "application/json", config: config)
        // 旧路径清理
        if let legacyURL = try? presignedURL(for: CloudUser.legacyShareRecordPath, method: "DELETE", expires: 600, headers: [], config: config) {
            var req = URLRequest(url: legacyURL)
            req.httpMethod = "DELETE"
            if let (_, resp) = try? await URLSession.shared.data(for: req) {
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 || http.statusCode == 204 || http.statusCode == 404 {
                    // 已清理
                }
            }
        }
    }

    // MARK: - 工具

    static func safeFileName(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" { out.append(ch) }
            else if ch == " " || ch == "." || ch == "/" || ch == ":" || ch == "," || ch == "，" { out.append("-") }
        }
        return out.isEmpty ? "house" : out
    }

    static func shareTimeTag() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// 户型标题：户型含「上/下」时不再重复拼接房号后缀
    static func layoutTitle(_ layout: String, roomNo: String) -> String {
        if layout.contains("上") || layout.contains("下") { return layout }
        return layout + roomNo
    }

    /// 清理本地分享缓存（不删云端，旧 H5 链接会失效，新生成页不受影响）
    static func clearShareCache() {
        let fm = FileManager.default
        if let names = try? fm.contentsOfDirectory(atPath: DataRoot.shareCacheDirectory.path) {
            for name in names {
                try? fm.removeItem(at: DataRoot.shareCacheDirectory.appendingPathComponent(name))
            }
        }
        CrashLogCollector.record("分享缓存已清理")
    }
}

// MARK: - 对象不存在错误（fetch 判空用）

struct CosObjectNotFoundError: Error, LocalizedError {
    let path: String
    var errorDescription: String? { "云端对象不存在: \(path)" }
}

// MARK: - 上传进度 Delegate

private final class CosUploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: (Double) -> Void
    var onCompletion: ((Error?) -> Void)?
    private var lastReported: Double = -1

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let p = min(Double(totalBytesSent) / Double(totalBytesExpectedToSend), 1.0)
        if p - lastReported >= 0.01 || p >= 1.0 {
            lastReported = p
            onProgress(p)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onCompletion?(error)
    }
}

// MARK: - 水印设置

enum WatermarkPosition: String, CaseIterable, Codable {
    case bottomRight, topLeft, topRight, bottomLeft
    var label: String {
        switch self {
        case .bottomRight: return "右下"
        case .topLeft: return "左上"
        case .topRight: return "右上"
        case .bottomLeft: return "左下"
        }
    }
}

struct WatermarkSettings: Codable, Equatable {
    var enabled: Bool
    var text: String
    var fontSize: Double
    var opacity: Double
    var position: WatermarkPosition
    var offsetX: Double
    var offsetY: Double

    static let defaultText = "梁涛-13288251132"
    static let `default` = WatermarkSettings(enabled: true, text: defaultText, fontSize: 14, opacity: 0.5, position: .bottomRight, offsetX: 12, offsetY: 12)
}

enum WatermarkSettingsStore {
    private static let key = "watermark.settings.v1"
    static var current: WatermarkSettings {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let s = try? JSONDecoder().decode(WatermarkSettings.self, from: data) else { return .default }
            return s
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
    static func resetToDefault() { current = .default }
}

extension CosUploader {
    static func watermarkHash(_ wm: WatermarkSettings) -> String {
        let s = "\(wm.enabled)|\(wm.text)|\(wm.fontSize)|\(wm.opacity)|\(wm.position.rawValue)|\(wm.offsetX)|\(wm.offsetY)"
        var h: UInt64 = 5381
        for b in s.utf8 { h = (h &* 33) ^ UInt64(b) }
        return String(h)
    }

    static func watermarkOverlayHTML(_ wm: WatermarkSettings) -> String {
        guard wm.enabled, !wm.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        let x = max(0, wm.offsetX)
        let y = max(0, wm.offsetY)
        let placement: String
        switch wm.position {
        case .bottomRight: placement = "right:\(x)px;bottom:\(y)px;"
        case .bottomLeft: placement = "left:\(x)px;bottom:\(y)px;"
        case .topRight: placement = "right:\(x)px;top:\(y)px;"
        case .topLeft: placement = "left:\(x)px;top:\(y)px;"
        }
        return "<div class=\"wm\" style=\"position:absolute;\(placement)color:rgba(255,255,255,\(wm.opacity));font-size:\(wm.fontSize)px;font-weight:500;line-height:1;text-shadow:0 1px 2px rgba(0,0,0,.35);pointer-events:none;user-select:none;z-index:2;max-width:70%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;\">\(escapeHTML(wm.text))</div>"
    }

    /// H5 埋点脚本（静默收集，GET 云函数，按用户名分文件统计）
    static func cloudTrackScript(room: String, mode: String) -> String {
        let url = CloudConfig.functionURL
        let roomEsc = escapeHTML(room)
        let modeEsc = escapeHTML(mode)
        let unameEsc = escapeHTML(CloudUser.username)
        return "<script>(function(){try{var u='\(url)';if(!u||u.indexOf('http')!==0)return;var k='gy_tk_'+encodeURIComponent('\(roomEsc)')+'_'+encodeURIComponent('\(modeEsc)');var now=Date.now(),last=0;try{last=parseInt(localStorage.getItem(k)||'0',10)||0;}catch(e){}if(now-last<30000)return;try{localStorage.setItem(k,String(now));}catch(e){}var r=(document.referrer||'').slice(0,120);var img=new Image();img.src=u+'?act=track&room='+encodeURIComponent('\(roomEsc)')+'&mode='+encodeURIComponent('\(modeEsc)')+'&ref='+encodeURIComponent(r)+'&t='+now+'&uname='+encodeURIComponent('\(unameEsc)');}catch(e){}})();</script>"
    }
}

// MARK: - 云函数配置

enum CloudConfig {
    static var functionURL: String {
        get {
            if let s = UserDefaults.standard.string(forKey: "cloud.functionURL"), !s.isEmpty { return s }
            if let s = KeychainStore.load("cloud.functionURL"), !s.isEmpty { return s }
            return ""
        }
        set { UserDefaults.standard.set(newValue, forKey: "cloud.functionURL") }
    }

    static func clearFunctionURL() {
        UserDefaults.standard.removeObject(forKey: "cloud.functionURL")
        _ = KeychainStore.save("", for: "cloud.functionURL")
    }

    static var adminPassword: String {
        get {
            if let s = KeychainStore.load(KeychainKey.adminPassword), !s.isEmpty { return s }
            if let s = UserDefaults.standard.string(forKey: "cloud.adminPassword"), !s.isEmpty {
                _ = KeychainStore.save(s, for: KeychainKey.adminPassword)
                return s
            }
            return "12345678"
        }
        set { _ = KeychainStore.save(newValue, for: KeychainKey.adminPassword) }
    }

    static var passwordHash: String {
        let data = Data(adminPassword.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 用户隔离

enum CloudUser {
    private static let key = "cloud.username"
    static var username: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static var displayName: String { username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未设置" : username }
    static var safeName: String {
        let t = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "未设置" : t
    }
    static var userRootPrefix: String { "users/\(safeName)/" }
    static var sharePagePrefix: String { "users/\(safeName)/shares/" }
    static var qrPath: String { "users/\(safeName)/qrcode.jpg" }
    static var backupPrefix: String { "users/\(safeName)/backups/" }
    static var shareRecordPath: String { "users/\(safeName)/share_records.json" }
    static var legacyShareRecordPath: String { "h/_share_records_\(safeName).json" }
    static var mediaMirrorPrefix: String { "users/\(safeName)/media/" }
    static var legacyMediaMirrorPrefix: String { "backups/media/" }
    /// 公开选房页壳路径：users/<用户名>/rooms/index.html
    static var roomsIndexPath: String { "users/\(safeName)/rooms/index.html" }
}

// MARK: - 云端操作记录

struct CloudOpEntry: Codable, Identifiable, Hashable {
    var id: String { "\(t)|\(op)|\(room)|\(user)|\(detail)" }
    let t: String
    let op: String
    let room: String
    let user: String
    let detail: String
}

struct CloudOpsResponse: Codable {
    let ok: Bool
    let records: [CloudOpEntry]
}

enum CloudOps {
    static var isConfigured: Bool {
        !CloudConfig.functionURL.isEmpty && !CloudConfig.passwordHash.isEmpty
    }
    private static var baseURL: URL? { URL(string: CloudConfig.functionURL) }

    static func log(category: String, action: String, result: String, detail: String, room: String = "") {
        guard isConfigured, let base = baseURL else { return }
        let op = "\(category)·\(action)·\(result)"
        var q = URLComponents()
        q.queryItems = [
            .init(name: "act", value: "logOp"),
            .init(name: "k", value: CloudConfig.passwordHash),
            .init(name: "op", value: op),
            .init(name: "room", value: room),
            .init(name: "uname", value: CloudUser.username),
            .init(name: "detail", value: detail),
        ]
        guard let query = q.percentEncodedQuery, let url = URL(string: base.absoluteString + "?" + query) else { return }
        URLSession.shared.dataTask(with: url).resume()
    }

    static func fetch(completion: @escaping ([CloudOpEntry]) -> Void) {
        guard isConfigured, let base = baseURL else { completion([]); return }
        let u = CloudUser.username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "\(base.absoluteString)?act=ops&k=\(CloudConfig.passwordHash)&u=\(u)") else { completion([]); return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data, let obj = try? JSONDecoder().decode(CloudOpsResponse.self, from: data), obj.ok else { completion([]); return }
            completion(obj.records)
        }.resume()
    }

    static func delete(_ e: CloudOpEntry, completion: (() -> Void)? = nil) {
        guard isConfigured, let base = baseURL else { completion?(); return }
        let u = CloudUser.username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var q = URLComponents()
        q.queryItems = [
            .init(name: "act", value: "delOp"), .init(name: "k", value: CloudConfig.passwordHash), .init(name: "u", value: u),
            .init(name: "t", value: e.t), .init(name: "op", value: e.op), .init(name: "room", value: e.room),
            .init(name: "user", value: e.user), .init(name: "detail", value: e.detail),
        ]
        guard let query = q.percentEncodedQuery, let url = URL(string: base.absoluteString + "?" + query) else { completion?(); return }
        URLSession.shared.dataTask(with: url) { _, _, _ in DispatchQueue.main.async { completion?() } }.resume()
    }
}

// MARK: - 云端房源账本 DTO（一房一文件 h/<房号>/info.json）

struct CloudHouseRecord: Codable, Identifiable {
    var id: String { roomKey }
    var roomKey: String
    var roomNo: String
    var tower: Int
    var landlord: String
    var layout: String
    var price: Int
    var password: String
    var remark: String
    var status: String
    var updatedAt: Date
    var updatedBy: String
    var mediaNames: [String]
}

// MARK: - 分享 H5 完整流程（单房）

extension CosUploader {

    /// 单房分享：生成/复用 H5 页面（含媒体增量上传）。返回可复制链接
    static func shareCard(mediaFiles: [ShareMediaFile], roomKey: String, info: ShareHouseInfo, mode: ShareMode, config: CosConfig, progress: ((Double) -> Void)? = nil) async throws -> String {
        guard !mediaFiles.isEmpty else { throw CosError.missingMedia }
        guard !config.customDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CosError.customDomainMissing }

        // 媒体排序：视频置顶
        let videos = mediaFiles.filter { $0.kind == "video" }
        let images = mediaFiles.filter { $0.kind == "image" }
        let sortedMedia = videos + images

        // 1) 检查云端媒体是否齐全（缺才上传，增量）
        var missing: [ShareMediaFile] = []
        for m in sortedMedia {
            let remoteName = (m.kind == "video") ? cloudVideoName(for: m.name) : m.name
            let exists = await remoteObjectExists(path: "h/\(roomKey)/\(remoteName)", config: config)
            if !exists { missing.append(m) }
        }

        var totalTasks = missing.count + 1
        var doneTasks = 0
        func bump() {
            doneTasks += 1
            progress?(min(Double(doneTasks) / Double(max(totalTasks, 1)), 1.0))
        }

        // 2) 上传缺失媒体
        for m in missing {
            try await uploadHouseMedia(fileName: m.name, kind: m.kind, roomKey: roomKey, config: config, compress: MediaSettingsStore.compressUpload)
            bump()
        }

        // 3) 组装签名 URL 列表
        var videoTags: [String] = []
        var imageURLs: [String] = []
        for m in sortedMedia {
            if m.kind == "video" {
                videoTags.append((try presignedGetURL(for: "h/\(roomKey)/\(cloudVideoName(for: m.name))", expires: shareLinkExpires, config: config)).absoluteString)
            } else {
                imageURLs.append((try presignedGetURL(for: "h/\(roomKey)/\(m.name)", expires: shareLinkExpires, config: config)).absoluteString)
            }
        }

        // 4) 封面：视频首帧 / 第一张图
        var coverSrc = ""
        if let firstVideo = videos.first {
            let vthumb = "\(CloudUser.sharePagePrefix)\(roomKey)/\(cloudVideoName(for: firstVideo.name)).vthumb.jpg"
            if let u = try? presignedGetURL(for: vthumb, expires: shareLinkExpires, config: config) {
                coverSrc = u.absoluteString
            }
        }
        if coverSrc.isEmpty, let firstImage = images.first {
            coverSrc = (try presignedGetURL(for: "h/\(roomKey)/\(firstImage.name)", expires: shareLinkExpires, config: config)).absoluteString
        }

        // 5) 名片信息（设置页可编辑）
        let name = ShareNameStore.displayName
        let phone = ShareNameStore.displayPhone

        // 6) 页面路径：users/<用户名>/shares/<房号>/<suffix>
        let pagePath = "\(CloudUser.sharePagePrefix)\(roomKey)/\(mode.pageSuffix)"

        // 7) 封面/二维码上传（名片二维码固定路径覆盖写 → 换二维码旧链接自动更新）
        var qrSrc = ""
        if let qrJPEG = makeQRCodeJPEG() {
            try? await upload(data: qrJPEG, to: CloudUser.qrPath, contentType: "image/jpeg", config: config)
            qrSrc = (try presignedGetURL(for: CloudUser.qrPath, expires: shareLinkExpires, config: config)).absoluteString
        }

        // 8) 组装 HTML
        let title: String
        let desc: String
        var html: String
        let track = cloudTrackScript(room: roomKey, mode: mode.rawValue)
        let wm = watermarkOverlayHTML(WatermarkSettingsStore.current)
        let shareURL = (try presignedGetURL(for: pagePath, expires: shareLinkExpires, config: config)).absoluteString

        switch mode {
        case .masked:
            title = layoutTitle(info.layout, roomNo: info.displayRoomNo)
            desc = "\(info.towerLabel)\(info.displayRoomNo) · \(info.statusLabel) · 月租\(info.priceText)"
            html = buildMaskedHTML(title: title, desc: desc, name: name, phone: phone,
                                   videoTags: videoTags, imageURLs: imageURLs, coverSrc: coverSrc,
                                   qrSrc: qrSrc, shareLink: shareURL, wm: wm, trackScript: track)
        case .full:
            title = layoutTitle(info.layout, roomNo: info.displayRoomNo)
            desc = "\(info.towerLabel)\(info.displayRoomNo) · \(info.statusLabel) · 月租\(info.priceText) · 房东\(info.landlord)"
            html = buildFullHTML(title: title, desc: desc, info: info, name: name, phone: phone,
                                 videoTags: videoTags, imageURLs: imageURLs, coverSrc: coverSrc,
                                 qrSrc: qrSrc, shareLink: shareURL, wm: wm, trackScript: track)
        }

        // 9) 上传页面（内容与云端一致则跳过，避免无谓重传——对齐 iOS 分享缓存语义）
        // 签名链接每次生成时间戳不同，比较前归一化 shareLink 占位
        let normHTML = html.replacingOccurrences(of: shareURL, with: "<LINK>")
        let normExisting: String? = {
            guard let data = try? await fetchObjectData(path: pagePath, config: config) else { return nil }
            return String(data: data, encoding: .utf8)?.replacingOccurrences(of: shareURL, with: "<LINK>")
        }()
        if normExisting == normHTML {
            // 页面无变化：零上传，仅复用
        } else {
            try await upload(data: Data(html.utf8), to: pagePath, contentType: "text/html", config: config)
        }

        // 10) 分享记录
        try? await appendShareRecord(roomKey: roomKey, displayRoomNo: info.displayRoomNo, mode: mode, url: shareURL, config: config)

        progress?(1.0)
        return shareURL
    }

    // MARK: 合集分享（多选 N 套房源 → 一个合集 H5，对齐 iOS 合集卡片）

    static func shareCollection(rooms: [ShareCollectionItem], config: CosConfig,
                                progress: ((Double) -> Void)? = nil) async throws -> String {
        guard !rooms.isEmpty else { throw CosError.missingMedia }
        guard !config.customDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CosError.customDomainMissing }

        // 1) 逐间上传缺失媒体（增量），并组装签名 URL
        var prepared: [PreparedRoom] = []
        var totalTasks = 0
        for room in rooms { totalTasks += room.mediaFiles.count }
        totalTasks = max(totalTasks, 1)
        var doneTasks = 0
        func bump() {
            doneTasks += 1
            progress?(min(Double(doneTasks) / Double(totalTasks), 1.0))
        }

        for room in rooms {
            let videos = room.mediaFiles.filter { $0.kind == "video" }
            let images = room.mediaFiles.filter { $0.kind == "image" }
            let sortedMedia = videos + images
            for m in sortedMedia {
                let remoteName = (m.kind == "video") ? cloudVideoName(for: m.name) : m.name
                let exists = await remoteObjectExists(path: "h/\(room.roomKey)/\(remoteName)", config: config)
                if !exists {
                    try await uploadHouseMedia(fileName: m.name, kind: m.kind, roomKey: room.roomKey,
                                               config: config, compress: MediaSettingsStore.compressUpload)
                }
                bump()
            }
            var videoTags: [String] = []
            var imageURLs: [String] = []
            for m in sortedMedia {
                if m.kind == "video" {
                    videoTags.append((try presignedGetURL(for: "h/\(room.roomKey)/\(cloudVideoName(for: m.name))", expires: shareLinkExpires, config: config)).absoluteString)
                } else {
                    imageURLs.append((try presignedGetURL(for: "h/\(room.roomKey)/\(m.name)", expires: shareLinkExpires, config: config)).absoluteString)
                }
            }
            var coverSrc = ""
            if let firstVideo = videos.first {
                let vthumb = "\(CloudUser.sharePagePrefix)\(room.roomKey)/\(cloudVideoName(for: firstVideo.name)).vthumb.jpg"
                if let u = try? presignedGetURL(for: vthumb, expires: shareLinkExpires, config: config) {
                    coverSrc = u.absoluteString
                }
            }
            if coverSrc.isEmpty, let firstImage = images.first {
                coverSrc = (try presignedGetURL(for: "h/\(room.roomKey)/\(firstImage.name)", expires: shareLinkExpires, config: config)).absoluteString
            }
            prepared.append(PreparedRoom(item: room, videoTags: videoTags, imageURLs: imageURLs, coverSrc: coverSrc))
        }

        // 2) 名片信息 + 二维码
        let name = ShareNameStore.displayName
        let phone = ShareNameStore.displayPhone
        var qrSrc = ""
        if let qrJPEG = makeQRCodeJPEG() {
            try? await upload(data: qrJPEG, to: CloudUser.qrPath, contentType: "image/jpeg", config: config)
            qrSrc = (try presignedGetURL(for: CloudUser.qrPath, expires: shareLinkExpires, config: config)).absoluteString
        }

        // 3) 页面路径：users/<用户名>/shares/collection-<时间戳>/index
        let ts = BackupTimestamp.string()
        let pagePath = "\(CloudUser.sharePagePrefix)collection-\(ts)/index"
        let shareURL = (try presignedGetURL(for: pagePath, expires: shareLinkExpires, config: config)).absoluteString

        // 4) 组装合集 HTML（封面取第一间房）
        let wm = watermarkOverlayHTML(WatermarkSettingsStore.current)
        let track = cloudTrackScript(room: rooms.first?.roomKey ?? "", mode: "collection")
        let html = buildCollectionHTML(rooms: prepared, mode: .masked, name: name, phone: phone,
                                       coverSrc: prepared.first?.coverSrc ?? "", qrSrc: qrSrc, wm: wm, trackScript: track)

        // 5) 上传页面
        try await upload(data: Data(html.utf8), to: pagePath, contentType: "text/html", config: config)
        try? await appendShareRecord(roomKey: "collection-\(ts)", displayRoomNo: "合集(\(rooms.count)套)", mode: .masked, url: shareURL, config: config)

        progress?(1.0)
        return shareURL
    }
}

// MARK: - 名片姓名电话（设置页可编辑，默认梁涛/13288251132）

enum ShareNameStore {
    static var displayName: String {
        let v = (KeychainStore.load(KeychainKey.shareName) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? "梁涛" : v
    }
    static var displayPhone: String {
        let v = (KeychainStore.load(KeychainKey.sharePhone) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? "13288251132" : v
    }
    static func save(name: String, phone: String) {
        _ = KeychainStore.save(name, for: KeychainKey.shareName)
        _ = KeychainStore.save(phone, for: KeychainKey.sharePhone)
    }
}

// MARK: - 媒体压缩上传设置（设置页开关）

enum MediaSettingsStore {
    private static let key = "media.compressUpload"
    static var compressUpload: Bool {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - H5 模板（与 iOS 版一致：脱敏版 / 完整版 / 合集 / 选房壳）

extension CosUploader {

    // MARK: 媒体块（视频置顶 + 图片单列 + 水印）

    static func mediaBlockHTML(videoTags: [String], imageURLs: [String], wm: String = "") -> String {
        var out = ""
        for (i, v) in videoTags.enumerated() {
            out += """
            <div class="vwrap" onclick="playVideo(this,'\(v)')"><div class="vthumb" style="background-image:url('\(v)')"></div><div class="vplay">▶</div><video preload="none" controlsList="nodownload" playsinline webkit-playsinline></video>\(wm)</div>
            """
            _ = i
        }
        for img in imageURLs {
            out += "<div class=\"cellwrap\" onclick=\"openImg(\(0))\" style=\"background-image:url('\(img)')\"><img class=\"cell\" src=\"\(img)\" alt=\"\" draggable=\"false\">\(wm)</div>"
        }
        return out
    }

    // MARK: 二维码栏

    static func qrColumnHTML(qrSrc: String) -> String {
        guard !qrSrc.isEmpty else { return "" }
        return """
        <div class="qr-col"><img class="qr" src="\(qrSrc)" alt="二维码" draggable="false"><div class="qr-tip">长按二维码加我好友</div></div>
        """
    }

    // MARK: 脱敏版

    static func buildMaskedHTML(title: String, desc: String, name: String, phone: String, videoTags: [String], imageURLs: [String], coverSrc: String, qrSrc: String, shareLink: String, wm: String = "", trackScript: String = "") -> String {
        let mediaBlock = mediaBlockHTML(videoTags: videoTags, imageURLs: imageURLs, wm: wm)
        let coverMeta = coverSrc.isEmpty ? "" : "<meta property=\"og:image\" content=\"\(coverSrc)\">"
        let urlMeta = shareLink.isEmpty ? "" : "<meta property=\"og:url\" content=\"\(shareLink)\">"
        let galleryJS = imageURLs.map { "'\($0)'" }.joined(separator: ",")
        let qrCol = qrColumnHTML(qrSrc: qrSrc)
        let qrWrapClass = qrSrc.isEmpty ? " qr-wrap center" : " qr-wrap"
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta property="og:title" content="\(escapeHTML(title))">
        <meta property="og:description" content="\(escapeHTML(desc))">
        \(coverMeta)
        \(urlMeta)
        <title>\(escapeHTML(title))</title>
        <style>
        body{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif;margin:0;background:#f4f5f7;color:#1c1c1e;-webkit-touch-callout:none;-webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent;}
        .wrap{max-width:640px;margin:0 auto;padding:0 16px 16px;}
        .hero{background:linear-gradient(135deg,#1f3a5f,#2d5f8a);color:#fff;border-radius:16px;padding:20px 20px 16px;}
        .type{font-size:30px;font-weight:700;margin:0 0 14px;}
        .loc{display:flex;align-items:center;gap:8px;color:rgba(255,255,255,.92);text-decoration:none;}
        .loc-name{font-size:15px;}
        .nav-pill{display:inline-flex;align-items:center;gap:4px;background:rgba(255,255,255,.18);border-radius:999px;padding:6px 12px;font-size:13px;margin-left:auto;}
        .sec{font-size:15px;color:#3a3a3c;margin:18px 4px 10px;font-weight:600;}
        .media{background:#fff;border-radius:16px;padding:12px;}
        .vwrap{position:relative;width:100%;aspect-ratio:4/3;border-radius:10px;overflow:hidden;margin-bottom:10px;background:#000;cursor:pointer;}
        .vthumb{position:absolute;inset:0;background-size:cover;background-position:center;}
        .vplay{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:64px;height:64px;border-radius:50%;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;color:#fff;font-size:28px;border:2px solid rgba(255,255,255,.85);}
        .vwrap video{width:100%;height:100%;display:none;background:#000;}
        .vwrap.playing .vthumb,.vwrap.playing .vplay{display:none;}
        .vwrap.playing video{display:block;}
        .cellwrap{width:100%;aspect-ratio:4/3;border-radius:10px;overflow:hidden;background-color:#e8e8ec;margin-bottom:10px;cursor:pointer;position:relative;}
        .cell{width:100%;height:100%;object-fit:cover;display:block;pointer-events:none;-webkit-user-drag:none;-webkit-touch-callout:none;}
        .card{background:linear-gradient(180deg,#f7fafd,#e9f1f9);border:1px solid #dfe9f3;border-radius:16px;padding:14px;margin-top:12px;}
        .qr-wrap{display:flex;align-items:center;gap:14px;}
        .qr-wrap.center{justify-content:center;}
        .qr-col{display:flex;flex-direction:column;align-items:center;gap:3px;flex-shrink:0;}
        .qr-tip{font-size:10px;color:#8e8e93;text-align:center;max-width:108px;white-space:nowrap;line-height:1.3;}
        .qr{width:108px;height:108px;border-radius:10px;object-fit:cover;flex-shrink:0;background:#fff;border:1px solid #e3e3e8;-webkit-touch-callout:default;-webkit-user-select:text;user-select:text;-webkit-user-drag:auto;}
        .card-info{flex:1;min-width:0;text-align:center;}
        .tag{color:#8e8e93;font-size:12px;margin-bottom:10px;}
        .row{display:flex;align-items:center;justify-content:center;gap:8px;}
        .name{font-size:17px;font-weight:600;}
        .num{font-size:16px;font-weight:600;color:#b8860b;}
        .note{color:#8e8e93;font-size:12px;margin:10px 0 14px;}
        .btns{display:flex;gap:10px;justify-content:center;}
        .btn{flex:1;max-width:220px;padding:12px 0;border-radius:999px;font-size:15px;font-weight:600;text-align:center;text-decoration:none;}
        .btn.call{background:#1f3a5f;color:#fff;}
        .btn.copy{background:#f0f0f2;color:#1c1c1e;border:none;}
        .foot{text-align:center;color:#8e8e93;font-size:12px;padding:18px 0 26px;}
        #toast{position:fixed;left:50%;bottom:80px;transform:translateX(-50%);background:rgba(0,0,0,.8);color:#fff;padding:10px 18px;border-radius:8px;font-size:14px;z-index:999;display:none;}
        #lb{position:fixed;inset:0;background:rgba(0,0,0,.95);z-index:999;display:none;}
        #lbImg{position:absolute;inset:0;background-size:contain;background-position:center;background-repeat:no-repeat;}
        #lbPrev{position:absolute;left:6px;top:50%;transform:translateY(-50%);color:#fff;font-size:44px;padding:10px 16px;cursor:pointer;user-select:none;}
        #lbNext{position:absolute;right:6px;top:50%;transform:translateY(-50%);color:#fff;font-size:44px;padding:10px 16px;cursor:pointer;user-select:none;}
        #lbClose{position:absolute;top:12px;right:12px;color:#fff;font-size:26px;padding:10px;cursor:pointer;user-select:none;}
        #lbCnt{position:absolute;bottom:22px;left:0;right:0;text-align:center;color:rgba(255,255,255,.85);font-size:14px;user-select:none;}
        </style>
        </head>
        <body oncontextmenu="return false">
        <div class="wrap">
        <section class="hero">
          <h1 class="type">\(escapeHTML(title))</h1>
          <a class="loc" href="https://uri.amap.com/search?keyword=%E5%88%A9%E4%BF%9D%E7%B1%B3%E5%85%B0%E5%85%AC%E5%AF%93" target="_blank" rel="noopener">
            <span class="loc-name">利保米兰公馆</span>
            <span class="nav-pill"><svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2a7 7 0 0 0-4 12.7V17a1 1 0 0 0 2 0v-1h4v1a1 1 0 0 0 2 0v-2.3A7 7 0 0 0 12 2zm0 2a5 5 0 1 1 0 10 5 5 0 0 1 0-10zm0 3a2 2 0 1 0 0 4 2 2 0 0 0 0-4z"/></svg>导航</span>
          </a>
        </section>
        <h2 class="sec">实拍 · 点击放大</h2>
        \(mediaBlock)
        <section class="card">
          <div class="\(qrWrapClass)">
            \(qrCol)
            <div class="card-info">
              <div class="tag">米兰租赁管家 · 专业省心租好房</div>
              <div class="row"><span class="name">\(escapeHTML(name))</span><span class="num">\(escapeHTML(phone))</span></div>
              <div class="note">微信同号 · 24小时可约看房</div>
              <div class="btns">
                <a class="btn call" href="tel:\(escapeHTML(phone))">拨打电话</a>
                <button class="btn copy" type="button" onclick="copyPhone()">复制电话</button>
              </div>
            </div>
          </div>
        </section>
        <div class="foot">更多优质房源请与我联系-\(escapeHTML(phone))</div>
        </div>
        <div id="toast"></div>
        <div id="lb"><div id="lbImg"></div><div id="lbPrev" onclick="lbPrev()">‹</div><div id="lbNext" onclick="lbNext()">›</div><div id="lbClose" onclick="lbClose()">✕</div><div id="lbCnt"></div></div>
        <script>
        var GALLERY=[\(galleryJS)];var gi=0;
        function playVideo(w,src){var v=w.querySelector('video');if(!v.src){v.src=src;}var p=v.play();if(p&&p.catch){p.catch(function(){});}w.className=w.className+' playing';}
        function openImg(i){gi=i;show();}
        function show(){var d=document.getElementById('lb');document.getElementById('lbImg').style.backgroundImage="url('"+GALLERY[gi]+"')";document.getElementById('lbCnt').textContent=(gi+1)+' / '+GALLERY.length;d.style.display='block';}
        function lbPrev(){gi=(gi-1+GALLERY.length)%GALLERY.length;show();}
        function lbNext(){gi=(gi+1)%GALLERY.length;show();}
        function lbClose(){document.getElementById('lb').style.display='none';}
        var _sx=0;(function(){var d=document.getElementById('lb');d.addEventListener('touchstart',function(e){_sx=e.touches[0].clientX},{passive:true});d.addEventListener('touchend',function(e){var dx=e.changedTouches[0].clientX-_sx;if(Math.abs(dx)>50){dx<0?lbNext():lbPrev();}},{passive:true});})();
        function toast(msg){var t=document.getElementById('toast');t.textContent=msg;t.style.display='block';clearTimeout(t._h);t._h=setTimeout(function(){t.style.display='none'},1600);}
        function copyPhone(){var p='\(phone)';function done(){toast('已复制 '+p)}function fb(){var i=document.createElement('input');i.value=p;document.body.appendChild(i);i.select();i.setSelectionRange(0,999);document.execCommand('copy');i.remove();done()}if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(p).then(done,fb)}else{fb()}}
        </script>
        \(trackScript)
        </body>
        </html>
        """
    }

    // MARK: 完整版（信息三行：房号+户型 / 租金+密码+房东 / 备注）

    static func buildFullHTML(title: String, desc: String, info: ShareHouseInfo, name: String, phone: String, videoTags: [String], imageURLs: [String], coverSrc: String, qrSrc: String, shareLink: String, wm: String = "", trackScript: String = "") -> String {
        let mediaBlock = mediaBlockHTML(videoTags: videoTags, imageURLs: imageURLs, wm: wm)
        let coverMeta = coverSrc.isEmpty ? "" : "<meta property=\"og:image\" content=\"\(coverSrc)\">"
        let urlMeta = shareLink.isEmpty ? "" : "<meta property=\"og:url\" content=\"\(shareLink)\">"
        let galleryJS = imageURLs.map { "'\($0)'" }.joined(separator: ",")
        let qrCol = qrColumnHTML(qrSrc: qrSrc)
        let qrWrapClass = qrSrc.isEmpty ? " qr-wrap center" : " qr-wrap"
        let remarkHTML = info.remark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "<div class=\"remark\">\(escapeHTML(info.remark))</div>"
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta property="og:title" content="\(escapeHTML(title))">
        <meta property="og:description" content="\(escapeHTML(desc))">
        \(coverMeta)
        \(urlMeta)
        <title>\(escapeHTML(title))</title>
        <style>
        body{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif;margin:0;background:#f4f5f7;color:#1c1c1e;-webkit-touch-callout:none;-webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent;}
        .wrap{max-width:640px;margin:0 auto;padding:0 16px 16px;}
        .hero{background:linear-gradient(135deg,#1f3a5f,#2d5f8a);color:#fff;border-radius:16px;padding:20px 20px 16px;}
        .type{font-size:28px;font-weight:700;margin:0 0 12px;}
        .infos{display:flex;flex-direction:column;gap:8px;font-size:15px;color:rgba(255,255,255,.95);}
        .irow{display:flex;align-items:center;gap:10px;}
        .irow .label{color:rgba(255,255,255,.65);font-size:13px;flex-shrink:0;}
        .irow .val{font-weight:600;}
        .irow .right{margin-left:auto;}
        .loc{display:flex;align-items:center;gap:8px;color:rgba(255,255,255,.92);text-decoration:none;margin-top:12px;}
        .loc-name{font-size:14px;}
        .nav-pill{display:inline-flex;align-items:center;gap:4px;background:rgba(255,255,255,.18);border-radius:999px;padding:6px 12px;font-size:13px;margin-left:auto;}
        .sec{font-size:15px;color:#3a3a3c;margin:18px 4px 10px;font-weight:600;}
        .media{background:#fff;border-radius:16px;padding:12px;}
        .vwrap{position:relative;width:100%;aspect-ratio:4/3;border-radius:10px;overflow:hidden;margin-bottom:10px;background:#000;cursor:pointer;}
        .vthumb{position:absolute;inset:0;background-size:cover;background-position:center;}
        .vplay{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:64px;height:64px;border-radius:50%;background:rgba(0,0,0,.55);display:flex;align-items:center;justify-content:center;color:#fff;font-size:28px;border:2px solid rgba(255,255,255,.85);}
        .vwrap video{width:100%;height:100%;display:none;background:#000;}
        .vwrap.playing .vthumb,.vwrap.playing .vplay{display:none;}
        .vwrap.playing video{display:block;}
        .cellwrap{width:100%;aspect-ratio:4/3;border-radius:10px;overflow:hidden;background-color:#e8e8ec;margin-bottom:10px;cursor:pointer;position:relative;}
        .cell{width:100%;height:100%;object-fit:cover;display:block;pointer-events:none;-webkit-user-drag:none;-webkit-touch-callout:none;}
        .card{background:linear-gradient(180deg,#f7fafd,#e9f1f9);border:1px solid #dfe9f3;border-radius:16px;padding:14px;margin-top:12px;}
        .qr-wrap{display:flex;align-items:center;gap:14px;}
        .qr-wrap.center{justify-content:center;}
        .qr-col{display:flex;flex-direction:column;align-items:center;gap:3px;flex-shrink:0;}
        .qr-tip{font-size:10px;color:#8e8e93;text-align:center;max-width:108px;white-space:nowrap;line-height:1.3;}
        .qr{width:108px;height:108px;border-radius:10px;object-fit:cover;flex-shrink:0;background:#fff;border:1px solid #e3e3e8;-webkit-touch-callout:default;-webkit-user-select:text;user-select:text;-webkit-user-drag:auto;}
        .card-info{flex:1;min-width:0;text-align:center;}
        .tag{color:#8e8e93;font-size:12px;margin-bottom:10px;}
        .row{display:flex;align-items:center;justify-content:center;gap:8px;}
        .name{font-size:17px;font-weight:600;}
        .num{font-size:16px;font-weight:600;color:#b8860b;}
        .note{color:#8e8e93;font-size:12px;margin:10px 0 14px;}
        .btns{display:flex;gap:10px;justify-content:center;}
        .btn{flex:1;max-width:220px;padding:12px 0;border-radius:999px;font-size:15px;font-weight:600;text-align:center;text-decoration:none;}
        .btn.call{background:#1f3a5f;color:#fff;}
        .btn.copy{background:#f0f0f2;color:#1c1c1e;border:none;}
        .foot{text-align:center;color:#8e8e93;font-size:12px;padding:18px 0 26px;}
        #toast{position:fixed;left:50%;bottom:80px;transform:translateX(-50%);background:rgba(0,0,0,.8);color:#fff;padding:10px 18px;border-radius:8px;font-size:14px;z-index:999;display:none;}
        #lb{position:fixed;inset:0;background:rgba(0,0,0,.95);z-index:999;display:none;}
        #lbImg{position:absolute;inset:0;background-size:contain;background-position:center;background-repeat:no-repeat;}
        #lbPrev{position:absolute;left:6px;top:50%;transform:translateY(-50%);color:#fff;font-size:44px;padding:10px 16px;cursor:pointer;user-select:none;}
        #lbNext{position:absolute;right:6px;top:50%;transform:translateY(-50%);color:#fff;font-size:44px;padding:10px 16px;cursor:pointer;user-select:none;}
        #lbClose{position:absolute;top:12px;right:12px;color:#fff;font-size:26px;padding:10px;cursor:pointer;user-select:none;}
        #lbCnt{position:absolute;bottom:22px;left:0;right:0;text-align:center;color:rgba(255,255,255,.85);font-size:14px;user-select:none;}
        .remark{color:#3a3a3c;font-size:14px;margin-top:10px;line-height:1.6;white-space:pre-wrap;}
        </style>
        </head>
        <body oncontextmenu="return false">
        <div class="wrap">
        <section class="hero">
          <h1 class="type">\(escapeHTML(title))</h1>
          <div class="infos">
            <div class="irow"><span class="val">\(escapeHTML(info.displayRoomNo))</span><span class="label">\(escapeHTML(info.towerLabel))</span><span class="label right">\(escapeHTML(info.statusLabel))</span></div>
            <div class="irow"><span class="label">月租</span><span class="val">\(escapeHTML(info.priceText))</span>\(info.password.isEmpty ? "" : "<span class=\"label\">密码</span><span class=\"val\">\(escapeHTML(info.password))</span>")<span class="label right">房东</span><span class="val">\(escapeHTML(info.landlord))</span></div>
          </div>
          <a class="loc" href="https://uri.amap.com/search?keyword=%E5%88%A9%E4%BF%9D%E7%B1%B3%E5%85%B0%E5%85%AC%E5%AF%93" target="_blank" rel="noopener">
            <span class="loc-name">利保米兰公馆</span>
            <span class="nav-pill">导航</span>
          </a>
        </section>
        \(remarkHTML.isEmpty ? "" : "<div class=\"remark\" style=\"margin:14px 4px 0;\">\(remarkHTML)</div>")
        <h2 class="sec">实拍 · 点击放大</h2>
        \(mediaBlock)
        <section class="card">
          <div class="\(qrWrapClass)">
            \(qrCol)
            <div class="card-info">
              <div class="tag">米兰租赁管家 · 专业省心租好房</div>
              <div class="row"><span class="name">\(escapeHTML(name))</span><span class="num">\(escapeHTML(phone))</span></div>
              <div class="note">微信同号 · 24小时可约看房</div>
              <div class="btns">
                <a class="btn call" href="tel:\(escapeHTML(phone))">拨打电话</a>
                <button class="btn copy" type="button" onclick="copyPhone()">复制电话</button>
              </div>
            </div>
          </div>
        </section>
        <div class="foot">更多优质房源请与我联系-\(escapeHTML(phone))</div>
        </div>
        <div id="toast"></div>
        <div id="lb"><div id="lbImg"></div><div id="lbPrev" onclick="lbPrev()">‹</div><div id="lbNext" onclick="lbNext()">›</div><div id="lbClose" onclick="lbClose()">✕</div><div id="lbCnt"></div></div>
        <script>
        var GALLERY=[\(galleryJS)];var gi=0;
        function playVideo(w,src){var v=w.querySelector('video');if(!v.src){v.src=src;}var p=v.play();if(p&&p.catch){p.catch(function(){});}w.className=w.className+' playing';}
        function openImg(i){gi=i;show();}
        function show(){var d=document.getElementById('lb');document.getElementById('lbImg').style.backgroundImage="url('"+GALLERY[gi]+"')";document.getElementById('lbCnt').textContent=(gi+1)+' / '+GALLERY.length;d.style.display='block';}
        function lbPrev(){gi=(gi-1+GALLERY.length)%GALLERY.length;show();}
        function lbNext(){gi=(gi+1)%GALLERY.length;show();}
        function lbClose(){document.getElementById('lb').style.display='none';}
        var _sx=0;(function(){var d=document.getElementById('lb');d.addEventListener('touchstart',function(e){_sx=e.touches[0].clientX},{passive:true});d.addEventListener('touchend',function(e){var dx=e.changedTouches[0].clientX-_sx;if(Math.abs(dx)>50){dx<0?lbNext():lbPrev();}},{passive:true});})();
        function toast(msg){var t=document.getElementById('toast');t.textContent=msg;t.style.display='block';clearTimeout(t._h);t._h=setTimeout(function(){t.style.display='none'},1600);}
        function copyPhone(){var p='\(phone)';function done(){toast('已复制 '+p)}function fb(){var i=document.createElement('input');i.value=p;document.body.appendChild(i);i.select();i.setSelectionRange(0,999);document.execCommand('copy');i.remove();done()}if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(p).then(done,fb)}else{fb()}}
        </script>
        \(trackScript)
        </body>
        </html>
        """
    }

    // MARK: 合集页

    struct PreparedRoom {
        let item: ShareCollectionItem
        let videoTags: [String]
        let imageURLs: [String]
        let coverSrc: String
    }

    static func buildCollectionHTML(rooms: [PreparedRoom], mode: ShareMode, name: String, phone: String, coverSrc: String, qrSrc: String, wm: String = "", trackScript: String = "") -> String {
        let count = rooms.count
        let qrCol = qrColumnHTML(qrSrc: qrSrc)
        let qrWrapClass = qrSrc.isEmpty ? " qr-wrap center" : " qr-wrap"
        let title: String
        let desc: String
        switch mode {
        case .masked:
            title = "已为你挑选\(count)套优质房源"
            desc = "利保米兰公馆\n\(name)-\(phone)"
        case .full:
            let minPrice = rooms.compactMap { Double($0.item.priceText) }.min()
            title = "已为你挑选\(count)套优质房源"
            desc = (minPrice.map { "月租 \(FormatKit.money($0)) 起 · " } ?? "") + "利保米兰公馆 \(name)-\(phone)"
        }
        let coverMeta = coverSrc.isEmpty ? "" : "<meta property=\"og:image\" content=\"\(coverSrc)\">"
        // 卡片
        var cards = ""
        for (i, r) in rooms.enumerated() {
            let item = r.item
            cards += """
            <div class="ccard" data-i="\(i)">
              <div class="cover">\(r.coverSrc.isEmpty ? "<div class=\"ph\"></div>" : "<img src=\"\(r.coverSrc)\" alt=\"\" loading=\"lazy\" onerror=\"this.remove()\">")<span class="play"></span><span class="type-tag">\(escapeHTML(item.layout))</span></div>
              <div class="cinfo"><div class="rrow"><span class="rno">\(escapeHTML(item.displayRoomNo))</span><span class="rprice">\(escapeHTML(item.priceText))</span></div><div class="rsub">\(escapeHTML(item.towerLabel)) · \(escapeHTML(item.statusLabel))\(item.landlord.isEmpty ? "" : " · 房东\(escapeHTML(item.landlord))")</div></div>
            </div>
            """
        }
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta property="og:title" content="\(escapeHTML(title))">
        <meta property="og:description" content="\(escapeHTML(desc))">
        \(coverMeta)
        <title>\(escapeHTML(title))</title>
        <style>
        body{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif;margin:0;background:#f4f5f7;color:#1c1c1e;-webkit-touch-callout:none;-webkit-user-select:none;user-select:none;-webkit-tap-highlight-color:transparent;}
        .wrap{max-width:640px;margin:0 auto;padding:0 16px 16px;}
        .hero{background:linear-gradient(135deg,#1f3a5f,#2d5f8a);color:#fff;border-radius:16px;padding:20px 20px 16px;}
        .type{font-size:24px;font-weight:700;margin:0 0 8px;}
        .sub{color:rgba(255,255,255,.85);font-size:14px;}
        .grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;padding:16px 0;}
        .ccard{background:#fff;border-radius:14px;overflow:hidden;box-shadow:0 1px 4px rgba(0,0,0,.06);}
        .cover{position:relative;aspect-ratio:1/1;background:#e8e8ec;}
        .cover img{width:100%;height:100%;object-fit:cover;display:block;}
        .ph{width:100%;height:100%;background:linear-gradient(135deg,#dfe3e8,#c6cdd6);}
        .play{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:42px;height:42px;border-radius:50%;background:rgba(0,0,0,.45);}
        .play::after{content:"";position:absolute;left:50%;top:50%;transform:translate(-40%,-50%);border-left:12px solid #fff;border-top:8px solid transparent;border-bottom:8px solid transparent;}
        .type-tag{position:absolute;left:8px;bottom:8px;background:rgba(0,0,0,.55);color:#fff;font-size:12px;padding:3px 9px;border-radius:10px;}
        .cinfo{padding:10px 12px 12px;}
        .rrow{display:flex;align-items:center;justify-content:space-between;}
        .rno{font-size:16px;font-weight:700;}
        .rprice{font-size:15px;font-weight:700;color:#1f7a4d;}
        .rsub{font-size:12px;color:#8e8e93;margin-top:3px;}
        .card{background:linear-gradient(180deg,#f7fafd,#e9f1f9);border:1px solid #dfe9f3;border-radius:16px;padding:14px;margin-top:12px;}
        .qr-wrap{display:flex;align-items:center;gap:14px;}
        .qr-wrap.center{justify-content:center;}
        .qr-col{display:flex;flex-direction:column;align-items:center;gap:3px;flex-shrink:0;}
        .qr-tip{font-size:10px;color:#8e8e93;text-align:center;max-width:108px;white-space:nowrap;line-height:1.3;}
        .qr{width:108px;height:108px;border-radius:10px;object-fit:cover;flex-shrink:0;background:#fff;border:1px solid #e3e3e8;-webkit-touch-callout:default;-webkit-user-select:text;user-select:text;-webkit-user-drag:auto;}
        .card-info{flex:1;min-width:0;text-align:center;}
        .tag{color:#8e8e93;font-size:12px;margin-bottom:10px;}
        .row{display:flex;align-items:center;justify-content:center;gap:8px;}
        .name{font-size:17px;font-weight:600;}
        .num{font-size:16px;font-weight:600;color:#b8860b;}
        .note{color:#8e8e93;font-size:12px;margin:10px 0 14px;}
        .btns{display:flex;gap:10px;justify-content:center;}
        .btn{flex:1;max-width:220px;padding:12px 0;border-radius:999px;font-size:15px;font-weight:600;text-align:center;text-decoration:none;}
        .btn.call{background:#1f3a5f;color:#fff;}
        .btn.copy{background:#f0f0f2;color:#1c1c1e;border:none;}
        .foot{text-align:center;color:#8e8e93;font-size:12px;padding:18px 0 26px;}
        #toast{position:fixed;left:50%;bottom:80px;transform:translateX(-50%);background:rgba(0,0,0,.8);color:#fff;padding:10px 18px;border-radius:8px;font-size:14px;z-index:999;display:none;}
        #mask{position:fixed;inset:0;background:rgba(0,0,0,.92);z-index:999;display:none;align-items:center;justify-content:center;}
        #mask img{max-width:92%;max-height:88%;border-radius:8px;}
        #mask .x{position:absolute;top:40px;right:18px;color:#fff;font-size:30px;padding:8px;}
        </style>
        </head>
        <body oncontextmenu="return false">
        <div class="wrap">
        <section class="hero">
          <h1 class="type">\(escapeHTML(title))</h1>
          <div class="sub">\(escapeHTML(desc))</div>
        </section>
        <div class="grid">\(cards)</div>
        <section class="card">
          <div class="\(qrWrapClass)">
            \(qrCol)
            <div class="card-info">
              <div class="tag">米兰租赁管家 · 专业省心租好房</div>
              <div class="row"><span class="name">\(escapeHTML(name))</span><span class="num">\(escapeHTML(phone))</span></div>
              <div class="note">微信同号 · 24小时可约看房</div>
              <div class="btns">
                <a class="btn call" href="tel:\(escapeHTML(phone))">拨打电话</a>
                <button class="btn copy" type="button" onclick="copyPhone()">复制电话</button>
              </div>
            </div>
          </div>
        </section>
        <div class="foot">更多优质房源请与我联系-\(escapeHTML(phone))</div>
        </div>
        <div id="mask" onclick="this.style.display='none'"><span class="x">×</span><img id="modalImg" alt=""></div>
        <div id="toast"></div>
        <script>
        function toast(msg){var t=document.getElementById('toast');t.textContent=msg;t.style.display='block';clearTimeout(t._h);t._h=setTimeout(function(){t.style.display='none'},1600);}
        function copyPhone(){var p='\(phone)';function done(){toast('已复制 '+p)}function fb(){var i=document.createElement('input');i.value=p;document.body.appendChild(i);i.select();i.setSelectionRange(0,999);document.execCommand('copy');i.remove();done()}if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(p).then(done,fb)}else{fb()}}
        document.querySelectorAll('.ccard').forEach(function(card){
          card.addEventListener('click',function(){
            var i=parseInt(card.getAttribute('data-i'));
            showDetail(i);
          });
        });
        var ROOM_LINKS=[];
        function showDetail(i){
          if(ROOM_LINKS[i]){ location.href=ROOM_LINKS[i]; return; }
          toast('详情链接生成中，请稍后');
        }
        </script>
        \(trackScript)
        </body>
        </html>
        """
    }

    // MARK: 选房壳（v1.50：公开选房页，静态壳 + JS 实时拉取 rooms_json）

    static func firstRoomCoverRemotePath() -> String {
        let dir = DataRoot.mediaDirectory
        guard let houseDirs = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return "" }
        for hd in houseDirs.sorted() {
            var isDir: ObjCBool = false
            let hpath = dir.appendingPathComponent(hd)
            guard FileManager.default.fileExists(atPath: hpath.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let mediaNames = (try? FileManager.default.contentsOfDirectory(atPath: hpath.path)) ?? []
            for mn in mediaNames.sorted() {
                let lower = mn.lowercased()
                if lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.hasSuffix(".m4v") {
                    return "users/\(CloudUser.safeName)/shares/\(hd)/\(mn).vthumb.jpg"
                }
            }
            for mn in mediaNames.sorted() {
                let lower = mn.lowercased()
                if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".png") || lower.hasSuffix(".heic") || lower.hasSuffix(".webp") {
                    return "h/\(hd)/\(mn)"
                }
            }
        }
        return ""
    }

    static func buildRoomsShellHTML(config: CosConfig, shellURL: String) -> String {
        let u = CloudUser.safeName
        let uEsc = u.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let base = CloudConfig.functionURL
        var cd = config.customDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        for pre in ["https://", "http://"] where cd.lowercased().hasPrefix(pre) {
            cd = String(cd.dropFirst(pre.count))
        }
        while cd.hasSuffix("/") { cd.removeLast() }
        let cdEsc = cd.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let jsUrlBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsUrl = jsUrlBase + "?act=rooms_json&u=" + uEsc + "&cd=" + cdEsc
        let pageUrl = base + "?act=rooms&u=" + uEsc
        var og = ""
        let coverPath = firstRoomCoverRemotePath()
        if !coverPath.isEmpty,
           let cv = try? presignedGetURL(for: coverPath, expires: 3650 * 86400, config: config).absoluteString {
            og = cv
        }
        let ogMeta = og.isEmpty ? "" : "<meta property=\"og:image\" content=\"\(og)\">"
        let urlMeta = "<meta property=\"og:url\" content=\"\(shellURL)\">"
        return """
        <!DOCTYPE html>
        <html lang="zh-CN">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>米兰公馆 · 在租房源</title>
        <meta name="description" content="米兰公馆在租房源，实时更新，户型直达">
        <meta property="og:type" content="website">
        <meta property="og:title" content="米兰公馆 · 在租房源">
        <meta property="og:description" content="实时更新的在租房源列表，点击查看户型。更多优质房源请与我联系。">
        \(ogMeta)
        \(urlMeta)
        <style>
        *{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent;}
        html,body{background:#f4f5f7;color:#1a1c20;font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",system-ui,sans-serif;}
        html,body{height:100%;}
        body{max-width:560px;margin:0 auto;padding:0 16px 24px;display:flex;flex-direction:column;min-height:100%;-webkit-touch-callout:none;-webkit-user-select:none;user-select:none;-webkit-user-drag:none;}
        body *{-webkit-touch-callout:none;-webkit-user-select:none;user-select:none;-webkit-user-drag:none;}
        .main{flex:1 0 auto;width:100%;}
        .head{display:flex;align-items:center;justify-content:space-between;padding:16px 2px 6px;}
        h1{font-size:19px;font-weight:700;color:#1a1c20;letter-spacing:.5px;}
        .refresh{color:#1f7a4d;font-size:14px;font-weight:600;background:none;border:none;padding:6px 8px;}
        .filters{display:flex;gap:8px;flex-wrap:wrap;padding:10px 2px 4px;}
        .chip{padding:5px 13px;border-radius:15px;background:#eef0f2;color:#5b616e;font-size:13px;border:none;}
        .chip.on{background:#1f7a4d;color:#fff;font-weight:600;}
        #count{font-size:13px;color:#8a919e;padding:4px 2px 2px;}
        #loading{text-align:center;color:#8a919e;padding:50px 0;font-size:14px;}
        .grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;padding:12px 0;}
        .card{position:relative;border-radius:12px;overflow:hidden;background:#fff;aspect-ratio:1/1;box-shadow:0 1px 4px rgba(0,0,0,.06);}
        .cover{position:absolute;inset:0;}
        .cover img{width:100%;height:100%;object-fit:cover;display:block;}
        .ph{width:100%;height:100%;background:linear-gradient(135deg,#dfe3e8,#c6cdd6);}
        .play{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:46px;height:46px;border-radius:50%;background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center;}
        .play::after{content:"";border-left:14px solid #fff;border-top:9px solid transparent;border-bottom:9px solid transparent;margin-left:3px;}
        .type-tag{position:absolute;left:8px;bottom:8px;background:rgba(0,0,0,.55);color:#fff;font-size:12px;padding:3px 9px;border-radius:10px;}
        #empty{display:none;text-align:center;color:#8a919e;padding:60px 0;font-size:14px;}
        #mask{display:none;position:fixed;inset:0;background:rgba(0,0,0,.92);z-index:50;align-items:center;justify-content:center;}
        #mask img{max-width:92%;max-height:88%;border-radius:8px;}
        #mask .x{position:absolute;top:44px;right:18px;color:#fff;font-size:30px;line-height:1;padding:8px;}
        #toast{position:fixed;left:50%;bottom:90px;transform:translateX(-50%);background:rgba(0,0,0,.8);color:#fff;padding:9px 16px;border-radius:8px;font-size:13px;opacity:0;pointer-events:none;transition:opacity .2s;z-index:60;}
        #toast.show{opacity:1;}
        .person{margin-top:auto;background:#fff;border-radius:12px;padding:14px 14px 12px;box-shadow:0 1px 4px rgba(0,0,0,.06);}
        .person .top{display:flex;gap:12px;align-items:flex-start;}
        .person .avatar{width:48px;height:48px;border-radius:50%;background:#1f7a4d;color:#fff;display:flex;align-items:center;justify-content:center;font-size:22px;font-weight:700;flex-shrink:0;}
        .person .nm{font-size:16px;font-weight:700;}
        .person .ph-t{font-size:14px;color:#5b616e;margin-top:2px;}
        .person .btns{display:flex;gap:10px;margin-top:12px;}
        .person .btn{flex:1;text-align:center;padding:10px 0;border-radius:10px;font-size:14px;}
        .person .call{background:#1f7a4d;color:#fff;font-weight:600;}
        .person .copy{background:#f0f2f4;color:#1a1c20;}
        .qr-row{display:none;margin-top:10px;background:#fff;border-radius:12px;padding:12px;text-align:center;}
        .qr-row img{width:110px;height:110px;border-radius:6px;}
        .qr-row p{font-size:12px;color:#8a919e;margin-top:6px;}
        </style>
        </head>
        <body>
        <div class="main">
          <div class="head"><h1>米兰公馆 · 在租房源</h1><button class="refresh" id="refreshBtn">刷新</button></div>
          <div class="filters" id="filters"></div>
          <div id="count"></div>
          <div id="loading">加载中...</div>
          <div class="grid" id="list"></div>
          <div id="empty">暂无待租房源</div>
        </div>
        <div class="person" id="cardShare">
          <div class="top">
            <div class="avatar" id="avatar">梁</div>
            <div>
              <div class="nm" id="nameText">梁涛</div>
              <div class="ph-t" id="phoneText">13288251132</div>
              <div style="font-size:12px;color:#8a919e;margin-top:2px;">微信同号 · 24小时可约看房</div>
            </div>
          </div>
          <div class="btns">
            <div class="btn call" id="callBtn">拨打电话</div>
            <div class="btn copy" id="copyBtn">复制电话</div>
          </div>
        </div>
        <div class="qr-row" id="qrCol"><img id="qrImg" alt="二维码"><p>扫码加微信 直接看房</p></div>
        <div id="mask" onclick="this.style.display='none'"><span class="x">×</span><img id="modalImg" alt=""></div>
        <div id="toast"></div>
        <script>
        var FETCH_URL = "\(jsUrl)";
        var ROOMS = [];
        var curFilter = "全部";
        function esc(s){ var d=document.createElement("div"); d.textContent=(s||""); return d.innerHTML; }
        function render(){
          var rows = ROOMS;
          if(curFilter !== "全部"){ rows = ROOMS.filter(function(h){ return h.layout === curFilter; }); }
          document.getElementById("count").textContent = "共 " + rows.length + " 套待租房源" + (curFilter !== "全部" ? "（"+curFilter+"）" : "");
          var list = document.getElementById("list");
          list.innerHTML = rows.map(function(h,i){
            var cover = h.cover || "";
            var inner = cover ? '<img class="cv" src="'+cover+'" alt="" loading="lazy" onerror="this.remove()">' : '<div class="ph"></div>';
            return '<div class="card" data-i="'+i+'"><div class="cover">'+inner+'<span class="play"></span><span class="type-tag">'+esc(h.layout)+'</span></div></div>';
          }).join("");
          document.getElementById("empty").style.display = rows.length ? "none" : "block";
          document.getElementById("loading").style.display = "none";
        }
        function buildFilters(){
          var kinds = ["全部"];
          ROOMS.forEach(function(h){ if(kinds.indexOf(h.layout) < 0) kinds.push(h.layout); });
          document.getElementById("filters").innerHTML = kinds.map(function(k){
            return '<span class="chip'+(curFilter===k?" on":"")+'" data-k="'+k+'">'+k+'</span>';
          }).join("");
        }
        var toastTimer;
        function showToast(msg){
          var t = document.getElementById("toast");
          t.textContent = msg; t.classList.add("show");
          clearTimeout(toastTimer);
          toastTimer = setTimeout(function(){ t.classList.remove("show"); }, 1600);
        }
        function showModal(src){
          document.getElementById("modalImg").src = src;
          document.getElementById("mask").style.display = "flex";
        }
        document.getElementById("list").addEventListener("click", function(e){
          var card = e.target.closest(".card");
          if(!card) return;
          var h = ROOMS[parseInt(card.getAttribute("data-i"))];
          if(!h) return;
          if(h.share){ location.href = h.share; return; }
          if(h.cover){ showModal(h.cover); }
        });
        function copyPhone(){
          var p = document.getElementById("phoneText").textContent;
          function done(){ showToast("已复制 "+p); }
          function fb(){
            var i = document.createElement("input");
            i.value = p; document.body.appendChild(i); i.select();
            i.setSelectionRange(0,999); document.execCommand("copy"); i.remove(); done();
          }
          if(navigator.clipboard && window.isSecureContext){ navigator.clipboard.writeText(p).then(done,fb); }
          else { fb(); }
        }
        function load(){
          document.getElementById("loading").style.display = "block";
          document.getElementById("list").innerHTML = "";
          document.getElementById("empty").style.display = "none";
          fetch(FETCH_URL).then(function(r){ return r.json(); }).then(function(d){
            ROOMS = (d && d.rooms) || [];
            buildFilters(); render();
            var name = (d && d.name) || "梁涛"; var phone = (d && d.phone) || "13288251132";
            document.getElementById("nameText").textContent = name;
            document.getElementById("phoneText").textContent = phone;
            var a = document.getElementById("avatar"); a.textContent = name.length ? name[0] : "梁";
            if(d && d.qr){ document.getElementById("qrCol").style.display = "block"; document.getElementById("qrImg").src = d.qr; }
            else { document.getElementById("qrCol").style.display = "none"; }
            showToast("已刷新");
            TRACK();
          }).catch(function(){
            document.getElementById("loading").style.display = "none";
            showToast("刷新失败，请检查网络");
          });
        }
        function TRACK(){
          try{
            var b = "\(jsUrlBase)"; if(!b || b.indexOf("http") !== 0) return;
            var img = new Image();
            img.src = b + "?act=track&room=rooms&mode=rooms&ref=" + encodeURIComponent((document.referrer||"").slice(0,120)) + "&t=" + Date.now() + "&uname=\(uEsc)";
          }catch(e){}
        }
        document.getElementById("filters").addEventListener("click", function(e){
          var chip = e.target.closest(".chip");
          if(!chip) return;
          curFilter = chip.getAttribute("data-k");
          buildFilters(); render();
        });
        document.getElementById("refreshBtn").addEventListener("click", load);
        document.getElementById("copyBtn").addEventListener("click", copyPhone);
        document.getElementById("callBtn").addEventListener("click", function(){
          var p = document.getElementById("phoneText").textContent;
          location.href = "tel:" + p.replace(/[^0-9]/g,"");
        });
        load();
        </script>
        </body>
        </html>
        """
    }
}

// MARK: - 网页后台缓存版本戳（对齐 iOS WebCache；Mac 无内嵌 WebView，仅更新戳供浏览器后台强制刷新）

enum WebCache {
    private static let stampKey = "cloud.webCacheStamp"

    /// 网页版本戳：每次「刷新网页后台」都更新，后台 URL 带上它 → 浏览器缓存立即失效
    static var stamp: String {
        UserDefaults.standard.string(forKey: stampKey) ?? "20261023"
    }

    /// 更新版本戳（Mac 无 WebView，等效 iOS 的清除 WebKit 缓存）
    static func updateStamp() {
        UserDefaults.standard.set("\(Int(Date().timeIntervalSince1970))", forKey: stampKey)
    }
}
