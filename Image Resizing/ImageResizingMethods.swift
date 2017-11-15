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
func imageResizeUIKit(imageURL: URL, scalingFactor: Double) -> UIImage? {
    let image = UIImage(contentsOfFile: imageURL.path)!
    
    let size = image.size.applying(CGAffineTransform(scaleX: CGFloat(scalingFactor), y: CGFloat(scalingFactor)))
    let hasAlpha = false
    let scale: CGFloat = 0.0 // Automatically use scale factor of main screen
    
    UIGraphicsBeginImageContextWithOptions(size, !hasAlpha, scale)
    image.draw(in: CGRect(origin: CGPoint.zero, size: size))
    
    let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return scaledImage
}

/// Load and resize an image using `CGContextDrawImage(...)`.
func imageResizeCoreGraphics(imageURL: URL, scalingFactor: Double) -> UIImage? {
    let cgImage = UIImage(contentsOfFile: imageURL.path)!.cgImage!
    
    let width = Double(cgImage.width) * scalingFactor
    let height = Double(cgImage.height) * scalingFactor
    let bitsPerComponent = cgImage.bitsPerComponent
    let bytesPerRow = cgImage.bytesPerRow
    let colorSpace = cgImage.colorSpace!
    let bitmapInfo = cgImage.bitmapInfo
    
    let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)
    
    context?.interpolationQuality = .high
    
    context?.draw(cgImage, in: CGRect(origin: .zero, size: CGSize(width: CGFloat(width), height: CGFloat(height))))
    
    guard let image = context?.makeImage() else { return nil }
    
    let scaledImage = UIImage(cgImage: image)
    return scaledImage
}

/// Load and resize an image using `CGImageSourceCreateThumbnailAtIndex(...)`.
func imageResizeImageIO(imageURL: URL, scalingFactor: Double) -> UIImage? {
    guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else { return nil }
    
    guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as NSDictionary? else { return nil }
    guard let width = properties[kCGImagePropertyPixelWidth as NSString] as? NSNumber else { return nil }
    guard let height = properties[kCGImagePropertyPixelHeight as NSString] as? NSNumber else { return nil }
    
    let options: [NSString: Any] = [
        kCGImageSourceThumbnailMaxPixelSize: max(width.doubleValue, height.doubleValue) * scalingFactor,
        kCGImageSourceCreateThumbnailFromImageAlways: true
    ]
    
    let scaledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary).flatMap { UIImage(cgImage: $0) }
    return scaledImage
}

// create CI Contexts
let sharedCIContextGPU = CIContext(options: [kCIContextUseSoftwareRenderer: false])
let sharedCIContextSofware = CIContext(options: [kCIContextUseSoftwareRenderer: true])

private func _imageResizeCoreImage(context: CIContext, imageURL: URL, scalingFactor: Double) -> UIImage? {
    let image = CIImage(contentsOf: imageURL)
    
    guard let filter = CIFilter(name: "CILanczosScaleTransform") else { return nil }
    filter.setValue(image, forKey: "inputImage")
    filter.setValue(scalingFactor, forKey: "inputScale")
    filter.setValue(1.0, forKey: "inputAspectRatio")
    guard let outputImage = filter.value(forKey: "outputImage") as? CIImage else { return nil }
    
    guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else { return nil }
    
    let scaledImage = UIImage(cgImage: cgImage)
    return scaledImage
}

/// Load and resize an image using the Core Image `CILanczosScaleTransform` filter with GPU rendering.
func imageResizeCoreImageGPU(imageURL: URL, scalingFactor: Double) -> UIImage? {
    return _imageResizeCoreImage(context: sharedCIContextGPU, imageURL: imageURL, scalingFactor: scalingFactor)
}

/// Load and resize an image using the Core Image `CILanczosScaleTransform` filter with CPU rendering.
func imageResizeCoreImageSoftware(imageURL: URL, scalingFactor: Double) -> UIImage? {
    return _imageResizeCoreImage(context: sharedCIContextSofware, imageURL: imageURL, scalingFactor: scalingFactor)
}

/// Load and resize an image using Accelerate and `vImageScale_ARGB8888(...)`.
func imageResizeVImage(imageURL: URL, scalingFactor: Double) -> UIImage? {
    // special thanks to "Nyx0uf" for the Obj-C version of this code:
    // https://gist.github.com/Nyx0uf/217d97f81f4889f4445a
    
    let image = UIImage(contentsOfFile: imageURL.path)!

    // create a source buffer
    var format = vImage_CGImageFormat(bitsPerComponent: 8,
        bitsPerPixel: 32,
        colorSpace: nil,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue),
        version: 0,
        decode: nil,
        renderingIntent: .defaultIntent)
    var sourceBuffer = vImage_Buffer()
    defer {
        sourceBuffer.data.deallocate(bytes: Int(sourceBuffer.height) * Int(sourceBuffer.height) * 4, alignedTo: MemoryLayout<vImage_Buffer>.alignment)
    }
    var error: vImage_Error
    
    error = vImageBuffer_InitWithCGImage(&sourceBuffer, &format, nil, image.cgImage!, numericCast(kvImageNoFlags))
    guard error == kvImageNoError else { return nil }
    
    // create a destination buffer
    let scale = UIScreen.main.scale
    let destWidth = Int(image.size.width * CGFloat(scalingFactor) * scale)
    let destHeight = Int(image.size.height * CGFloat(scalingFactor) * scale)
    let bytesPerPixel = image.cgImage!.bitsPerPixel / 8
    let destBytesPerRow = destWidth * bytesPerPixel
    let destData = UnsafeMutablePointer<UInt8>.allocate(capacity: destHeight * destWidth * bytesPerPixel)
    defer {
        destData.deallocate(capacity: destHeight * destBytesPerRow)
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
    let scaledImage = UIImage(cgImage: destCGImage, scale: 0.0, orientation: image.imageOrientation)
    return scaledImage
}

