//
//  BodyPartManager.swift
//  Weightlifting
//
//  Created by Avinash Jain on 6/27/19.
//  Copyright © 2019 Avinash Jain. All rights reserved.
//

import Foundation
import RealityKit
import ARKit


class BodyPartManager {
    
    var bodyParts: [BodyPart] = []
    
    init(with bodyTypes: [BodyPartType]) {
        for type in bodyTypes {
            bodyParts.append(BodyPart(type: type, position: nil, id: idForBodyPart(type: type)))
        }
    }
    
    // IDs for each body part derived from the list of different parts in jointNames
    func idForBodyPart(type: BodyPartType) -> Int{
        switch(type) {
        case .leftHip:
            return 2
        case .leftKnee:
            return 3
        case .rightHip:
            return 7
        case .rightKnee:
            return 8
        }
    }
    
    // Takes in the array of jointTransforms and updates the position of each body part in the array
    func updateBodyParts(with jointTransforms:[Transform]) {
        for bodyPart in bodyParts {
            let rotationVector = jointTransforms[bodyPart.id].rotation.vector
            let rotationMatrix = getRotationMatrixFrom(vector: rotationVector)
            bodyPart.position = jointTransforms[bodyPart.id].translation * rotationMatrix
        }
    }
    
    // Takes in two body part types and an axis, getting the positions of both body parts and compares them on that axis
    func getDifference(firstType: BodyPartType, secondType: BodyPartType, axis: AxisType) -> Float {
        let bp1 = bodyParts.first(where: {$0.type == firstType})!
        let bp2 = bodyParts.first(where: {$0.type == secondType})!
        var val:Float = 100.0
        if (bp1.position != nil && bp2.position != nil) {
            switch (axis) {
            case .x:
                val = abs(bp1.position!.x - bp2.position!.x)
            case .y:
                val = abs(bp1.position!.y - bp2.position!.y)
            case .z:
                val = abs(bp1.position!.z - bp2.position!.z)
            }
        }
        return val
    }
    
    // Produces the rotation matrix from a given rotational vector
    func getRotationMatrixFrom(vector: simd_float4) -> simd_float3x3 {
        let qxs = (vector.x) * (vector.x)
        let qys = (vector.y) * (vector.y)
        let qzs = (vector.z) * (vector.z)
        
        let qxqw = (vector.x) * (vector.w)
        let qxqy = (vector.x) * (vector.y)
        let qxqz = (vector.x) * (vector.z)
        
        let qyqw = (vector.y) * (vector.w)
        let qyqz = (vector.y) * (vector.z)
        
        let qzqw = (vector.z) * (vector.w)
        
        let rows = [
            simd_float3((1-2*qys-2*qzs),
                        (2*qxqy - 2*qzqw),
                        (2*qxqz + 2*qyqw)),
            simd_float3((2*qxqy + 2*qzqw),
                        (1-2*qxs-2*qzs),
                        (2*qyqz - 2*qxqw)),
            simd_float3((2*qxqz-2*qyqw),
                        (2*qyqz+2*qxqw),
                        (1-2*qxs-2*qys))
        ]
        
        return float3x3(rows: rows)
    }
}

// Class for handling every Body Part - each body part has a type, position and id
class BodyPart {
    var type: BodyPartType
    var position: simd_float3?
    var id: Int
    
    init(type: BodyPartType, position: simd_float3?, id: Int) {
        self.type = type
        self.position = position
        self.id = id
    }
}

// Enum for handling the different types of body parts we're searching for
enum BodyPartType {
    case rightHip
    case rightKnee
    case leftHip
    case leftKnee
}

// Enum for handling which axis the positions should be compared on
enum AxisType {
    case x
    case y
    case z
}
