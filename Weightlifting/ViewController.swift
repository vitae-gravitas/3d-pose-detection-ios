//
//  ViewController.swift
//  Weightlifting
//
//  Created by Avinash Jain on 6/10/19.
//  Copyright © 2019 Avinash Jain. All rights reserved.
//

import UIKit
import RealityKit
import ARKit
import CoreML
import Vision

class ViewController: UIViewController, ARSessionDelegate {
    
    @IBOutlet var arView: ARView!
    @IBOutlet weak var previewView: UIView!
    
    var rootLayer: CALayer! = nil
    var detectionOverlay: CALayer! = nil
    // The 3D character to display.
    var character: BodyTrackedEntity?
    let characterOffset: SIMD3<Float> = [-1.0, 0, 0] // Offset the character by one meter to the left
    let characterAnchor = AnchorEntity()
    
    var detector = BarbellDetector()
    
    var lineLayers: [CALayer] = []
    var firstBarbell: [CGRect] = []
    var secondBarbell: [CGRect] = []
    
    
    var bufferWidth:Float = 0.0
    var bufferHeight:Float = 0.0
    
    var rootLayerHasLoaded = false
    var color = UIColor.red.cgColor
    
    var frameCount = 0
    
    // Sets up BodyPartManager with what body part types to track
    var bodyPartManager = BodyPartManager(with: [.leftHip, .leftKnee, .rightHip, .rightKnee])
    
    // Threshold for the difference between
    let thresholdLegs:Float = 0.12
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        arView.session.delegate = self
        
        // If the iOS device doesn't support body tracking, raise a developer error for
        // this unhandled case.
        guard ARBodyTrackingConfiguration.isSupported else {
            fatalError("This feature is only supported on devices with an A12 chip")
        }
        
        // Run a body tracking configration.
        let configuration = ARBodyTrackingConfiguration()
        arView.session.run(configuration)
        
        // Comment this line out if you don't want the 3D skeleton to render on the iPhone
        arView.scene.addAnchor(characterAnchor)
        
        // Asynchronously load the 3D character.
        
        _ = Entity.loadBodyTrackedAsync(named: "character/robot").sink(receiveCompletion: { completion in
            if case let .failure(error) = completion {
                print("Error: Unable to load model: \(error.localizedDescription)")
            }
        }, receiveValue: { (character: Entity) in
            if let character = character as? BodyTrackedEntity {
                character.scale = [1.0, 1.0, 1.0]
                self.character = character
            } else {
                print("Error: Unable to load model as BodyTrackedEntity")
            }
        })
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCount += 1
        if frameCount > 0 {
            frameCount = 1
            let buffer = frame.capturedImage
            
            self.bufferWidth = Float(CVPixelBufferGetWidth(buffer))
            self.bufferHeight  = Float(CVPixelBufferGetHeight(buffer))
            
            if rootLayerHasLoaded == false {
                self.loadRootLayer()
                self.loadDetectionOverlay()
                self.updateLayerGeometry()
            }
            
            detector.performDetection(inputBuffer: buffer, completion: {(obs, error) -> Void in
                guard let observations = obs else {
                    return
                }
                self.generateBoundingBox(observations: observations)
            })
            
        }
    }
    
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        
        //        guard character != nil else {
        //            print("Character has not been found")
        //            return
        //        }
        //
        //        // This function will update the positions of all the body parts
        //        bodyPartManager.updateBodyParts(with: character!.jointTransforms)
        //
        //        // This is the actual results of the new positions. Currently checking left hip and left knee.
        //        if (bodyPartManager.getDifference(firstType: .leftHip, secondType: .leftKnee, axis: .x) < thresholdLegs) {
        //            print("The left hip and left knee are parallel to each other")
        //        } else {
        //            print("The left hip and left knee are not parallel")
        //        }
        //
        //
        //        // This code is for rendering the skeleton on the devie - ignore
        //        for anchor in anchors {
        //
        //            guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }
        //            let bodyPosition = simd_make_float3(bodyAnchor.transform.columns.3)
        //            characterAnchor.position = bodyPosition
        //            characterAnchor.orientation = Transform(matrix: bodyAnchor.transform).rotation
        //
        //            if let character = character, character.parent == nil {
        //                // Attach the character to its anchor as soon as
        //                // 1. the body anchor was detected and
        //                // 2. the character was loaded.
        //                characterAnchor.addChild(character)
        //            }
        //        }
    }
}

// MARK:- UI Code to render bounding box

extension ViewController {
    
    func getTopResults(_ results: [Any], numResults: Int = 2, targetLabel: String = "mainPlate") -> ArraySlice<VNRecognizedObjectObservation>{
        var topResults: [VNRecognizedObjectObservation] = []
        
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }
            
            if objectObservation.labels[0].identifier == targetLabel {
                var append = true
                if topResults.count > 0 {
                    for result in topResults {
                        if self.boundingBoxOverlap(bb1: result.boundingBox, bb2: objectObservation.boundingBox) {
                            append = false
                        }
                    }
                }
                if append {
                    topResults.append(objectObservation)
                }
            }
        }
        topResults = topResults.sorted(by: { $0.labels[0].confidence > $1.labels[0].confidence })
        return topResults.prefix(numResults)
    }
    
    func boundingBoxOverlap(bb1: CGRect, bb2: CGRect) -> Bool {
        return bb1.intersects(bb2)
    }
    
    func generateBoundingBox(observations: [VNRecognizedObjectObservation]) {
        
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        for layer in detectionOverlay?.sublayers ?? [] {
            if layer.name != "Line" {
                layer.removeFromSuperlayer()
            } else {
                if lineLayers.count >= 50 {
                    lineLayers.remove(at: 0).removeFromSuperlayer()
                }
            }
        }
        
        for observation in getTopResults(observations) where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }
            
            // Select only the label with the highest confidence.
            let topLabelObservation = objectObservation.labels[0]
            
            var objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(bufferWidth), Int(bufferHeight))
            
            var fbarbell = true
            var showBounds = false
            let padding:CGFloat = 100.0
            
            if (firstBarbell.count == 0) {
                firstBarbell.append(objectBounds)
                showBounds = true
            } else {
                if objectBounds.intersects(firstBarbell.last!) {
                    objectBounds = updateBarbellRect(firstBarbell, objectBounds)
                    if objectBounds.intersection(firstBarbell.last!).width > padding
                        && objectBounds.intersection(firstBarbell.last!).height > padding {
                        firstBarbell.append(objectBounds)
                        showBounds = true
                    }
                    
                } else {
                    
                    fbarbell = false
                    objectBounds = updateBarbellRect(secondBarbell, objectBounds)
                    if secondBarbell.count > 0 {
                        if objectBounds.intersection(secondBarbell.last!).width > padding
                            && objectBounds.intersection(secondBarbell.last!).height > padding {
                            secondBarbell.append(objectBounds)
                            showBounds = true
                        }
                    } else {
                        secondBarbell.append(objectBounds)
                        showBounds = true
                    }
                    
                }
            } 
            
            if showBounds {
                let shapeLayer = self.createRoundedRectLayerWithBounds(fbarbell, bounds: objectBounds)
                
                let textLayer = self.createTextSubLayerInBounds(objectBounds,
                                                                identifier: topLabelObservation.identifier,
                                                                confidence: topLabelObservation.confidence)
                let lineLayer = self.createLineLayerWithBounds(objectBounds)
                shapeLayer.addSublayer(textLayer)
                detectionOverlay.addSublayer(shapeLayer)
                lineLayers.append(lineLayer)
                //detectionOverlay.addSublayer(lineLayer)
            }
            
        }
        self.updateLayerGeometry()
        CATransaction.commit()
    }
    
    // Made this function to prevent flickering of bounds, needs some work
    func shouldIncludeBounds(firstB: Bool, bounds: CGRect) -> Bool {
        var lastTenFrames:[CGRect] = []
        if firstB {
            if (firstBarbell.count < 20) {
                return true
            }
            lastTenFrames = firstBarbell.suffix(20)
        } else {
            if (secondBarbell.count < 20) {
                return true
            }
            lastTenFrames = secondBarbell.suffix(20)
        }
        
        let count = CGFloat(lastTenFrames.count)
        let averageRect: CGRect
        var width:CGFloat = 0
        var height:CGFloat = 0
        var x:CGFloat = 0
        var y:CGFloat = 0
        for frame in lastTenFrames {
            width = width + frame.width
            height = height + frame.height
            x = frame.origin.x
            y = frame.origin.y
        }
        averageRect = CGRect(x: x/count, y: y/count, width: width/count, height: height/count)
        return averageRect.intersects(bounds)
    }
    
    func updateBarbellRect(_ frames: [CGRect], _ rect: CGRect) -> CGRect {
        if (frames.count < 5) {
            return rect
        }
        let finalFrames = frames.suffix(20)
        var width:CGFloat = 0.0
        var height:CGFloat = 0.0
        for rect in finalFrames {
            width = width + rect.width
            height = height + rect.height
        }
        
        let diffX = rect.origin.x - finalFrames.last!.origin.x
        //print(diffX)
        var rect = CGRect(x: finalFrames.last!.origin.x + 0.4 * diffX, y: rect.origin.y, width: rect.width, height: rect.height)
        
        var ratio:CGFloat = 0.7
        
        width = ratio * (width / CGFloat(finalFrames.count)) + (1-ratio) * (rect.width)
        height = ratio * (height / CGFloat(finalFrames.count)) + (1-ratio) * (rect.height)
        
        let newX = (rect.midX - width/2.0)
        let newY = (rect.midY - height/2.0)
        
        return CGRect(x: newX, y: newY, width: width, height: height)
    }
    
    func loadRootLayer() {
        rootLayer = previewView.layer
        rootLayerHasLoaded = true
    }
    
    func loadDetectionOverlay() {
        detectionOverlay = CALayer() // container layer that has all the renderings of the observations
        detectionOverlay.name = "DetectionOverlay"
        detectionOverlay.bounds = CGRect(x: 0.0,
                                         y: 0.0,
                                         width: Double(bufferWidth),
                                         height: Double(bufferHeight))
        detectionOverlay.position = CGPoint(x: rootLayer.bounds.midX, y: rootLayer.bounds.midY)
        rootLayer.addSublayer(detectionOverlay)
    }
    
    func updateLayerGeometry() {
        let bounds = rootLayer.bounds   
        var scale: CGFloat
        
        let xScale: CGFloat = bounds.size.width / CGFloat(bufferHeight)
        let yScale: CGFloat = bounds.size.height / CGFloat(bufferWidth)
        
        scale = fmax(xScale, yScale)
        if scale.isInfinite {
            scale = 1.0
        }
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        
        // rotate the layer into screen orientation and scale and mirror
        
        detectionOverlay.setAffineTransform(
            //CGAffineTransform(scaleX: scale, y: -scale)
            CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: scale, y: -scale)
        )
        // center the layer
        detectionOverlay.position = CGPoint (x: bounds.midX, y: bounds.midY)
        
        CATransaction.commit()
    }
    
    func createTextSubLayerInBounds(_ bounds: CGRect, identifier: String, confidence: VNConfidence) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.name = "Object Label"
        let formattedString = NSMutableAttributedString(string: String(format: "\(identifier)\nConfidence:  %.2f", confidence))
        let largeFont = UIFont(name: "Helvetica", size: 24.0)!
        formattedString.addAttributes([NSAttributedString.Key.font: largeFont], range: NSRange(location: 0, length: identifier.count))
        textLayer.string = formattedString
        textLayer.bounds = CGRect(x: 0, y: 0, width: bounds.size.height - 10, height: bounds.size.width - 10)
        textLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        textLayer.shadowOpacity = 0.7
        textLayer.shadowOffset = CGSize(width: 2, height: 2)
        textLayer.foregroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.0, 0.0, 0.0, 1.0])
        textLayer.contentsScale = 2.0 // retina rendering
        // rotate the layer into screen orientation and scale and mirror
        textLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: 1.0, y: -1.0))
        return textLayer
    }
    
    func createRoundedRectLayerWithBounds(_ barbell: Bool,  bounds: CGRect) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Found Object"
        if (barbell) {
            shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 0.2, 0.4])
        } else {
            shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.2, 1.0, 1.0, 0.4])
        }
        shapeLayer.cornerRadius = 7
        //.transform = CATransform3DMakeRotation(270.0 / 180.0 * .pi, 0.0, 0.0, 1.0)
        return shapeLayer
    }
    
    func createLineLayerWithBounds(_ bounds: CGRect) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = CGRect(x: bounds.midX-30, y: bounds.midY-30, width: 30, height: 30)
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Line"
        shapeLayer.backgroundColor = self.color
        if self.color == UIColor.red.cgColor {
            self.color = UIColor.blue.cgColor
        } else { self.color = UIColor.red.cgColor }
        shapeLayer.cornerRadius = 15
        return shapeLayer
    }
}


