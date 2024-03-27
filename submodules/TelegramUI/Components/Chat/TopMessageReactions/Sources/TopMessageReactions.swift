import Foundation
import SwiftSignalKit
import TelegramCore
import Postbox
import AccountContext
import ReactionSelectionNode

public enum AllowedReactions {
    case set(Set<MessageReaction.Reaction>)
    case all
}

public func peerMessageAllowedReactions(context: AccountContext, message: Message) -> Signal<AllowedReactions?, NoError> {
    if message.id.peerId == context.account.peerId {
        return .single(.all)
    }
    
    if message.containsSecretMedia {
        return .single(AllowedReactions.set(Set()))
    }
    
    return combineLatest(
        context.engine.data.get(
            TelegramEngine.EngineData.Item.Peer.Peer(id: message.id.peerId),
            TelegramEngine.EngineData.Item.Peer.AllowedReactions(id: message.id.peerId)
        ),
        context.engine.stickers.availableReactions() |> take(1)
    )
    |> map { data, availableReactions -> AllowedReactions? in
        let (peer, allowedReactions) = data
        
        if let effectiveReactions = message.effectiveReactions(isTags: message.areReactionsTags(accountPeerId: context.account.peerId)), effectiveReactions.count >= 11 {
            return .set(Set(effectiveReactions.map(\.value)))
        }
        
        switch allowedReactions {
        case .unknown:
            if case let .channel(channel) = peer, case .broadcast = channel.info {
                if let availableReactions = availableReactions {
                    return .set(Set(availableReactions.reactions.map(\.value)))
                } else {
                    return .set(Set())
                }
            }
            return .all
        case let .known(value):
            switch value {
            case .all:
                if case let .channel(channel) = peer, case .broadcast = channel.info {
                    if let availableReactions = availableReactions {
                        return .set(Set(availableReactions.reactions.map(\.value)))
                    } else {
                        return .set(Set())
                    }
                }
                return .all
            case let .limited(reactions):
                return .set(Set(reactions))
            case .empty:
                return .set(Set())
            }
        }
    }
}

public func tagMessageReactions(context: AccountContext, subPeerId: EnginePeer.Id?) -> Signal<[ReactionItem], NoError> {
    let topTags: Signal<([MessageReaction.Reaction], [Int64: TelegramMediaFile]), NoError> = context.engine.data.get(TelegramEngine.EngineData.Item.Messages.SavedMessageTagStats(peerId: context.account.peerId, threadId: subPeerId?.toInt64()))
    |> mapToSignal { tagStats -> Signal<([MessageReaction.Reaction], [Int64: TelegramMediaFile]), NoError> in
        let reactions = tagStats.sorted(by: { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value > rhs.value
            }
            return lhs.key < rhs.key
        }).filter({ $0.value > 0 }).map(\.key)
        
        var customFileIds: [Int64] = []
        for reaction in reactions {
            if case let .custom(fileId) = reaction {
                if !customFileIds.contains(fileId) {
                    customFileIds.append(fileId)
                }
            }
        }
        
        return context.engine.stickers.resolveInlineStickersLocal(fileIds: customFileIds)
        |> map { files -> ([MessageReaction.Reaction], [Int64: TelegramMediaFile]) in
            return (reactions, files)
        }
    }
    
    return combineLatest(
        context.engine.stickers.availableReactions(),
        context.account.postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudDefaultTagReactions], namespaces: [ItemCollectionId.Namespace.max - 1], aroundIndex: nil, count: 10000000),
        topTags
    )
    |> take(1)
    |> map { availableReactions, view, topTags -> [ReactionItem] in
        var defaultTagReactions: OrderedItemListView?
        for orderedView in view.orderedItemListsViews {
            if orderedView.collectionId == Namespaces.OrderedItemList.CloudDefaultTagReactions {
                defaultTagReactions = orderedView
            }
        }
        
        var result: [ReactionItem] = []
        var existingIds = Set<MessageReaction.Reaction>()
        
        for reactionValue in topTags.0 {
            switch reactionValue {
            case let .builtin(value):
                if let reaction = availableReactions?.reactions.first(where: { $0.value == .builtin(value) }) {
                    guard let centerAnimation = reaction.centerAnimation else {
                        continue
                    }
                    guard let aroundAnimation = reaction.aroundAnimation else {
                        continue
                    }
                    
                    if existingIds.contains(reaction.value) {
                        continue
                    }
                    existingIds.insert(reaction.value)
                    
                    result.append(ReactionItem(
                        reaction: ReactionItem.Reaction(rawValue: reaction.value),
                        appearAnimation: reaction.appearAnimation,
                        stillAnimation: reaction.selectAnimation,
                        listAnimation: centerAnimation,
                        largeListAnimation: reaction.activateAnimation,
                        applicationAnimation: aroundAnimation,
                        largeApplicationAnimation: reaction.effectAnimation,
                        isCustom: false
                    ))
                } else {
                    continue
                }
            case let .custom(fileId):
                guard let file = topTags.1[fileId] else {
                    continue
                }
                
                if existingIds.contains(.custom(file.fileId.id)) {
                    continue
                }
                existingIds.insert(.custom(file.fileId.id))
                
                result.append(ReactionItem(
                    reaction: ReactionItem.Reaction(rawValue: .custom(file.fileId.id)),
                    appearAnimation: file,
                    stillAnimation: file,
                    listAnimation: file,
                    largeListAnimation: file,
                    applicationAnimation: nil,
                    largeApplicationAnimation: nil,
                    isCustom: true
                ))
            }
        }
        
        if let defaultTagReactions {
            for item in defaultTagReactions.items {
                guard let topReaction = item.contents.get(RecentReactionItem.self) else {
                    continue
                }
                switch topReaction.content {
                case let .builtin(value):
                    if let reaction = availableReactions?.reactions.first(where: { $0.value == .builtin(value) }) {
                        guard let centerAnimation = reaction.centerAnimation else {
                            continue
                        }
                        guard let aroundAnimation = reaction.aroundAnimation else {
                            continue
                        }
                        
                        if existingIds.contains(reaction.value) {
                            continue
                        }
                        existingIds.insert(reaction.value)
                        
                        result.append(ReactionItem(
                            reaction: ReactionItem.Reaction(rawValue: reaction.value),
                            appearAnimation: reaction.appearAnimation,
                            stillAnimation: reaction.selectAnimation,
                            listAnimation: centerAnimation,
                            largeListAnimation: reaction.activateAnimation,
                            applicationAnimation: aroundAnimation,
                            largeApplicationAnimation: reaction.effectAnimation,
                            isCustom: false
                        ))
                    } else {
                        continue
                    }
                case let .custom(file):
                    if existingIds.contains(.custom(file.fileId.id)) {
                        continue
                    }
                    existingIds.insert(.custom(file.fileId.id))
                    
                    result.append(ReactionItem(
                        reaction: ReactionItem.Reaction(rawValue: .custom(file.fileId.id)),
                        appearAnimation: file,
                        stillAnimation: file,
                        listAnimation: file,
                        largeListAnimation: file,
                        applicationAnimation: nil,
                        largeApplicationAnimation: nil,
                        isCustom: true
                    ))
                }
            }
        }
        
        return result
    }
}

public func topMessageReactions(context: AccountContext, message: Message, subPeerId: EnginePeer.Id?) -> Signal<[ReactionItem], NoError> {
    if message.id.peerId == context.account.peerId {
        var loadTags = false
        if let effectiveReactionsAttribute = message.effectiveReactionsAttribute(isTags: message.areReactionsTags(accountPeerId: context.account.peerId)) {
            loadTags = true
            if !effectiveReactionsAttribute.reactions.isEmpty {
                if !effectiveReactionsAttribute.isTags {
                    loadTags = false
                }
            }
        } else {
            loadTags = true
        }
        
        if loadTags {
            return tagMessageReactions(context: context, subPeerId: subPeerId)
        }
    }
    
    let viewKey: PostboxViewKey = .orderedItemList(id: Namespaces.OrderedItemList.CloudTopReactions)
    let topReactions = context.account.postbox.combinedView(keys: [viewKey])
    |> map { views -> [RecentReactionItem] in
        guard let view = views.views[viewKey] as? OrderedItemListView else {
            return []
        }
        return view.items.compactMap { item -> RecentReactionItem? in
            return item.contents.get(RecentReactionItem.self)
        }
    }
    
    let allowedReactionsWithFiles: Signal<(reactions: AllowedReactions, files: [Int64: TelegramMediaFile])?, NoError> = peerMessageAllowedReactions(context: context, message: message)
    |> mapToSignal { allowedReactions -> Signal<(reactions: AllowedReactions, files: [Int64: TelegramMediaFile])?, NoError> in
        guard let allowedReactions = allowedReactions else {
            return .single(nil)
        }
        if case let .set(reactions) = allowedReactions {
            return context.engine.stickers.resolveInlineStickers(fileIds: reactions.compactMap { item -> Int64? in
                switch item {
                case .builtin:
                    return nil
                case let .custom(fileId):
                    return fileId
                }
            })
            |> map { files -> (reactions: AllowedReactions, files: [Int64: TelegramMediaFile]) in
                return (allowedReactions, files)
            }
        } else {
            return .single((allowedReactions, [:]))
        }
    }

    return combineLatest(
        context.engine.stickers.availableReactions(),
        allowedReactionsWithFiles,
        topReactions
    )
    |> take(1)
    |> map { availableReactions, allowedReactionsAndFiles, topReactions -> [ReactionItem] in
        guard let availableReactions = availableReactions, let allowedReactionsAndFiles = allowedReactionsAndFiles else {
            return []
        }
        
        var result: [ReactionItem] = []
        var existingIds = Set<MessageReaction.Reaction>()
        
        for topReaction in topReactions {
            switch topReaction.content {
            case let .builtin(value):
                if let reaction = availableReactions.reactions.first(where: { $0.value == .builtin(value) }) {
                    guard let centerAnimation = reaction.centerAnimation else {
                        continue
                    }
                    guard let aroundAnimation = reaction.aroundAnimation else {
                        continue
                    }
                    
                    if existingIds.contains(reaction.value) {
                        continue
                    }
                    existingIds.insert(reaction.value)
                    
                    switch allowedReactionsAndFiles.reactions {
                    case let .set(set):
                        if !set.contains(reaction.value) {
                            continue
                        }
                    case .all:
                        break
                    }
                    
                    result.append(ReactionItem(
                        reaction: ReactionItem.Reaction(rawValue: reaction.value),
                        appearAnimation: reaction.appearAnimation,
                        stillAnimation: reaction.selectAnimation,
                        listAnimation: centerAnimation,
                        largeListAnimation: reaction.activateAnimation,
                        applicationAnimation: aroundAnimation,
                        largeApplicationAnimation: reaction.effectAnimation,
                        isCustom: false
                    ))
                } else {
                    continue
                }
            case let .custom(file):
                switch allowedReactionsAndFiles.reactions {
                case let .set(set):
                    if !set.contains(.custom(file.fileId.id)) {
                        continue
                    }
                case .all:
                    break
                }
                
                if existingIds.contains(.custom(file.fileId.id)) {
                    continue
                }
                existingIds.insert(.custom(file.fileId.id))
                
                result.append(ReactionItem(
                    reaction: ReactionItem.Reaction(rawValue: .custom(file.fileId.id)),
                    appearAnimation: file,
                    stillAnimation: file,
                    listAnimation: file,
                    largeListAnimation: file,
                    applicationAnimation: nil,
                    largeApplicationAnimation: nil,
                    isCustom: true
                ))
            }
        }
        
        for reaction in availableReactions.reactions {
            guard let centerAnimation = reaction.centerAnimation else {
                continue
            }
            guard let aroundAnimation = reaction.aroundAnimation else {
                continue
            }
            if !reaction.isEnabled {
                continue
            }

            switch allowedReactionsAndFiles.reactions {
            case let .set(set):
                if !set.contains(reaction.value) {
                    continue
                }
            case .all:
                continue
            }
            
            if existingIds.contains(reaction.value) {
                continue
            }
            existingIds.insert(reaction.value)
            
            result.append(ReactionItem(
                reaction: ReactionItem.Reaction(rawValue: reaction.value),
                appearAnimation: reaction.appearAnimation,
                stillAnimation: reaction.selectAnimation,
                listAnimation: centerAnimation,
                largeListAnimation: reaction.activateAnimation,
                applicationAnimation: aroundAnimation,
                largeApplicationAnimation: reaction.effectAnimation,
                isCustom: false
            ))
        }
        
        if case let .set(reactions) = allowedReactionsAndFiles.reactions {
            for reaction in reactions {
                if existingIds.contains(reaction) {
                    continue
                }
                existingIds.insert(reaction)
                
                switch reaction {
                case .builtin:
                    break
                case let .custom(fileId):
                    if let file = allowedReactionsAndFiles.files[fileId] {
                        result.append(ReactionItem(
                            reaction: ReactionItem.Reaction(rawValue: .custom(file.fileId.id)),
                            appearAnimation: file,
                            stillAnimation: file,
                            listAnimation: file,
                            largeListAnimation: file,
                            applicationAnimation: nil,
                            largeApplicationAnimation: nil,
                            isCustom: true
                        ))
                    }
                }
            }
        }

        return result
    }
}
