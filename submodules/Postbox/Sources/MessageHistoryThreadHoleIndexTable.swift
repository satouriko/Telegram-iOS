import Foundation

private func decomposeKey(_ key: ValueBoxKey) -> (threadId: Int64, id: MessageId, space: MessageHistoryHoleSpace) {
    let tag = MessageTags(rawValue: key.getUInt32(8 + 8 + 4))
    let space: MessageHistoryHoleSpace
    if tag.rawValue == 0 {
        space = .everywhere
    } else {
        space = .tag(tag)
    }
    return (key.getInt64(8), MessageId(peerId: PeerId(key.getInt64(0)), namespace: key.getInt32(8 + 8), id: key.getInt32(8 + 8 + 4 + 4)), space)
}

private func decodeValue(value: ReadBuffer, peerId: PeerId, namespace: MessageId.Namespace) -> MessageId {
    var id: Int32 = 0
    value.read(&id, offset: 0, length: 4)
    return MessageId(peerId: peerId, namespace: namespace, id: id)
}

final class MessageHistoryThreadHoleIndexTable: Table {
    static func tableSpec(_ id: Int32) -> ValueBoxTable {
        return ValueBoxTable(id: id, keyType: .binary, compactValuesOnCreation: true)
    }
    
    let metadataTable: MessageHistoryMetadataTable
    let seedConfiguration: SeedConfiguration
    
    init(valueBox: ValueBox, table: ValueBoxTable, useCaches: Bool, metadataTable: MessageHistoryMetadataTable, seedConfiguration: SeedConfiguration) {
        self.seedConfiguration = seedConfiguration
        self.metadataTable = metadataTable
        
        super.init(valueBox: valueBox, table: table, useCaches: useCaches)
    }
    
    private func key(threadId: Int64, id: MessageId, space: MessageHistoryHoleSpace) -> ValueBoxKey {
        let key = ValueBoxKey(length: 8 + 8 + 4 + 4 + 4)
        key.setInt64(0, value: id.peerId.toInt64())
        key.setInt64(8, value: threadId)
        key.setInt32(8 + 8, value: id.namespace)
        let tagValue: UInt32
        switch space {
            case .everywhere:
                tagValue = 0
            case let .tag(tag):
                tagValue = tag.rawValue
        }
        key.setUInt32(8 + 8 + 4, value: tagValue)
        key.setInt32(8 + 8 + 4 + 4, value: id.id)
        return key
    }
    
    private func lowerBound(peerId: PeerId, threadId: Int64) -> ValueBoxKey {
        let key = ValueBoxKey(length: 8 + 8)
        key.setInt64(0, value: peerId.toInt64())
        key.setInt64(8, value: threadId)
        return key
    }
    
    private func upperBound(peerId: PeerId, threadId: Int64) -> ValueBoxKey {
        return self.lowerBound(peerId: peerId, threadId: threadId).successor
    }
    
    private func lowerBound(peerId: PeerId, threadId: Int64, namespace: MessageId.Namespace, space: MessageHistoryHoleSpace) -> ValueBoxKey {
        let key = ValueBoxKey(length: 8 + 8 + 4 + 4)
        key.setInt64(0, value: peerId.toInt64())
        key.setInt64(8, value: threadId)
        key.setInt32(8 + 8, value: namespace)
        let tagValue: UInt32
        switch space {
            case .everywhere:
                tagValue = 0
            case let .tag(tag):
                tagValue = tag.rawValue
        }
        key.setUInt32(8 + 8 + 4, value: tagValue)
        return key
    }
    
    private func upperBound(peerId: PeerId, threadId: Int64, namespace: MessageId.Namespace, space: MessageHistoryHoleSpace) -> ValueBoxKey {
        let key = ValueBoxKey(length: 8 + 8 + 4 + 4)
        key.setInt64(0, value: peerId.toInt64())
        key.setInt64(8, value: threadId)
        key.setInt32(8 + 8, value: namespace)
        let tagValue: UInt32
        switch space {
            case .everywhere:
                tagValue = 0
            case let .tag(tag):
                tagValue = tag.rawValue
        }
        key.setUInt32(8 + 8 + 4, value: tagValue)
        return key.successor
    }
    
    private func namespaceLowerBound(peerId: PeerId, threadId: Int64, namespace: MessageId.Namespace) -> ValueBoxKey {
        let key = ValueBoxKey(length: 8 + 8 + 4)
        key.setInt64(0, value: peerId.toInt64())
        key.setInt64(8, value: threadId)
        key.setInt32(8 + 8, value: namespace)
        return key
    }
    
    private func namespaceUpperBound(peerId: PeerId, threadId: Int64, namespace: MessageId.Namespace) -> ValueBoxKey {
        let key = ValueBoxKey(length: 8 + 8 + 4)
        key.setInt64(0, value: peerId.toInt64())
        key.setInt64(8, value: threadId)
        key.setInt32(8 + 8, value: namespace)
        return key.successor
    }
    
    private func ensureInitialized(peerId: PeerId, threadId: Int64) {
        if !self.metadataTable.isThreadHoleIndexInitialized(peerId: peerId, threadId: threadId) {
            postboxLog("MessageHistoryThreadHoleIndexTable: Initializing \(peerId) \(threadId)")
            self.metadataTable.setIsThreadHoleIndexInitialized(peerId: peerId, threadId: threadId)
            
            if let messageNamespaces = self.seedConfiguration.messageThreadHoles[peerId.namespace] {
                for namespace in messageNamespaces {
                    var operations: [MessageHistoryIndexHoleOperationKey: [MessageHistoryIndexHoleOperation]] = [:]
                    self.add(peerId: peerId, threadId: threadId, namespace: namespace, space: .everywhere, range: 1 ... (Int32.max - 1), operations: &operations)
                }
            }
        }
    }
    
    func existingNamespaces(peerId: PeerId, threadId: Int64, holeSpace: MessageHistoryHoleSpace) -> Set<MessageId.Namespace> {
        self.ensureInitialized(peerId: peerId, threadId: threadId)
        
        var result = Set<MessageId.Namespace>()
        var currentLowerBound = self.lowerBound(peerId: peerId, threadId: threadId)
        let upperBound = self.upperBound(peerId: peerId, threadId: threadId)
        while true {
            var idAndSpace: (Int64, MessageId, MessageHistoryHoleSpace)?
            self.valueBox.range(self.table, start: currentLowerBound, end: upperBound, keys: { key in
                idAndSpace = decomposeKey(key)
                return false
            }, limit: 1)
            if let (_, id, space) = idAndSpace {
                if space == holeSpace {
                    result.insert(id.namespace)
                }
                currentLowerBound = self.upperBound(peerId: peerId, threadId: threadId, namespace: id.namespace, space: space)
            } else {
                break
            }
        }
        return result
    }
    
    private func scanSpaces(peerId: PeerId, threadId: Int64, namespace: MessageId.Namespace) -> [MessageHistoryHoleSpace] {
        self.ensureInitialized(peerId: peerId, threadId: threadId)
        
        var currentLowerBound = self.namespaceLowerBound(peerId: peerId, threadId: threadId, namespace: namespace)
        var result: [MessageHistoryHoleSpace] = []
        while true {
            var found = false
            self.valueBox.range(self.table, start: currentLowerBound, end: self.namespaceUpperBound(peerId: peerId, threadId: threadId, namespace: namespace), keys: { key in
                let space = decomposeKey(key).space
                result.append(space)
                currentLowerBound = self.upperBound(peerId: peerId, threadId: threadId, namespace: namespace, space: space)
                found = true
                return false
            }, limit: 1)
            if !found {
                break
            }
        }
        assert(Set(result).count == result.count)
        return result
    }
    
    func containing(threadId: Int64, id: MessageId) -> [MessageHistoryHoleSpace: ClosedRange<MessageId.Id>] {
        self.ensureInitialized(peerId: id.peerId, threadId: threadId)
        
        var result: [MessageHistoryHoleSpace: ClosedRange<MessageId.Id>] = [:]
        for space in self.scanSpaces(peerId: id.peerId, threadId: threadId, namespace: id.namespace) {
            self.valueBox.range(self.table, start: self.key(threadId: threadId, id: id, space: space), end: self.upperBound(peerId: id.peerId, threadId: threadId, namespace: id.namespace, space: space), values: { key, value in
                let (keyThreadId, upperId, keySpace) = decomposeKey(key)
                assert(keyThreadId == threadId)
                assert(keySpace == space)
                assert(upperId.peerId == id.peerId)
                assert(upperId.namespace == id.namespace)
                let lowerId = decodeValue(value: value, peerId: id.peerId, namespace: id.namespace)
                let holeRange: ClosedRange<MessageId.Id> = lowerId.id ... upperId.id
                result[space] = holeRange
                return false
            }, limit: 1)
        }
        return result
    }
    
    func latest(peerId: PeerId, threadId: Int64, namespace: MessageId.Namespace, space: MessageHistoryHoleSpace) -> ClosedRange<MessageId.Id>? {
        self.ensureInitialized(peerId: peerId, threadId: threadId)
        
        var result: ClosedRange<MessageId.Id>?
        self.valueBox.range(self.table, start: self.upperBound(peerId: peerId, threadId: threadId, namespace: namespace, space: space), end: self.lowerBound(peerId: peerId, threadId: threadId, namespace: namespace, space: space), values: { key, value in
            
            let (keyThreadId, upperId, keySpace) = decomposeKey(key)
            assert(keyThreadId == threadId)
            assert(keySpace == space)
            assert(upperId.peerId == peerId)
            assert(upperId.namespace == namespace)
            let lowerId = decodeValue(value: value, peerId: peerId, namespace: namespace)
            result = lowerId.id ... upperId.id
            
            return false
        }, limit: 1)
        
        return result
    }
    
    func closest(peerId: PeerId, threadId: Int64, namespace: MessageId.Namespace, space: MessageHistoryHoleSpace, range: ClosedRange<MessageId.Id>) -> IndexSet {
        self.ensureInitialized(peerId: peerId, threadId: threadId)
        
        var result = IndexSet()
        
        func processIntersectingRange(_ key: ValueBoxKey, _ value: ReadBuffer) {
            let (keyThreadId, upperId, keySpace) = decomposeKey(key)
            assert(keyThreadId == threadId)
            assert(keySpace == space)
            assert(upperId.peerId == peerId)
            assert(upperId.namespace == namespace)
            let lowerId = decodeValue(value: value, peerId: peerId, namespace: namespace)
            let holeRange: ClosedRange<MessageId.Id> = lowerId.id ... upperId.id
            if holeRange.overlaps(range) {
                result.insert(integersIn: Int(holeRange.lowerBound) ... Int(holeRange.upperBound))
            }
        }
        
        func processEdgeRange(_ key: ValueBoxKey, _ value: ReadBuffer) {
            let (keyThreadId, upperId, keySpace) = decomposeKey(key)
            assert(keyThreadId == threadId)
            assert(keySpace == space)
            assert(upperId.peerId == peerId)
            assert(upperId.namespace == namespace)
            let lowerId = decodeValue(value: value, peerId: peerId, namespace: namespace)
            let holeRange: ClosedRange<MessageId.Id> = lowerId.id ... upperId.id
            result.insert(integersIn: Int(holeRange.lowerBound) ... Int(holeRange.upperBound))
        }
        
        self.valueBox.range(self.table, start: self.key(threadId: threadId, id: MessageId(peerId: peerId, namespace: namespace, id: range.lowerBound), space: space).predecessor, end: self.key(threadId: threadId, id: MessageId(peerId: peerId, namespace: namespace, id: range.upperBound), space: space).successor, values: { key, value in
            processIntersectingRange(key, value)
            return true
        }, limit: 0)
        
        self.valueBox.range(self.table, start: self.key(threadId: threadId, id: MessageId(peerId: peerId, namespace: namespace, id: range.upperBound), space: space), end: self.upperBound(peerId: peerId, threadId: threadId, namespace: namespace, space: space), values: { key, value in
            processIntersectingRange(key, value)
            return true
        }, limit: 1)
        
        if !result.contains(Int(range.lowerBound)) {
            self.valueBox.range(self.table, start: self.key(threadId: threadId, id: MessageId(peerId: peerId, namespace: namespace, id: range.lowerBound), space: space), end: self.lowerBound(peerId: peerId, threadId: threadId, namespace: namespace, space: space), values: { key, value in
                processEdgeRange(key, value)
                return true
            }, limit: 1)
        }
        if !result.contains(Int(range.upperBound)) {
            self.valueBox.range(self.table, start: self.key(threadId: threadId, id: MessageId(peerId: peerId, namespace: namespace, id: range.upperBound), space: space), end: self.upperBound(peerId: peerId, threadId: threadId, namespace: namespace, space: space), values: { key, value in
                processEdgeRange(key, value)
                return true
            }, limit: 1)
        }
        
        return result
    }
    
    func add(peerId: PeerId, threadId: Int64, namespace: MessageId.Namespace, space: MessageHistoryHoleSpace, range: ClosedRange<MessageId.Id>, operations: inout [MessageHistoryIndexHoleOperationKey: [MessageHistoryIndexHoleOperation]]) {
        self.ensureInitialized(peerId: peerId, threadId: threadId)
        
        self.addInternal(peerId: peerId, threadId: threadId, namespace: namespace, space: space, range: range, operations: &operations)
        
        /*switch space {
            case .everywhere:
                if let namespaceHoleTags = self.seedConfiguration.messageHoles[peerId.namespace]?[namespace] {
                    for tag in namespaceHoleTags {
                        self.addInternal(peerId: peerId, threadId: threadId, namespace: namespace, space: .tag(tag), range: range, operations: &operations)
                    }
                }
            case .tag:
                break
        }*/
    }
    
    private func addInternal(peerId: PeerId, threadId: Int64, namespace: MessageId.Namespace, space: MessageHistoryHoleSpace, range: ClosedRange<MessageId.Id>, operations: inout [MessageHistoryIndexHoleOperationKey: [MessageHistoryIndexHoleOperation]]) {
        let clippedLowerBound = max(1, range.lowerBound)
        let clippedUpperBound = min(Int32.max - 1, range.upperBound)
        if clippedLowerBound > clippedUpperBound {
            return
        }
        let clippedRange = clippedLowerBound ... clippedUpperBound
        
        var insertedIndices = IndexSet()
        var removeKeys: [Int32] = []
        var insertRanges = IndexSet()
        
        var alreadyMapped = false
        
        func processRange(_ key: ValueBoxKey, _ value: ReadBuffer) {
            let (keyThreadId, upperId, keySpace) = decomposeKey(key)
            assert(keyThreadId == threadId)
            assert(keySpace == space)
            assert(upperId.peerId == peerId)
            assert(upperId.namespace == namespace)
            let lowerId = decodeValue(value: value, peerId: peerId, namespace: namespace)
            let holeRange: ClosedRange<Int32> = lowerId.id ... upperId.id
            if clippedRange.lowerBound >= holeRange.lowerBound && clippedRange.upperBound <= holeRange.upperBound {
                alreadyMapped = true
                return
            } else if clippedRange.overlaps(holeRange) || (holeRange.upperBound != Int32.max && clippedRange.lowerBound == holeRange.upperBound + 1) || clippedRange.upperBound == holeRange.lowerBound - 1 {
                removeKeys.append(upperId.id)
                let unionRange: ClosedRange = min(clippedRange.lowerBound, holeRange.lowerBound) ... max(clippedRange.upperBound, holeRange.upperBound)
                insertRanges.insert(integersIn: Int(unionRange.lowerBound) ... Int(unionRange.upperBound))
            }
        }
        
        let lowerScanBound = max(0, clippedRange.lowerBound - 2)
        
        self.valueBox.range(self.table, start: self.key(threadId: threadId, id: MessageId(peerId: peerId, namespace: namespace, id: lowerScanBound), space: space), end: self.key(threadId: threadId, id: MessageId(peerId: peerId, namespace: namespace, id: clippedRange.upperBound), space: space).successor, values: { key, value in
            processRange(key, value)
            if alreadyMapped {
                return false
            }
            return true
        }, limit: 0)
        
        if !alreadyMapped {
            self.valueBox.range(self.table, start: self.key(threadId: threadId, id: MessageId(peerId: peerId, namespace: namespace, id: clippedRange.upperBound), space: space), end: self.upperBound(peerId: peerId, threadId: threadId, namespace: namespace, space: space), values: { key, value in
                processRange(key, value)
                if alreadyMapped {
                    return false
                }
                return true
            }, limit: 1)
        }
        
        if alreadyMapped {
            return
        }
        
        insertRanges.insert(integersIn: Int(clippedRange.lowerBound) ... Int(clippedRange.upperBound))
        insertedIndices.insert(integersIn: Int(clippedRange.lowerBound) ... Int(clippedRange.upperBound))
        
        for id in removeKeys {
            self.valueBox.remove(self.table, key: self.key(threadId: threadId, id: MessageId(peerId: peerId, namespace: namespace, id: id), space: space), secure: false)
        }
        
        for insertRange in insertRanges.rangeView {
            let closedRange: ClosedRange<MessageId.Id> = Int32(insertRange.lowerBound) ... Int32(insertRange.upperBound - 1)
            var lowerBound: Int32 = closedRange.lowerBound
            self.valueBox.set(self.table, key: self.key(threadId: threadId, id: MessageId(peerId: peerId, namespace: namespace, id: closedRange.upperBound), space: space), value: MemoryBuffer(memory: &lowerBound, capacity: 4, length: 4, freeWhenDone: false))
        }
        
        addMessageHistoryHoleOperation(.insert(clippedRange), peerId: peerId, threadId: threadId, namespace: namespace, space: MessageHistoryHoleOperationSpace(space), to: &operations)
    }
    
    func remove(peerId: PeerId, threadId: Int64, namespace: MessageId.Namespace, space: MessageHistoryHoleSpace, range: ClosedRange<MessageId.Id>, operations: inout [MessageHistoryIndexHoleOperationKey: [MessageHistoryIndexHoleOperation]]) {
        self.ensureInitialized(peerId: peerId, threadId: threadId)
        
        self.removeInternal(peerId: peerId, threadId: threadId, namespace: namespace, space: space, range: range, operations: &operations)
        
        switch space {
            case .everywhere:
                if let namespaceHoleTags = self.seedConfiguration.messageHoles[peerId.namespace]?[namespace] {
                    for tag in namespaceHoleTags {
                        self.removeInternal(peerId: peerId, threadId: threadId, namespace: namespace, space: .tag(tag), range: range, operations: &operations)
                    }
                }
            case .tag:
                break
        }
    }
    
    private func removeInternal(peerId: PeerId, threadId: Int64, namespace: MessageId.Namespace, space: MessageHistoryHoleSpace, range: ClosedRange<MessageId.Id>, operations: inout [MessageHistoryIndexHoleOperationKey: [MessageHistoryIndexHoleOperation]]) {
        var removeKeys: [Int32] = []
        var insertRanges = IndexSet()
        
        func processRange(_ key: ValueBoxKey, _ value: ReadBuffer) {
            let (keyThreadId, upperId, keySpace) = decomposeKey(key)
            assert(keyThreadId == threadId)
            assert(keySpace == space)
            assert(upperId.peerId == peerId)
            assert(upperId.namespace == namespace)
            let lowerId = decodeValue(value: value, peerId: peerId, namespace: namespace)
            let holeRange: ClosedRange<MessageId.Id> = lowerId.id ... upperId.id
            if range.lowerBound <= holeRange.lowerBound && range.upperBound >= holeRange.upperBound {
                removeKeys.append(upperId.id)
            } else if range.overlaps(holeRange) {
                removeKeys.append(upperId.id)
                var holeIndices = IndexSet(integersIn: Int(holeRange.lowerBound) ... Int(holeRange.upperBound))
                holeIndices.remove(integersIn: Int(range.lowerBound) ... Int(range.upperBound))
                insertRanges.formUnion(holeIndices)
            }
        }
        
        let lowerScanBound = max(0, range.lowerBound - 2)
        
        self.valueBox.range(self.table, start: self.key(threadId: threadId, id: MessageId(peerId: peerId, namespace: namespace, id: lowerScanBound), space: space), end: self.key(threadId: threadId, id: MessageId(peerId: peerId, namespace: namespace, id: range.upperBound), space: space).successor, values: { key, value in
            processRange(key, value)
            return true
        }, limit: 0)
        
        self.valueBox.range(self.table, start: self.key(threadId: threadId, id: MessageId(peerId: peerId, namespace: namespace, id: range.upperBound), space: space), end: self.upperBound(peerId: peerId, threadId: threadId, namespace: namespace, space: space), values: { key, value in
            processRange(key, value)
            return true
        }, limit: 1)
        
        for id in removeKeys {
            self.valueBox.remove(self.table, key: self.key(threadId: threadId, id: MessageId(peerId: peerId, namespace: namespace, id: id), space: space), secure: false)
        }
        
        for insertRange in insertRanges.rangeView {
            let closedRange: ClosedRange<MessageId.Id> = Int32(insertRange.lowerBound) ... Int32(insertRange.upperBound - 1)
            var lowerBound: Int32 = closedRange.lowerBound
            self.valueBox.set(self.table, key: self.key(threadId: threadId, id: MessageId(peerId: peerId, namespace: namespace, id: closedRange.upperBound), space: space), value: MemoryBuffer(memory: &lowerBound, capacity: 4, length: 4, freeWhenDone: false))
        }
        
        if !removeKeys.isEmpty {
            addMessageHistoryHoleOperation(.remove(range), peerId: peerId, threadId: threadId, namespace: namespace, space: MessageHistoryHoleOperationSpace(space), to: &operations)
        }
    }
    
    func debugList(peerId: PeerId, threadId: Int64, namespace: MessageId.Namespace, space: MessageHistoryHoleSpace) -> [ClosedRange<MessageId.Id>] {
        var result: [ClosedRange<MessageId.Id>] = []
        self.valueBox.range(self.table, start: self.lowerBound(peerId: peerId, threadId: threadId, namespace: namespace, space: space), end: self.upperBound(peerId: peerId, threadId: threadId, namespace: namespace, space: space), values: { key, value in
            let (keyThreadId, upperId, keySpace) = decomposeKey(key)
            assert(keyThreadId == threadId)
            assert(keySpace == space)
            assert(upperId.peerId == peerId)
            assert(upperId.namespace == namespace)
            let lowerId = decodeValue(value: value, peerId: peerId, namespace: namespace)
            let holeRange: ClosedRange<MessageId.Id> = lowerId.id ... upperId.id
            result.append(holeRange)
            return true
        }, limit: 0)
        return result
    }
}
