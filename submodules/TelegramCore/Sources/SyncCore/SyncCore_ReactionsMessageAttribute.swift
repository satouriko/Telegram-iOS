import Foundation
import Postbox
import TelegramApi

public struct MessageReaction: Equatable, PostboxCoding, Codable {
    public enum Reaction: Hashable, Comparable, Codable, PostboxCoding {
        case builtin(String)
        case custom(Int64)
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: StringCodingKey.self)
            
            if let value = try container.decodeIfPresent(String.self, forKey: "v") {
                self = .builtin(value)
            } else {
                self = .custom(try container.decode(Int64.self, forKey: "cfid"))
            }
        }
        
        public init(decoder: PostboxDecoder) {
            if let value = decoder.decodeOptionalStringForKey("v") {
                self = .builtin(value)
            } else {
                self = .custom(decoder.decodeInt64ForKey("cfid", orElse: 0))
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: StringCodingKey.self)
            
            switch self {
            case let .builtin(value):
                try container.encode(value, forKey: "v")
            case let .custom(fileId):
                try container.encode(fileId, forKey: "cfid")
            }
        }
        
        public func encode(_ encoder: PostboxEncoder) {
            switch self {
            case let .builtin(value):
                encoder.encodeString(value, forKey: "v")
            case let .custom(fileId):
                encoder.encodeInt64(fileId, forKey: "cfid")
            }
        }
        
        public static func <(lhs: Reaction, rhs: Reaction) -> Bool {
            switch lhs {
            case let .builtin(lhsValue):
                switch rhs {
                case let .builtin(rhsValue):
                    return lhsValue < rhsValue
                case .custom:
                    return true
                }
            case let .custom(lhsValue):
                switch rhs {
                case .builtin:
                    return false
                case let .custom(rhsValue):
                    return lhsValue < rhsValue
                }
            }
        }
    }
    
    public var value: Reaction
    public var count: Int32
    public var chosenOrder: Int?
    
    public var isSelected: Bool {
        return self.chosenOrder != nil
    }
    
    public init(value: Reaction, count: Int32, chosenOrder: Int?) {
        self.value = value
        self.count = count
        self.chosenOrder = chosenOrder
    }
    
    public init(decoder: PostboxDecoder) {
        if let value = decoder.decodeOptionalStringForKey("v") {
            self.value = .builtin(value)
        } else {
            self.value = .custom(decoder.decodeInt64ForKey("cfid", orElse: 0))
        }
        self.count = decoder.decodeInt32ForKey("c", orElse: 0)
        if let chosenOrder = decoder.decodeOptionalInt32ForKey("cord") {
            self.chosenOrder = Int(chosenOrder)
        } else if let isSelected = decoder.decodeOptionalInt32ForKey("s"), isSelected != 0 {
            self.chosenOrder = 0
        } else {
            self.chosenOrder = nil
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        
        if let value = try container.decodeIfPresent(String.self, forKey: "v") {
            self.value = .builtin(value)
        } else {
            self.value = .custom(try container.decode(Int64.self, forKey: "cfid"))
        }
        self.count = try container.decode(Int32.self, forKey: "c")
        if let chosenOrder = try container.decodeIfPresent(Int32.self, forKey: "cord") {
            self.chosenOrder = Int(chosenOrder)
        } else if let isSelected = try container.decodeIfPresent(Int32.self, forKey: "s"), isSelected != 0 {
            self.chosenOrder = 0
        } else {
            self.chosenOrder = nil
        }
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        switch self.value {
        case let .builtin(value):
            encoder.encodeString(value, forKey: "v")
        case let .custom(fileId):
            encoder.encodeInt64(fileId, forKey: "cfid")
        }
        encoder.encodeInt32(self.count, forKey: "c")
        if let chosenOrder = self.chosenOrder {
            encoder.encodeInt32(Int32(chosenOrder), forKey: "cord")
        } else {
            encoder.encodeNil(forKey: "cord")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        
        switch self.value {
        case let .builtin(value):
            try container.encode(value, forKey: "v")
        case let .custom(fileId):
            try container.encode(fileId, forKey: "cfid")
        }
        try container.encode(self.count, forKey: "c")
        try container.encodeIfPresent(self.chosenOrder.flatMap(Int32.init), forKey: "cord")
    }
}

extension MessageReaction.Reaction {
    init?(apiReaction: Api.Reaction) {
        switch apiReaction {
        case .reactionEmpty:
            return nil
        case let .reactionEmoji(emoticon):
            self = .builtin(emoticon)
        case let .reactionCustomEmoji(documentId):
            self = .custom(documentId)
        }
    }
    
    var apiReaction: Api.Reaction {
        switch self {
        case let .builtin(value):
            return .reactionEmoji(emoticon: value)
        case let .custom(fileId):
            return .reactionCustomEmoji(documentId: fileId)
        }
    }
}

public final class ReactionsMessageAttribute: Equatable, MessageAttribute {
    public static func messageTag(reaction: MessageReaction.Reaction) -> MemoryBuffer {
        let buffer = WriteBuffer()
        var prefix: UInt8 = 0
        buffer.write(&prefix, offset: 0, length: 1)
        switch reaction {
        case let .builtin(value):
            var stringData = value.data(using: .utf8) ?? Data()
            var length: UInt8 = UInt8(clamping: stringData.count)
            if stringData.count > Int(length) {
                stringData.count = Int(length)
            }
            var typeId: UInt8 = 0
            buffer.write(&typeId, offset: 0, length: 1)
            
            buffer.write(&length, offset: 0, length: 1)
            buffer.write(stringData)
        case var .custom(fileId):
            var typeId: UInt8 = 1
            buffer.write(&typeId, offset: 0, length: 1)
            buffer.write(&fileId, offset: 0, length: 8)
        }
        
        return buffer
    }
    
    public static func reactionFromMessageTag(tag: MemoryBuffer) -> MessageReaction.Reaction? {
        if tag.length < 2 {
            return nil
        }
        
        let readBuffer = ReadBuffer(memoryBufferNoCopy: tag)
        
        var prefix: UInt8 = 0
        readBuffer.read(&prefix, offset: 0, length: 1)
        if prefix != 0 {
            return nil
        }
        
        var typeId: UInt8 = 0
        readBuffer.read(&typeId, offset: 0, length: 1)
        switch typeId {
        case 0:
            var length8: UInt8 = 0
            readBuffer.read(&length8, offset: 0, length: 1)
            let length = Int(length8)
            if readBuffer.offset + length > readBuffer.length {
                return nil
            }
            let data = readBuffer.readData(length: length)
            guard let string = String(data: data, encoding: .utf8) else {
                return nil
            }
            return .builtin(string)
        case 1:
            if readBuffer.offset + 8 > readBuffer.length {
                return nil
            }
            var fileId: Int64 = 0
            readBuffer.read(&fileId, offset: 0, length: 8)
            return .custom(fileId)
        default:
            return nil
        }
    }
    
    public struct RecentPeer: Equatable, PostboxCoding {
        public var value: MessageReaction.Reaction
        public var isLarge: Bool
        public var isUnseen: Bool
        public var isMy: Bool
        public var peerId: PeerId
        public var timestamp: Int32?
        
        public init(value: MessageReaction.Reaction, isLarge: Bool, isUnseen: Bool, isMy: Bool, peerId: PeerId, timestamp: Int32?) {
            self.value = value
            self.isLarge = isLarge
            self.isUnseen = isUnseen
            self.isMy = isMy
            self.peerId = peerId
            self.timestamp = timestamp
        }
        
        public init(decoder: PostboxDecoder) {
            if let value = decoder.decodeOptionalStringForKey("v") {
                self.value = .builtin(value)
            } else {
                self.value = .custom(decoder.decodeInt64ForKey("cfid", orElse: 0))
            }
            self.isLarge = decoder.decodeInt32ForKey("l", orElse: 0) != 0
            self.isUnseen = decoder.decodeInt32ForKey("u", orElse: 0) != 0
            self.isMy = decoder.decodeInt32ForKey("my", orElse: 0) != 0
            self.peerId = PeerId(decoder.decodeInt64ForKey("p", orElse: 0))
            self.timestamp = decoder.decodeOptionalInt32ForKey("ts")
        }
        
        public func encode(_ encoder: PostboxEncoder) {
            switch self.value {
            case let .builtin(value):
                encoder.encodeString(value, forKey: "v")
            case let .custom(fileId):
                encoder.encodeInt64(fileId, forKey: "cfid")
            }
            encoder.encodeInt32(self.isLarge ? 1 : 0, forKey: "l")
            encoder.encodeInt32(self.isUnseen ? 1 : 0, forKey: "u")
            encoder.encodeInt32(self.isMy ? 1 : 0, forKey: "my")
            encoder.encodeInt64(self.peerId.toInt64(), forKey: "p")
            if let timestamp = self.timestamp {
                encoder.encodeInt32(timestamp, forKey: "ts")
            } else {
                encoder.encodeNil(forKey: "ts")
            }
        }
    }
    
    public let canViewList: Bool
    public let isTags: Bool
    public let reactions: [MessageReaction]
    public let recentPeers: [RecentPeer]
    
    public var associatedPeerIds: [PeerId] {
        return self.recentPeers.map(\.peerId)
    }
    
    public var associatedMediaIds: [MediaId] {
        var result: [MediaId] = []
        
        for reaction in self.reactions {
            switch reaction.value {
            case .builtin:
                break
            case let .custom(fileId):
                let mediaId = MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)
                if !result.contains(mediaId) {
                    result.append(mediaId)
                }
            }
        }
        
        return result
    }
    
    public init(canViewList: Bool, isTags: Bool, reactions: [MessageReaction], recentPeers: [RecentPeer]) {
        self.canViewList = canViewList
        self.isTags = isTags
        self.reactions = reactions
        self.recentPeers = recentPeers
    }
    
    required public init(decoder: PostboxDecoder) {
        self.canViewList = decoder.decodeBoolForKey("vl", orElse: true)
        self.isTags = decoder.decodeBoolForKey("tg", orElse: false)
        self.reactions = decoder.decodeObjectArrayWithDecoderForKey("r")
        self.recentPeers = decoder.decodeObjectArrayWithDecoderForKey("rp")
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeBool(self.canViewList, forKey: "vl")
        encoder.encodeBool(self.isTags, forKey: "tg")
        encoder.encodeObjectArray(self.reactions, forKey: "r")
        encoder.encodeObjectArray(self.recentPeers, forKey: "rp")
    }
    
    public static func ==(lhs: ReactionsMessageAttribute, rhs: ReactionsMessageAttribute) -> Bool {
        if lhs.canViewList != rhs.canViewList {
            return false
        }
        if lhs.isTags != rhs.isTags {
            return false
        }
        if lhs.reactions != rhs.reactions {
            return false
        }
        if lhs.recentPeers != rhs.recentPeers {
            return false
        }
        return true
    }
    
    public var hasUnseen: Bool {
        for recentPeer in self.recentPeers {
            if recentPeer.isUnseen {
                return true
            }
        }
        return false
    }
    
    public func withAllSeen() -> ReactionsMessageAttribute {
        return ReactionsMessageAttribute(
            canViewList: self.canViewList,
            isTags: self.isTags,
            reactions: self.reactions,
            recentPeers: self.recentPeers.map { recentPeer in
                var recentPeer = recentPeer
                recentPeer.isUnseen = false
                return recentPeer
            }
        )
    }
}

public final class PendingReactionsMessageAttribute: MessageAttribute {
    public struct PendingReaction: Equatable, PostboxCoding {
        public var value: MessageReaction.Reaction
        public var sendAsPeerId: PeerId?
        
        public init(value: MessageReaction.Reaction, sendAsPeerId: PeerId?) {
            self.value = value
            self.sendAsPeerId = sendAsPeerId
        }
        
        public init(decoder: PostboxDecoder) {
            self.value = decoder.decodeObjectForKey("val", decoder: { MessageReaction.Reaction(decoder: $0) }) as! MessageReaction.Reaction
            self.sendAsPeerId = decoder.decodeOptionalInt64ForKey("sa").flatMap(PeerId.init)
        }
        
        public func encode(_ encoder: PostboxEncoder) {
            encoder.encodeObject(self.value, forKey: "val")
            if let sendAsPeerId = self.sendAsPeerId {
                encoder.encodeInt64(sendAsPeerId.toInt64(), forKey: "sa")
            } else {
                encoder.encodeNil(forKey: "sa")
            }
        }
    }
    
    public let accountPeerId: PeerId?
    public let reactions: [PendingReaction]
    public let isLarge: Bool
    public let storeAsRecentlyUsed: Bool
    public let isTags: Bool
    
    public var associatedPeerIds: [PeerId] {
        var peerIds: [PeerId] = []
        if let accountPeerId = self.accountPeerId {
            peerIds.append(accountPeerId)
        }
        for reaction in self.reactions {
            if let sendAsPeerId = reaction.sendAsPeerId {
                if !peerIds.contains(sendAsPeerId) {
                    peerIds.append(sendAsPeerId)
                }
            }
        }
        return peerIds
    }
    
    public var associatedMediaIds: [MediaId] {
        var result: [MediaId] = []
        
        for reaction in self.reactions {
            switch reaction.value {
            case .builtin:
                break
            case let .custom(fileId):
                let mediaId = MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)
                if !result.contains(mediaId) {
                    result.append(mediaId)
                }
            }
        }
        
        return result
    }
    
    public init(accountPeerId: PeerId?, reactions: [PendingReaction], isLarge: Bool, storeAsRecentlyUsed: Bool, isTags: Bool) {
        self.accountPeerId = accountPeerId
        self.reactions = reactions
        self.isLarge = isLarge
        self.storeAsRecentlyUsed = storeAsRecentlyUsed
        self.isTags = isTags
    }
    
    required public init(decoder: PostboxDecoder) {
        self.accountPeerId = decoder.decodeOptionalInt64ForKey("ap").flatMap(PeerId.init)
        self.reactions = decoder.decodeObjectArrayWithDecoderForKey("reac")
        self.isLarge = decoder.decodeInt32ForKey("l", orElse: 0) != 0
        self.storeAsRecentlyUsed = decoder.decodeInt32ForKey("used", orElse: 0) != 0
        self.isTags = decoder.decodeBoolForKey("itag", orElse: false)
    }
    
    public func encode(_ encoder: PostboxEncoder) {
        if let accountPeerId = self.accountPeerId {
            encoder.encodeInt64(accountPeerId.toInt64(), forKey: "ap")
        } else {
            encoder.encodeNil(forKey: "ap")
        }
        
        encoder.encodeObjectArray(self.reactions, forKey: "reac")
        
        encoder.encodeInt32(self.isLarge ? 1 : 0, forKey: "l")
        encoder.encodeInt32(self.storeAsRecentlyUsed ? 1 : 0, forKey: "used")
        encoder.encodeBool(self.isTags, forKey: "itag")
    }
}
