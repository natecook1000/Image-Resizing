//
//  ImageResizingMethods.swift
//  Image Resizing
//
//  Created by Nate Cook on 9/3/15.
//  Copyright © 2015 Nate Cook. All rights reserved.
//

import UIKit
import ImageIO
import Accelerate

/// Load and resize an image using `UIImage.drawInRect(_:)`.
func imageResizeUIKit(imageURL: NSURL, scalingFactor: Double) -> UIImage? {
    let image = UIImage(contentsOfFile: imageURL.path!)!
    
    let size = CGSizeApplyAffineTransform(image.size, CGAffineTransformMakeScale(CGFloat(scalingFactor), CGFloat(scalingFactor)))
    let hasAlpha = false
    let scale: CGFloat = 0.0 // Automatically use scale factor of main screen
    
    UIGraphicsBeginImageContextWithOptions(size, !hasAlpha, scale)
    image.drawInRect(CGRect(origin: CGPointZero, size: size))
    
    let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return scaledImage
}

/// Load and resize an image using `CGContextDrawImage(...)`.
func imageResizeCoreGraphics(imageURL: NSURL, scalingFactor: Double) -> UIImage? {
    let cgImage = UIImage(contentsOfFile: imageURL.path!)!.CGImage
    
    let width = Double(CGImageGetWidth(cgImage)) * scalingFactor
    let height = Double(CGImageGetHeight(cgImage)) * scalingFactor
    let bitsPerComponent = CGImageGetBitsPerComponent(cgImage)
    let bytesPerRow = CGImageGetBytesPerRow(cgImage)
    let colorSpace = CGImageGetColorSpace(cgImage)
    let bitmapInfo = CGImageGetBitmapInfo(cgImage)
    
    let context = CGBitmapContextCreate(nil, Int(width), Int(height), bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo.rawValue)
    
    CGContextSetInterpolationQuality(context, .High)
    
    CGContextDrawImage(context, CGRect(origin: CGPointZero, size: CGSize(width: CGFloat(width), height: CGFloat(height))), cgImage)
    
    let scaledImage = CGBitmapContextCreateImage(context).flatMap { return UIImage(CGImage: $0) }
    return scaledImage
}

/// Load and resize an image using `CGImageSourceCreateThumbnailAtIndex(...)`.
func imageResizeImageIO(imageURL: NSURL, scalingFactor: Double) -> UIImage? {
    guard let imageSource = CGImageSourceCreateWithURL(imageURL, nil) else { return nil }
    
    guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as NSDictionary? else { return nil }
    guard let width = properties[kCGImagePropertyPixelWidth as NSString] as? NSNumber else { return nil }
    guard let height = properties[kCGImagePropertyPixelHeight as NSString] as? NSNumber else { return nil }
    
    let options: [NSString: NSObject] = [
        kCGImageSourceThumbnailMaxPixelSize: max(width.doubleValue, height.doubleValue) * scalingFactor,
        kCGImageSourceCreateThumbnailFromImageAlways: true
    ]
        
    let scaledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options).flatMap { UIImage(CGImage: $0) }
    return scaledImage
}

// create CI Contexts
let sharedCIContextGPU = CIContext(options: [kCIContextUseSoftwareRenderer: false])
let sharedCIContextSofware = CIContext(options: [kCIContextUseSoftwareRenderer: true])

private func _imageResizeCoreImage(context: CIContext, imageURL: NSURL, scalingFactor: Double) -> UIImage? {
    let image = CIImage(contentsOfURL: imageURL)
    
    guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return nil }
    filter.setValue(image, forKey: "inputImage")
    filter.setValue(scalingFactor, forKey: "inputScale")
    filter.setValue(1.0, forKey: "inputAspectRatio")
    guard let outputImage = filter.valueForKey("outputImage") as? CIImage else { return nil }
    
    let scaledImage = UIImage(CGImage: context.createCGImage(outputImage, fromRect: outputImage.extent))
    return scaledImage
}

/// Load and resize an image using the Core Image `CILanczosScaleTransform` filter with GPU rendering.
func imageResizeCoreImageGPU(imageURL: NSURL, scalingFactor: Double) -> UIImage? {
    return _imageResizeCoreImage(sharedCIContextGPU, imageURL: imageURL, scalingFactor: scalingFactor)
}

/// Load and resize an image using the Core Image `CILanczosScaleTransform` filter with CPU rendering.
func imageResizeCoreImageSoftware(imageURL: NSURL, scalingFactor: Double) -> UIImage? {
    return _imageResizeCoreImage(sharedCIContextSofware, imageURL: imageURL, scalingFactor: scalingFactor)
}

/// Load and resize an image using Accelerate and `vImageScale_ARGB8888(...)`.
func imageResizeVImage(imageURL: NSURL, scalingFactor: Double) -> UIImage? {
    // special thanks to "Nyx0uf" for the Obj-C version of this code:
    // https://gist.github.com/Nyx0uf/217d97f81f4889f4445a
    
    let image = UIImage(contentsOfFile: imageURL.path!)!

    // create a source buffer
    var format = vImage_CGImageFormat(bitsPerComponent: 8,
        bitsPerPixel: 32,
        colorSpace: nil,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.First.rawValue),
        version: 0,
        decode: nil,
        renderingIntent: CGColorRenderingIntent.RenderingIntentDefault)
    var sourceBuffer = vImage_Buffer()
    defer {
        sourceBuffer.data.dealloc(Int(sourceBuffer.height) * Int(sourceBuffer.height) * 4)
    }
    var error: vImage_Error
    
    error = vImageBuffer_InitWithCGImage(&sourceBuffer, &format, nil, image.CGImage!, numericCast(kvImageNoFlags))
    guard error == kvImageNoError else { return nil }
    
    // create a destination buffer
    let scale = UIScreen.mainScreen().scale
    let destWidth = Int(image.size.width * CGFloat(scalingFactor) * scale)
    let destHeight = Int(image.size.height * CGFloat(scalingFactor) * scale)
    let bytesPerPixel = CGImageGetBitsPerPixel(image.CGImage) / 8
    let destBytesPerRow = destWidth * bytesPerPixel
    let destData = UnsafeMutablePointer<UInt8>.alloc(destHeight * destWidth * bytesPerPixel)
    defer {
        destData.dealloc(destHeight * destBytesPerRow)
    }
    var destBuffer = vImage_Buffer(data: destData, height: vImagePixelCount(destHeight), width: vImagePixelCount(destWidth), rowBytes: destBytesPerRow)

    // scale the image
    error = vImageScale_ARGB8888(&sourceBuffer, &destBuffer, nil, numericCast(kvImageHighQualityResampling))
    guard error == kvImageNoError else { return nil }
    
    // create a CGImage from vImage_Buffer
    guard let destCGImage = vImageCreateCGImageFromBuffer(&destBuffer, &format, nil, nil, numericCast(kvImageNoFlags), &error)?.takeRetainedValue()
        else { return nil }
    guard error == kvImageNoError else { return nil }

    // create a UIImage
//    let scaledImage = destCGImage.flatMap { UIImage(CGImage: $0, scale: 0.0, orientation: image.imageOrientation) }
    let scaledImage = UIImage(CGImage: destCGImage, scale: 0.0, orientation: image.imageOrientation)
    return scaledImage
}

