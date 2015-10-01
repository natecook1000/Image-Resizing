//
//  ViewController.swift
//  Image Resizing
//
//  Created by Nate Cook on 9/3/15.
//  Copyright © 2015 Nate Cook. All rights reserved.
//

import UIKit

/// An enumeration of the test images that provides access to each image's URL.
enum TestImage {
    case Postgres
    case NASA
    
    /// The URL for the image.
    var url: NSURL {
        switch self {
        case .Postgres:
            return NSBundle.mainBundle().URLForResource("postgres", withExtension: "png")!
        case .NASA:
            return NSBundle.mainBundle().URLForResource("nasa", withExtension: "jpg")!
        }
    }
}

/// An enumeration of the different kinds of tests.
enum ResizingTest: String {
    case UIKit = "UIKit"
    case CoreGraphics = "Core Graphics"
    case ImageIO = "Image IO"
    case CoreImageGPU = "Core Image GPU"
    case CoreImageSoftware = "Core Image Software"
    case VImage = "Accelerate VImage"
    
    typealias ResizingFunction = (NSURL, Double) -> UIImage?
    
    /// The function to call for the test.
    var function: ResizingFunction {
        switch self {
        case .UIKit:
            return imageResizeUIKit
        case .CoreGraphics:
            return imageResizeCoreGraphics
        case .ImageIO:
            return imageResizeImageIO
        case .CoreImageGPU:
            return imageResizeCoreImageGPU
        case .CoreImageSoftware:
            return imageResizeCoreImageSoftware
        case .VImage:
            return imageResizeVImage
        }
    }
}

/// Calculate the standard deviation of the observations in `data`.
func standardDeviation(data: [Double]) -> Double {
    let doubleCount = Double(data.count)
    let mean = data.reduce(0, combine: +) / doubleCount
    let variance = data.map({ pow($0 - mean, 2) }).reduce(0, combine: +) / doubleCount
    return sqrt(variance)
}

class ViewController: UIViewController {
    
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet weak var outputText: UITextView!
    
    @IBOutlet weak var renderingImageView: UIImageView!
    
    func performResizingTest(image: TestImage, test: ResizingTest) {
        
        // test setup
        let resizingFactor = 0.1
        var results: [Double] = []
        let startAll = CACurrentMediaTime()
        var resizedImage: UIImage?

        let numberTests: Int
        
        // The NASA image test is too big for a couple of the
        switch (image, test) {
        case (.NASA, .CoreImageSoftware), (.NASA, .VImage):
            numberTests = 0
        default:
            numberTests = 10
        }

        for _ in 0..<numberTests {
            // this is a timed test that loads and resizes an image at the given URL, then adds it to
            // an onscreen UIImageView to compel the image to actually render. (CIImage-based UIImages don't
            // appear to render unless displayed, even when rendering calls are made.)
            let start = CACurrentMediaTime()
            resizedImage = test.function(image.url, resizingFactor)
            dispatch_sync(dispatch_get_main_queue()) {
                self.renderingImageView.image = resizedImage
            }
            results.append(CACurrentMediaTime() - start)
        }
        
        // clear the rendered image - a visual cue that this round is over
        dispatch_sync(dispatch_get_main_queue()) {
            self.renderingImageView.image = nil
        }
        
        // calculate the results
        let floatFormat = "%0.4f"
        var output = "\(image) - \(test)\n"
        
        // check to make sure the test actually worked properly
        if resizedImage != nil {
            output += results.map({ String(format: floatFormat, $0) }).joinWithSeparator(" ") + "\n"
            
            let mean = results.reduce(0, combine: +) / Double(results.count)
            let stdev = standardDeviation(results)
            output +=   "total time: \(String(format: floatFormat, CACurrentMediaTime() - startAll))\n" +
                        "average: \(String(format: floatFormat, mean)), s.d.: \(String(format: floatFormat, stdev))\n\n"
        } else {
            output += "TEST FAILED\n\n"
        }
        
        dispatch_async(dispatch_get_main_queue()) {
            self.outputText.text = output + self.outputText.text
        }
    }
    
    func runTests() {
        let images: [TestImage] = [.Postgres, .NASA]
        let tests: [ResizingTest] = [.UIKit, .CoreGraphics, .ImageIO, .VImage, .CoreImageGPU, .CoreImageSoftware]
        
        // build a serial queue for the tests
        let queue = NSOperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .UserInitiated     // seems appropriate
        queue.suspended = true
        
        for image in images {
            for test in tests {
                queue.addOperationWithBlock {
                    self.performResizingTest(image, test: test)
                }
            }
        }
        
        // turn the start button back on when finished with tests
        queue.addOperationWithBlock {
            NSOperationQueue.mainQueue().addOperationWithBlock {
                self.startButton.enabled = true
            }
        }
        queue.suspended = false
    }
    
    @IBAction func beginTest(_: AnyObject) {
        // prepare
        startButton.enabled = false
        outputText.text = ""
        
        // create the Core Image contexts before the tests start
        // as global constants, these will wait to be created until they're access
        print(sharedCIContextGPU, sharedCIContextSofware)
        
        runTests()
    }
}

