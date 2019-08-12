//
//  ViewController.swift
//  Weightlifting
//
//  Created by Avinash Jain on 6/10/19.
//  Copyright © 2019 Avinash Jain. All rights reserved.
//

import ARKit
import CoreML
import RealityKit
import UIKit
import Vision

class ViewController: UIViewController, ARSessionDelegate, UIGestureRecognizerDelegate {
    @IBOutlet var arView: ARView!
    @IBOutlet var previewView: UIView!

    var rootLayer: CALayer!
    var detectionOverlay: CALayer!
    // The 3D character to display.
    var character: BodyTrackedEntity?
    let characterOffset: SIMD3<Float> = [-1.0, 0, 0] // Offset the character by one meter to the left
    let characterAnchor = AnchorEntity()

    var detector = BarbellDetector()

    var lineLayers: [CALayer] = []
    var firstBarbell: [CGRect] = []
    var secondBarbell: [CGRect] = []
    var barbellManager = BarbellManager()

    var bufferWidth: Float = 0.0
    var bufferHeight: Float = 0.0

    var rootLayerHasLoaded = false
    var color = UIColor.red.cgColor

    var frameCount = 0

    // Sets up BodyPartManager with what body part types to track
    var bodyPartManager = BodyPartManager(with: [.leftHip, .leftKnee, .rightHip, .rightKnee])

    // Threshold for the difference between
    let thresholdLegs: Float = 0.12

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
        //arView.scene.addAnchor(characterAnchor)

//         Asynchronously load the 3D character.
//        _ = Entity.loadBodyTrackedAsync(named: "character/robot").sink(receiveCompletion: { completion in
//            if case let .failure(error) = completion {
//                print("Error: Unable to load model: \(error.localizedDescription)")
//            }
//        }, receiveValue: { (character: Entity) in
//            if let character = character as? BodyTrackedEntity {
//                character.scale = [1.0, 1.0, 1.0]
//                self.character = character
//            } else {
//                print("Error: Unable to load model as BodyTrackedEntity")
//            }
//        })
    }

    var count = 0
    
    func session(_: ARSession, didUpdate frame: ARFrame) {
        count = count + 1
        
        if count % 2 == 0 {
            let buffer = frame.capturedImage

            bufferWidth = Float(CVPixelBufferGetWidth(buffer))
            bufferHeight = Float(CVPixelBufferGetHeight(buffer))

            if rootLayerHasLoaded == false {
                loadRootLayer()
                loadDetectionOverlay()
                updateLayerGeometry()
            }

            if barbellManager.frontBarbellInitial != nil && barbellManager.backBarbellInitial != nil {
                let buffer = frame.capturedImage
                detector.performDetection(buffer: buffer, completion: { (obs, _) -> Void in
                    guard let observations = obs else {
                        return
                    }
                    self.generateBoundingBox(observations: observations)
                })
            }
        }
        
    }

    func session(_: ARSession, didUpdate anchors: [ARAnchor]) {
        guard character != nil else {
            //print("Character has not been found")
            return
        }

        // This function will update the positions of all the body parts
        bodyPartManager.updateBodyParts(with: character!.jointTransforms)

        // This is the actual results of the new positions. Currently checking left hip and left knee.
        if bodyPartManager.getDifference(firstType: .leftHip, secondType: .leftKnee, axis: .x) < thresholdLegs {
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

    override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
        if let touch = touches.first {
            var position = touch.location(in: arView)
            position = self.rootLayer.convert(position, to: self.detectionOverlay)
            
            print(position)
            if barbellManager.frontBarbellInitial == nil {
                barbellManager.setBarbellInitial(position: position, type: .front)
            } else if barbellManager.backBarbellInitial == nil {
                barbellManager.setBarbellInitial(position: position, type: .back)
            }
        }
    }
    
    func sortResults(results: [VNRecognizedObjectObservation]) -> [VNRecognizedObjectObservation] {
        let topFront = results.sorted(by: {
            let intersec = $0.boundingBox.intersection(barbellManager.frontBarbellPositions.last!)
            let intersec2 = $1.boundingBox.intersection(barbellManager.frontBarbellPositions.last!)
            return intersec.width * intersec.height > intersec2.width * intersec2.height
            
        }).first
        
        let topBack = results.sorted(by: {
            let intersec = $0.boundingBox.intersection(barbellManager.backBarbellPositions.last!)
            let intersec2 = $1.boundingBox.intersection(barbellManager.backBarbellPositions.last!)
            return intersec.width * intersec.height > intersec2.width * intersec2.height
            
        }).first
        
        var final:[VNRecognizedObjectObservation] = []
        if topFront != nil {
            final.append(topFront!)
        }
        if topBack != nil {
            final.append(topBack!)
        }
        
        return final
    }
    
    var gotFirst = false
    
    func getTopResults(_ results: [Any], numResults: Int = 2, targetLabel: String = "mainPlate") -> ArraySlice<VNRecognizedObjectObservation> {
        var topResults: [VNRecognizedObjectObservation] = []
        
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }
            
            if objectObservation.labels[0].identifier == targetLabel {
                topResults.append(objectObservation)
            }
        }
//        if !gotFirst {
//            topResults = topResults.sorted(by: { $0.labels[0].confidence > $1.labels[0].confidence })
//        } else {
//            topResults = sortResults(results: topResults)
//        }
        topResults = topResults.sorted(by: { $0.labels[0].confidence > $1.labels[0].confidence })
        var finalResults = topResults.prefix(numResults)
        
        var foundFirst = false
        var foundSecond = false
        
        var firstRect:CGRect = CGRect(x: 0, y: 0, width: 0, height: 0)
        var secondRect:CGRect = CGRect(x: 0, y: 0, width: 0, height: 0)
    
        for result in finalResults {
            
            let objectBounds = VNImageRectForNormalizedRect( result.boundingBox, Int(self.bufferWidth), Int(self.bufferHeight))
            if barbellManager.frontBarbellPositions.count == 0 {
                if objectBounds.contains(barbellManager.frontBarbellInitial!) {
                    barbellManager.frontBarbellPositions.append(objectBounds)
                }
            } else if barbellManager.backBarbellPositions.count == 0 {
                if objectBounds.contains(barbellManager.backBarbellInitial!) {
                    barbellManager.backBarbellPositions.append(objectBounds)
                    barbellManager.setupKalman()
                }
            } else {
                let iouThreshold:CGFloat = 0.1
                gotFirst = true
                let iouFirst = barbellManager.intersectionOverUnion(firstBounds: objectBounds, secondBounds: barbellManager.frontBarbellPositions.last!)
                let iouSecond = barbellManager.intersectionOverUnion(firstBounds: objectBounds, secondBounds: barbellManager.backBarbellPositions.last!)
                
                if iouFirst > iouThreshold && iouFirst >= iouSecond && foundFirst == false {
                    firstRect = objectBounds
                    foundFirst = true
                } else if iouSecond > iouThreshold {
                    secondRect = objectBounds
                    foundSecond = true
                }
            }
        }
        
        if gotFirst {
            barbellManager.frontBarbellPositions.append(firstRect)
            barbellManager.backBarbellPositions.append(secondRect)
            barbellManager.kalmanAction()
        } else {
            finalResults.removeAll()
        }
        return finalResults
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
        
        let blah = getTopResults(observations)
        
        if (blah.count > 0) {
        
            let shapeLayer = self.barbellManager.createRoundedRectLayerWithBounds(.front, bounds: barbellManager.frontBarbellPositions.last!)

            let textLayer = self.barbellManager.createTextSubLayerInBounds(barbellManager.frontBarbellPositions.last!,
                                                                           identifier: "Main Barbell",
                                                                           confidence: 0.99)
            shapeLayer.addSublayer(textLayer)
            detectionOverlay.addSublayer(shapeLayer)
            
            let shapeLayer2 = self.barbellManager.createRoundedRectLayerWithBounds(.back, bounds: barbellManager.backBarbellPositions.last!)
            
            let textLayer2 = self.barbellManager.createTextSubLayerInBounds(barbellManager.backBarbellPositions.last!,
                                                                           identifier: "Main Barbell",
                                                                           confidence: 0.99)
            shapeLayer2.addSublayer(textLayer2)
            detectionOverlay.addSublayer(shapeLayer2)
        }
        
//        for observation in getTopResults(observations) where observation is VNRecognizedObjectObservation {
//            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
//                continue
//            }
//
//            // Select only the label with the highest confidence.
//            let topLabelObservation = objectObservation.labels[0]
//
//            var objectBounds = VNImageRectForNormalizedRect( objectObservation.boundingBox, Int(self.bufferWidth), Int(self.bufferHeight))
//
//            let boundData = self.barbellManager.analyzeObservation(objectBounds: objectBounds)
//
//            guard let boundRect = boundData.0 else {
//                continue
//            }
//            guard let boundType = boundData.1 else {
//                continue
//            }
//
//            let shapeLayer = self.barbellManager.createRoundedRectLayerWithBounds(boundType, bounds: boundRect)
//
//            let textLayer = self.barbellManager.createTextSubLayerInBounds(boundRect,
//                                                                           identifier: topLabelObservation.identifier,
//                                                                           confidence: topLabelObservation.confidence.magnitude)
//
//            shapeLayer.addSublayer(textLayer)
//            detectionOverlay.addSublayer(shapeLayer)
//            //            let lineLayer = self.barbellManager.createLineLayerWithBounds(boundRect)
//            //            lineLayers.append(lineLayer)
//            //            detectionOverlay.addSublayer(lineLayer)
//        }
        updateLayerGeometry()
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
            CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: scale, y: -scale)
        )
        // center the layer
        detectionOverlay.position = CGPoint (x: bounds.midX, y: bounds.midY)
        
        CATransaction.commit()
    }
    
    
    
    
    
    
    
    
    
    
    
    
    // Made this function to prevent flickering of bounds, needs some work
    func generateAverageBounds(from frames: [CGRect]) -> CGRect {
        let lastFrames = Array(frames.suffix(3))
        
        let count = CGFloat(lastFrames.count)
        
        var averageDiffX: CGFloat = 0
        var averageDiffY: CGFloat = 0
        for index in 0 ..< lastFrames.count - 1 {
            let diffX = lastFrames[index].origin.x - lastFrames[index + 1].origin.x
            let diffY = lastFrames[index].origin.y - lastFrames[index + 1].origin.y
            averageDiffX = averageDiffX + diffX
            averageDiffY = averageDiffY + diffY
        }
        
        averageDiffX = averageDiffX / (count - 1)
        averageDiffY = averageDiffY / (count - 1)
        
        let averageRect = CGRect(x: frames.last!.origin.x + averageDiffX, y: frames.last!.origin.y + averageDiffY, width: frames.last!.width, height: frames.last!.height)
        return averageRect
    }
    
}
