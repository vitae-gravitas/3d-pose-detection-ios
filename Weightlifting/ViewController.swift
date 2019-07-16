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
    
    var bufferWidth:Float = 0.0
    var bufferHeight:Float = 0.0
    
    var rootLayerHasLoaded = false
    
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
        
        guard character != nil else {
            print("Character has not been found")
            return
        }
        
        // This function will update the positions of all the body parts
        bodyPartManager.updateBodyParts(with: character!.jointTransforms)
        
        // This is the actual results of the new positions. Currently checking left hip and left knee. 
        if (bodyPartManager.getDifference(firstType: .leftHip, secondType: .leftKnee, axis: .x) < thresholdLegs) {
            print("The left hip and left knee are parallel to each other")
        } else {
            print("The left hip and left knee are not parallel")
        }
        
        
        // This code is for rendering the skeleton on the devie - ignore
        for anchor in anchors {
            
            guard let bodyAnchor = anchor as? ARBodyAnchor else { continue }
            let bodyPosition = simd_make_float3(bodyAnchor.transform.columns.3)
            characterAnchor.position = bodyPosition
            characterAnchor.orientation = Transform(matrix: bodyAnchor.transform).rotation
            
            if let character = character, character.parent == nil {
                // Attach the character to its anchor as soon as
                // 1. the body anchor was detected and
                // 2. the character was loaded.
                characterAnchor.addChild(character)
            }
        }
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
                topResults.append(objectObservation)
            }
        }
        
        topResults = topResults.sorted(by: { $0.labels[0].confidence > $1.labels[0].confidence })
        return topResults.prefix(numResults)
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
            
            
            
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(bufferWidth), Int(bufferHeight))
            
            let shapeLayer = self.createRoundedRectLayerWithBounds(objectBounds)
            
            let textLayer = self.createTextSubLayerInBounds(objectBounds,
                                                            identifier: topLabelObservation.identifier,
                                                            confidence: topLabelObservation.confidence)
            let lineLayer = self.createLineLayerWithBounds(objectBounds)
            shapeLayer.addSublayer(textLayer)
            detectionOverlay.addSublayer(shapeLayer)
            lineLayers.append(lineLayer)
            detectionOverlay.addSublayer(lineLayer)
            
        }
        self.updateLayerGeometry()
        CATransaction.commit()
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
    
    func createRoundedRectLayerWithBounds(_ bounds: CGRect) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Found Object"
        shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 0.2, 0.4])
        shapeLayer.cornerRadius = 7
        //.transform = CATransform3DMakeRotation(270.0 / 180.0 * .pi, 0.0, 0.0, 1.0)
        return shapeLayer
    }
    
    func createLineLayerWithBounds(_ bounds: CGRect) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = CGRect(x: bounds.midX-30, y: bounds.midY-30, width: 30, height: 30)
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Line"
        shapeLayer.backgroundColor = UIColor.red.cgColor
        shapeLayer.cornerRadius = 15
        return shapeLayer
    }
}


