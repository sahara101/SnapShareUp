import Foundation

public struct HeaderConfig: Codable, Identifiable, Hashable {
    public var id: UUID
    public var key: String
    public var value: String
    
    public init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }
}

public struct UploadConfig: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var requestURL: String
    public var fileFormName: String
    public var responseURL: String
    public var headers: [HeaderConfig]
    public var isDefault: Bool
    
    public init(
        id: UUID = UUID(),
        name: String = "",
        requestURL: String = "",
        fileFormName: String = "file",
        responseURL: String = "",
        headers: [HeaderConfig] = [],
        isDefault: Bool = false
    ) {
        self.id = id
        self.name = name
        self.requestURL = requestURL
        self.fileFormName = fileFormName
        self.responseURL = responseURL
        self.headers = headers
        self.isDefault = isDefault
    }
    
    // Implement Hashable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: UploadConfig, rhs: UploadConfig) -> Bool {
        lhs.id == rhs.id
    }
    
    var headersDictionary: [String: String] {
        Dictionary(uniqueKeysWithValues: headers.map { ($0.key, $0.value) })
    }
}
