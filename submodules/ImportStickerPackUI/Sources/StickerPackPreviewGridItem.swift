import Foundation
import UIKit
import Display
import TelegramCore
import SyncCore
import SwiftSignalKit
import AsyncDisplayKit
import Postbox
import StickerResources
import AccountContext
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import TelegramPresentationData
import ShimmerEffect

final class StickerPackPreviewInteraction {
    var previewedItem: ImportStickerPack.Sticker?
    var playAnimatedStickers: Bool
    
    init(playAnimatedStickers: Bool) {
        self.playAnimatedStickers = playAnimatedStickers
    }
}

final class StickerPackPreviewGridItem: GridItem {
    let account: Account
    let stickerItem: ImportStickerPack.Sticker
    let interaction: StickerPackPreviewInteraction
    let theme: PresentationTheme
    let isEmpty: Bool
    
    let section: GridSection? = nil
    
    init(account: Account, stickerItem: ImportStickerPack.Sticker, interaction: StickerPackPreviewInteraction, theme: PresentationTheme, isEmpty: Bool) {
        self.account = account
        self.stickerItem = stickerItem
        self.interaction = interaction
        self.theme = theme
        self.isEmpty = isEmpty
    }
    
    func node(layout: GridNodeLayout, synchronousLoad: Bool) -> GridItemNode {
        let node = StickerPackPreviewGridItemNode()
        node.setup(account: self.account, stickerItem: self.stickerItem, interaction: self.interaction, theme: self.theme, isEmpty: self.isEmpty)
        return node
    }
    
    func update(node: GridItemNode) {
        guard let node = node as? StickerPackPreviewGridItemNode else {
            assertionFailure()
            return
        }
        node.setup(account: self.account, stickerItem: self.stickerItem, interaction: self.interaction, theme: self.theme, isEmpty: self.isEmpty)
    }
}

private let textFont = Font.regular(20.0)

final class StickerPackPreviewGridItemNode: GridItemNode {
    private var currentState: (Account, ImportStickerPack.Sticker?, CGSize)?
    private var isEmpty: Bool?
    private let imageNode: ASImageNode
    private var animationNode: AnimatedStickerNode?
    
    private var theme: PresentationTheme?
    
    override var isVisibleInGrid: Bool {
        didSet {
            self.animationNode?.visibility = self.isVisibleInGrid && self.interaction?.playAnimatedStickers ?? true
        }
    }
    
    private var currentIsPreviewing = false
    
    private let stickerFetchedDisposable = MetaDisposable()
    
    var interaction: StickerPackPreviewInteraction?
    
    var selected: (() -> Void)?
    
    var stickerPackItem: ImportStickerPack.Sticker? {
        return self.currentState?.1
    }
    
    override init() {
        self.imageNode = ASImageNode()

        super.init()
        
        self.addSubnode(self.imageNode)
    }
    
    deinit {
        self.stickerFetchedDisposable.dispose()
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.imageNodeTap(_:))))
    }
    
    func setup(account: Account, stickerItem: ImportStickerPack.Sticker?, interaction: StickerPackPreviewInteraction, theme: PresentationTheme, isEmpty: Bool) {
        self.interaction = interaction
        self.theme = theme
        
        if self.currentState == nil || self.currentState!.0 !== account || self.currentState!.1 !== stickerItem || self.isEmpty != isEmpty {
            var dimensions = CGSize(width: 512.0, height: 512.0)
            if let stickerItem = stickerItem {
                switch stickerItem.content {
                    case let .image(data):
                        if let animationNode = self.animationNode {
                            animationNode.visibility = false
                            self.animationNode = nil
                            animationNode.removeFromSupernode()
                        }
                        self.imageNode.isHidden = false
                        if let image = UIImage(data: data) {
                            self.imageNode.image = image
                            dimensions = image.size
                        }
                    case let .animation(data):
                        self.imageNode.isHidden = true
                        let animationNode = AnimatedStickerNode()
                        self.animationNode = animationNode
                        self.addSubnode(animationNode)
                        
                        let fittedDimensions = dimensions.aspectFitted(CGSize(width: 160.0, height: 160.0))
//                        animationNode.setup(source: AnimatedStickerResourceSource(account: account, resource: stickerItem.file.resource), width: Int(fittedDimensions.width), height: Int(fittedDimensions.height), mode: .cached)
                        animationNode.visibility = self.isVisibleInGrid && self.interaction?.playAnimatedStickers ?? true
                }
            } else {
                dimensions = CGSize()
            }
            self.currentState = (account, stickerItem, dimensions)
            self.setNeedsLayout()
        }
        self.isEmpty = isEmpty
    }
    
    override func layout() {
        super.layout()
        
        let bounds = self.bounds
        let boundsSide = min(bounds.size.width - 14.0, bounds.size.height - 14.0)
        let boundingSize = CGSize(width: boundsSide, height: boundsSide)
        
        if let (_, _, dimensions) = self.currentState {
            let imageSize = dimensions.aspectFitted(boundingSize)
            self.imageNode.frame = CGRect(origin: CGPoint(x: floor((bounds.size.width - imageSize.width) / 2.0), y: (bounds.size.height - imageSize.height) / 2.0), size: imageSize)
            if let animationNode = self.animationNode {
                animationNode.frame = CGRect(origin: CGPoint(x: floor((bounds.size.width - imageSize.width) / 2.0), y: (bounds.size.height - imageSize.height) / 2.0), size: imageSize)
                animationNode.updateLayout(size: imageSize)
            }
        }
    }
    
    func transitionNode() -> ASDisplayNode? {
        return self
    }
    
    @objc func imageNodeTap(_ recognizer: UITapGestureRecognizer) {
    }
    
    func updatePreviewing(animated: Bool) {
        var isPreviewing = false
        if let (_, maybeItem, _) = self.currentState, let interaction = self.interaction, let item = maybeItem {
            isPreviewing = interaction.previewedItem === item
        }
        if self.currentIsPreviewing != isPreviewing {
            self.currentIsPreviewing = isPreviewing
            
            if isPreviewing {
                self.layer.sublayerTransform = CATransform3DMakeScale(0.8, 0.8, 1.0)
                if animated {
                    self.layer.animateSpring(from: 1.0 as NSNumber, to: 0.8 as NSNumber, keyPath: "sublayerTransform.scale", duration: 0.4)
                }
            } else {
                self.layer.sublayerTransform = CATransform3DIdentity
                if animated {
                    self.layer.animateSpring(from: 0.8 as NSNumber, to: 1.0 as NSNumber, keyPath: "sublayerTransform.scale", duration: 0.5)
                }
            }
        }
    }
}

