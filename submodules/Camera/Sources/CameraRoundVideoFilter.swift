import Foundation
import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Metal
import Display
import TelegramCore

let videoMessageDimensions = PixelDimensions(width: 400, height: 400)

func allocateOutputBufferPool(with inputFormatDescription: CMFormatDescription, outputRetainedBufferCountHint: Int) -> (
    outputBufferPool: CVPixelBufferPool?,
    outputColorSpace: CGColorSpace?,
    outputFormatDescription: CMFormatDescription?) {
        let inputMediaSubType = CMFormatDescriptionGetMediaSubType(inputFormatDescription)
        if inputMediaSubType != kCVPixelFormatType_32BGRA {
            return (nil, nil, nil)
        }
        
        let inputDimensions = CMVideoFormatDescriptionGetDimensions(inputFormatDescription)
        var pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: UInt(inputMediaSubType),
            kCVPixelBufferWidthKey as String: Int(inputDimensions.width),
            kCVPixelBufferHeightKey as String: Int(inputDimensions.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as NSDictionary
        ]
        
        var cgColorSpace = CGColorSpaceCreateDeviceRGB()
        if let inputFormatDescriptionExtension = CMFormatDescriptionGetExtensions(inputFormatDescription) as Dictionary? {
            let colorPrimaries = inputFormatDescriptionExtension[kCVImageBufferColorPrimariesKey]
            
            if let colorPrimaries = colorPrimaries {
                var colorSpaceProperties: [String: AnyObject] = [kCVImageBufferColorPrimariesKey as String: colorPrimaries]
                
                if let yCbCrMatrix = inputFormatDescriptionExtension[kCVImageBufferYCbCrMatrixKey] {
                    colorSpaceProperties[kCVImageBufferYCbCrMatrixKey as String] = yCbCrMatrix
                }
                
                if let transferFunction = inputFormatDescriptionExtension[kCVImageBufferTransferFunctionKey] {
                    colorSpaceProperties[kCVImageBufferTransferFunctionKey as String] = transferFunction
                }
                
                pixelBufferAttributes[kCVBufferPropagatedAttachmentsKey as String] = colorSpaceProperties
            }
            
            if let cvColorspace = inputFormatDescriptionExtension[kCVImageBufferCGColorSpaceKey] {
                cgColorSpace = cvColorspace as! CGColorSpace
            } else if (colorPrimaries as? String) == (kCVImageBufferColorPrimaries_P3_D65 as String) {
                cgColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
            }
        }
        
        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: outputRetainedBufferCountHint]
        var cvPixelBufferPool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as NSDictionary?, pixelBufferAttributes as NSDictionary?, &cvPixelBufferPool)
        guard let pixelBufferPool = cvPixelBufferPool else {
            return (nil, nil, nil)
        }
        
        preallocateBuffers(pool: pixelBufferPool, allocationThreshold: outputRetainedBufferCountHint)
        
        var pixelBuffer: CVPixelBuffer?
        var outputFormatDescription: CMFormatDescription?
        let auxAttributes = [kCVPixelBufferPoolAllocationThresholdKey as String: outputRetainedBufferCountHint] as NSDictionary
        CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pixelBufferPool, auxAttributes, &pixelBuffer)
        if let pixelBuffer = pixelBuffer {
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                         imageBuffer: pixelBuffer,
                                                         formatDescriptionOut: &outputFormatDescription)
        }
        pixelBuffer = nil
        
        return (pixelBufferPool, cgColorSpace, outputFormatDescription)
}

private func preallocateBuffers(pool: CVPixelBufferPool, allocationThreshold: Int) {
    var pixelBuffers = [CVPixelBuffer]()
    var error: CVReturn = kCVReturnSuccess
    let auxAttributes = [kCVPixelBufferPoolAllocationThresholdKey as String: allocationThreshold] as NSDictionary
    var pixelBuffer: CVPixelBuffer?
    while error == kCVReturnSuccess {
        error = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, auxAttributes, &pixelBuffer)
        if let pixelBuffer = pixelBuffer {
            pixelBuffers.append(pixelBuffer)
        }
        pixelBuffer = nil
    }
    pixelBuffers.removeAll()
}

final class CameraRoundVideoFilter {
    private let ciContext: CIContext
    private let colorSpace: CGColorSpace
    private let simple: Bool
    
    private var resizeFilter: CIFilter?
    private var overlayFilter: CIFilter?
    private var compositeFilter: CIFilter?
    private var borderFilter: CIFilter?
    
    private var outputColorSpace: CGColorSpace?
    private var outputPixelBufferPool: CVPixelBufferPool?
    private(set) var outputFormatDescription: CMFormatDescription?
    private(set) var inputFormatDescription: CMFormatDescription?
    
    private(set) var isPrepared = false
    
    init(ciContext: CIContext, colorSpace: CGColorSpace, simple: Bool) {
        self.ciContext = ciContext
        self.colorSpace = colorSpace
        self.simple = simple
    }
    
    func prepare(with formatDescription: CMFormatDescription, outputRetainedBufferCountHint: Int) {
        self.reset()
        
        (self.outputPixelBufferPool, self.outputColorSpace, self.outputFormatDescription) = allocateOutputBufferPool(with: formatDescription, outputRetainedBufferCountHint: outputRetainedBufferCountHint)
        if self.outputPixelBufferPool == nil {
            return
        }
        self.inputFormatDescription = formatDescription
        
        let circleImage = generateImage(videoMessageDimensions.cgSize, opaque: false, scale: 1.0, rotatedContext: { size, context in
            let bounds = CGRect(origin: .zero, size: size)
            context.clear(bounds)
            context.setFillColor(UIColor.white.cgColor)
            context.fill(bounds)
            context.setBlendMode(.clear)
            context.fillEllipse(in: bounds.insetBy(dx: -2.0, dy: -2.0))
        })!
                
        self.resizeFilter = CIFilter(name: "CILanczosScaleTransform")
        self.overlayFilter = CIFilter(name: "CIColorMatrix")
        self.compositeFilter = CIFilter(name: "CISourceOverCompositing")
        
        self.borderFilter = CIFilter(name: "CISourceOverCompositing")
        self.borderFilter?.setValue(CIImage(image: circleImage), forKey: kCIInputImageKey)
        
        self.isPrepared = true
    }
    
    func reset() {
        self.resizeFilter = nil
        self.overlayFilter = nil
        self.compositeFilter = nil
        self.borderFilter = nil
        self.outputColorSpace = nil
        self.outputPixelBufferPool = nil
        self.outputFormatDescription = nil
        self.inputFormatDescription = nil
        self.isPrepared = false
        self.lastMainSourceImage = nil
        self.lastAdditionalSourceImage = nil
    }
    
    private var lastMainSourceImage: CIImage?
    private var lastAdditionalSourceImage: CIImage?
    
    func render(pixelBuffer: CVPixelBuffer, additional: Bool, captureOrientation: AVCaptureVideoOrientation, transitionFactor: CGFloat) -> CVPixelBuffer? {
        guard let resizeFilter = self.resizeFilter, let overlayFilter = self.overlayFilter, let compositeFilter = self.compositeFilter, let borderFilter = self.borderFilter, self.isPrepared else {
            return nil
        }
        
        var sourceImage = CIImage(cvImageBuffer: pixelBuffer, options: [.colorSpace: self.colorSpace])
        var sourceOrientation: CGImagePropertyOrientation
        var sourceIsLandscape = false
        switch captureOrientation {
        case .portrait:
            sourceOrientation = additional ? .leftMirrored : .right
        case .landscapeLeft:
            sourceOrientation = additional ? .upMirrored : .down
            sourceIsLandscape = true
        case .landscapeRight:
            sourceOrientation = additional ? .downMirrored : .up
            sourceIsLandscape = true
        case .portraitUpsideDown:
            sourceOrientation = additional ? .rightMirrored : .left
        @unknown default:
            sourceOrientation = additional ? .leftMirrored : .right
        }
        sourceImage = sourceImage.oriented(sourceOrientation)
        let scale = CGFloat(videoMessageDimensions.width) / min(sourceImage.extent.width, sourceImage.extent.height)
        
        if !self.simple {
            resizeFilter.setValue(sourceImage, forKey: kCIInputImageKey)
            resizeFilter.setValue(scale, forKey: kCIInputScaleKey)
            
            if let resizedImage = resizeFilter.outputImage {
                sourceImage = resizedImage
            } else {
                sourceImage = sourceImage.transformed(by: CGAffineTransformMakeScale(scale, scale), highQualityDownsample: true)
            }
        } else {
            sourceImage = sourceImage.transformed(by: CGAffineTransformMakeScale(scale, scale), highQualityDownsample: true)
        }
        
        if sourceIsLandscape {
            sourceImage = sourceImage.transformed(by: CGAffineTransformMakeTranslation(-(sourceImage.extent.width - sourceImage.extent.height) / 2.0, 0.0))
            sourceImage = sourceImage.cropped(to: CGRect(x: 0.0, y: 0.0, width: sourceImage.extent.height, height: sourceImage.extent.height))
        } else {
            sourceImage = sourceImage.transformed(by: CGAffineTransformMakeTranslation(0.0, -(sourceImage.extent.height - sourceImage.extent.width) / 2.0))
            sourceImage = sourceImage.cropped(to: CGRect(x: 0.0, y: 0.0, width: sourceImage.extent.width, height: sourceImage.extent.width))
        }
        
        if additional {
            self.lastAdditionalSourceImage = sourceImage
        } else {
            self.lastMainSourceImage = sourceImage
        }
        
        var effectiveSourceImage: CIImage
        if transitionFactor == 0.0 {
            effectiveSourceImage = !additional ? sourceImage : (self.lastMainSourceImage ?? sourceImage)
        } else if transitionFactor == 1.0 {
            effectiveSourceImage = additional ? sourceImage : (self.lastAdditionalSourceImage ?? sourceImage)
        } else {
            if let mainSourceImage = self.lastMainSourceImage, let additionalSourceImage = self.lastAdditionalSourceImage {
                let overlayRgba: [CGFloat] = [0, 0, 0, transitionFactor]
                let alphaVector: CIVector = CIVector(values: overlayRgba, count: 4)
                overlayFilter.setValue(additionalSourceImage, forKey: kCIInputImageKey)
                overlayFilter.setValue(alphaVector, forKey: "inputAVector")
                
                compositeFilter.setValue(mainSourceImage, forKey: kCIInputBackgroundImageKey)
                compositeFilter.setValue(overlayFilter.outputImage, forKey: kCIInputImageKey)
                effectiveSourceImage = compositeFilter.outputImage ?? sourceImage
            } else {
                effectiveSourceImage = sourceImage
            }
        }
        
        borderFilter.setValue(effectiveSourceImage, forKey: kCIInputBackgroundImageKey)
        
        let finalImage = borderFilter.outputImage
        guard let finalImage else {
            return nil
        }
                
        var pbuf: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPixelBufferPool!, &pbuf)
        guard let outputPixelBuffer = pbuf else {
            return nil
        }
        
        self.ciContext.render(finalImage, to: outputPixelBuffer, bounds: CGRect(origin: .zero, size: videoMessageDimensions.cgSize), colorSpace: outputColorSpace)
        
        return outputPixelBuffer
    }
}
