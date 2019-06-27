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

class ViewController: UIViewController, ARSessionDelegate {
    
    @IBOutlet var arView: ARView!
    
    // The 3D character to display.
    var character: BodyTrackedEntity?
    let characterOffset: SIMD3<Float> = [-1.0, 0, 0] // Offset the character by one meter to the left
    let characterAnchor = AnchorEntity()
    
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
