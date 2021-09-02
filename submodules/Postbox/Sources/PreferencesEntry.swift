import Foundation

public final class PreferencesEntry: Equatable {
    public let data: Data

    public init(data: Data) {
        self.data = data
    }

    public init?<T: Encodable>(_ value: T) {
        let encoder = PostboxEncoder()
        encoder.encode(value, forKey: "_")
        self.data = encoder.makeData()
    }

    public func get<T: Decodable>(_ type: T.Type) -> T? {
        let decoder = PostboxDecoder(buffer: MemoryBuffer(data: self.data))
        return decoder.decode(T.self, forKey: "_")
    }

    public static func ==(lhs: PreferencesEntry, rhs: PreferencesEntry) -> Bool {
        return lhs.data == rhs.data
    }
}

public extension PreferencesEntry {
    var relatedResources: [MediaResourceId] {
        return []
    }
}
