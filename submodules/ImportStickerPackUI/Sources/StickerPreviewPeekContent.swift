import Foundation
import UIKit
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SyncCore
import SwiftSignalKit
import StickerResources
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import ContextUI

public final class StickerPreviewPeekContent: PeekControllerContent {
    let account: Account
    public let item: ImportStickerPack.Sticker
    let menu: [ContextMenuItem]
    
    public init(account: Account, item: ImportStickerPack.Sticker, menu: [ContextMenuItem]) {
        self.account = account
        self.item = item
        self.menu = menu
    }
    
    public func presentation() -> PeekControllerContentPresentation {
        return .freeform
    }
    
    public func menuActivation() -> PeerControllerMenuActivation {
        return .press
    }
    
    public func menuItems() -> [ContextMenuItem] {
        return self.menu
    }
    
    public func node() -> PeekControllerContentNode & ASDisplayNode {
        return StickerPreviewPeekContentNode(account: self.account, item: self.item)
    }
    
    public func topAccessoryNode() -> ASDisplayNode? {
        return nil
    }
    
    public func isEqual(to: PeekControllerContent) -> Bool {
        if let to = to as? StickerPreviewPeekContent {
            return self.item === to.item
        } else {
            return false
        }
    }
}

private final class StickerPreviewPeekContentNode: ASDisplayNode, PeekControllerContentNode {
    private let account: Account
    private let item: ImportStickerPack.Sticker
    
    private var textNode: ASTextNode
    private var imageNode: ASImageNode
    private var animationNode: AnimatedStickerNode?
    
    private var containerLayout: (ContainerViewLayout, CGFloat)?
    
    init(account: Account, item: ImportStickerPack.Sticker) {
        self.account = account
        self.item = item
        
        self.textNode = ASTextNode()
        self.imageNode = ASImageNode()
        self.imageNode.displaysAsynchronously = false
        if case let .image(data) = item.content, let image = UIImage(data: data) {
            self.imageNode.image = image
        }
        self.textNode.attributedText = NSAttributedString(string: item.emojis.joined(separator: " "), font: Font.regular(32.0), textColor: .black)
                
//        if item.file.isAnimatedSticker {
//            let animationNode = AnimatedStickerNode()
//            self.animationNode = animationNode
//
//            let dimensions = item.file.dimensions ?? PixelDimensions(width: 512, height: 512)
//            let fittedDimensions = dimensions.cgSize.aspectFitted(CGSize(width: 400.0, height: 400.0))
//
//            self.animationNode?.setup(source: AnimatedStickerResourceSource(account: account, resource: item.file.resource), width: Int(fittedDimensions.width), height: Int(fittedDimensions.height), mode: .direct(cachePathPrefix: nil))
//            self.animationNode?.visibility = true
//            self.animationNode?.addSubnode(self.textNode)
//        } else {
//            self.imageNode.addSubnode(self.textNode)
//            self.animationNode = nil
//        }
        
        super.init()
        
        self.isUserInteractionEnabled = false
        
        if let animationNode = self.animationNode {
            self.addSubnode(animationNode)
        } else {
            self.addSubnode(self.imageNode)
        }
        
        self.addSubnode(self.textNode)
    }
    
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        let boundingSize = CGSize(width: 180.0, height: 180.0).fitted(size)
        let imageFrame = CGRect(origin: CGPoint(), size: boundingSize)
            
        let textSpacing: CGFloat = 10.0
        let textSize = self.textNode.measure(CGSize(width: 100.0, height: 100.0))
        self.textNode.frame = CGRect(origin: CGPoint(x: floor((imageFrame.size.width - textSize.width) / 2.0), y: -textSize.height - textSpacing), size: textSize)
        
        self.imageNode.frame = imageFrame
        return boundingSize
        
//        if let dimensitons = self.item.file.dimensions {
//            let textSpacing: CGFloat = 10.0
//            let textSize = self.textNode.measure(CGSize(width: 100.0, height: 100.0))
//
//            let imageSize = dimensitons.cgSize.aspectFitted(boundingSize)
//            self.imageNode.asyncLayout()(TransformImageArguments(corners: ImageCorners(), imageSize: imageSize, boundingSize: imageSize, intrinsicInsets: UIEdgeInsets()))()
//            let imageFrame = CGRect(origin: CGPoint(x: floor((size.width - imageSize.width) / 2.0), y: textSize.height + textSpacing), size: imageSize)
//            self.imageNode.frame = imageFrame
//            if let animationNode = self.animationNode {
//                animationNode.frame = imageFrame
//                animationNode.updateLayout(size: imageSize)
//            }
//
//            self.textNode.frame = CGRect(origin: CGPoint(x: floor((imageFrame.size.width - textSize.width) / 2.0), y: -textSize.height - textSpacing), size: textSize)
//
//            return CGSize(width: size.width, height: imageFrame.height + textSize.height + textSpacing)
//        } else {
//            return CGSize(width: size.width, height: 10.0)
//        }
    }
}
