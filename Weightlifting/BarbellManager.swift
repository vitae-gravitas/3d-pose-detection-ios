//
//  BarbellManager.swift
//  Weightlifting
//
//  Created by Avinash Jain on 7/23/19.
//  Copyright © 2019 Avinash Jain. All rights reserved.
//

import Accelerate
import Foundation
import simd
import UIKit

class BarbellManager {
    var frontBarbellInitial: CGPoint?
    var frontBarbellPositions: [CGRect] = []
    
    init() {
        frontBarbellInitial = nil
    }
    
    func setBarbellInitial(position: CGPoint, type: BarbellType) {
        switch type {
        case .front:
            frontBarbellInitial = position
        }
    }
    
    func resetData() {
        self.frontBarbellInitial = nil
        self.frontBarbellPositions.removeAll()
    }
    
    func analyzeObservation(objectBounds: CGRect) -> (CGRect?, BarbellType?) {
        guard let frontInit = frontBarbellInitial else {
            return (nil, nil)
        }
        
        if frontBarbellPositions.count == 0, objectBounds.contains(frontInit) {
            return updatePosition(position: objectBounds, type: .front)
        }
        
        // && (frontBarbellPositions.last!.intersects(objectBounds))
        if frontBarbellPositions.count > 0, frontBarbellPositions.last!.intersects(objectBounds) {
            return updatePosition(position: objectBounds, type: .front)
        }
        
        return (nil, nil)
    }
    
    func updatePosition(position: CGRect, type: BarbellType) -> (CGRect?, BarbellType) {
        switch type {
        case .front:
            frontBarbellPositions.append(updateBarbellRect(frontBarbellPositions, frontBarbellPositions.removeLast()))
            return (frontBarbellPositions.last, .front)
        }
    }
    
    func updateBarbellRect(_ frames: [CGRect], _ rect: CGRect) -> CGRect {
        if frames.count < 5 {
            return rect
        }
        let finalFrames = frames.suffix(20)
        var width: CGFloat = 0.0
        var height: CGFloat = 0.0
        for rect in finalFrames {
            width = width + rect.width
            height = height + rect.height
        }
        
        let diffX = rect.origin.x - finalFrames.last!.origin.x
        var rect = CGRect(x: finalFrames.last!.origin.x + 0.4 * diffX, y: rect.origin.y, width: rect.width, height: rect.height)
        
        var ratio: CGFloat = 0.7
        
        width = ratio * (width / CGFloat(finalFrames.count)) + (1 - ratio) * rect.width
        height = ratio * (height / CGFloat(finalFrames.count)) + (1 - ratio) * rect.height
        
        let newX = (rect.midX - width / 2.0)
        let newY = (rect.midY - height / 2.0)
        
        return CGRect(x: newX, y: newY, width: width, height: height)
    }
    
    
    
    
    
    
    
    
    
    func intersectionOverUnion(firstBounds: CGRect, secondBounds: CGRect) -> CGFloat {
        let intersectionBounds = firstBounds.intersection(secondBounds)
        let interArea = intersectionBounds.width * intersectionBounds.height
        let firstBoundsArea = firstBounds.width * firstBounds.height
        let secondBoundsArea = secondBounds.width * secondBounds.height
        let unionArea = firstBoundsArea + secondBoundsArea - interArea
        return interArea / unionArea
    }
    
    func transformPrediction(bounds: CGRect) -> Matrix {
        return Matrix([Double(bounds.origin.x), Double(bounds.origin.y), Double(bounds.width/bounds.height), Double(bounds.height)])
    }
    
    let ndim = 4
    let dt = 1
    let motionMatrix = Matrix([
        [1, 0, 0, 0, 1, 0, 0, 0],
        [0, 1, 0, 0, 0, 1, 0, 0],
        [0, 0, 1, 0, 0, 0, 1, 0],
        [0, 0, 0, 1, 0, 0, 0, 1],
        [0, 0, 0, 0, 1, 0, 0, 0],
        [0, 0, 0, 0, 0, 1, 0, 0],
        [0, 0, 0, 0, 0, 0, 1, 0],
        [0, 0, 0, 0, 0, 0, 0, 1],
        ])
    
    let updateMatrix = Matrix([
        [1, 0, 0, 0, 0, 0, 0, 0],
        [0, 1, 0, 0, 0, 0, 0, 0],
        [0, 0, 1, 0, 0, 0, 0, 0],
        [0, 0, 0, 1, 0, 0, 0, 0],
        ])
    let stdWeightPosition:Double = 1.0 / 20.0
    let stdWeightVelocity:Double = 1.0 / 160.0
    
    func initializeKalman(matrix: Matrix) -> KalmanData {
        let mean = Matrix([matrix.grid[0], matrix.grid[1], matrix.grid[2], matrix.grid[3], 0.0, 0.0, 0.0, 0.0])
        let standardDeviation = Matrix([
            [0.0001, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            [0.0, 0.0001, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.0001, 0.0, 0.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.0, 0.0001, 0.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.0, 0.0, 0.0001, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.0, 0.0, 0.0, 0.0001, 0.0, 0.0],
            [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0001, 0.0],
            [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0001],
            ])
        return KalmanData(mean: mean, covariance: standardDeviation)
    }
    
    func predict(mean: Matrix, covariance: Matrix) -> KalmanData {
        let motionCovariance = Matrix([
            [0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            [0.0, 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.0000000001, 0.0, 0.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.0, 0.0000000001, 0.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.0, 0.0, 0.05, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.0, 0.0, 0.0, 0.05, 0.0, 0.0],
            [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0000000001, 0.0],
            [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0000000001],
            ])
        let updatedMean = (motionMatrix <*> mean.transpose()).transpose()
        let result = motionMatrix <*> covariance <*> motionMatrix.transpose() + motionCovariance
        return KalmanData(mean: updatedMean, covariance: result)
    }
    
    func project(mean: Matrix, covariance: Matrix) -> KalmanData {
        let val = (stdWeightPosition * mean.grid[3])
        let std = Matrix([val*val, val*val, 1, val*val])
        let innovationCovariance = Matrix([
            [std.grid[0], 0, 0, 0],
            [0,std.grid[1],0,0],
            [0,0,std.grid[2],0],
            [0,0,0,std.grid[3]],
            ])
        var m = updateMatrix <*> mean.transpose()
        let c = updateMatrix <*> covariance <*> updateMatrix.transpose()
        return KalmanData(mean: m, covariance: c + innovationCovariance)
    }
    
    func cholesky(matrix: [Double], n: Int) -> [Double] {
        var res = [Double](repeating: 0, count: matrix.count)
        
        for i in 0..<n {
            for j in 0..<i+1 {
                var s = 0.0
                
                for k in 0..<j {
                    s += res[i * n + k] * res[j * n + k]
                }
                
                if i == j {
                    res[i * n + j] = (matrix[i * n + i] - s).squareRoot()
                } else {
                    res[i * n + j] = (1.0 / res[j * n + j] * (matrix[i * n + j] - s))
                }
            }
        }
        return res
    }
    
    func solveCholeskyForward(lMatrix: [Double], bMatrix:[Double], n: Int) -> [Double] {
        var res = [Double](repeating: 0, count: bMatrix.count)
        let rowSize = bMatrix.count / n
        
        for i in 0..<n {
            for j in 0..<rowSize {
                var val = bMatrix[j + rowSize * i]
                for k in 0..<i {
                    val -= res[j + rowSize * k] * bMatrix[j + rowSize * i]
                }
                res[j + rowSize * i] = val / lMatrix[i + 4 * i]
            }
        }
        return res
    }
    
    func solveCholeskyBackward(lMatrix: [Double], bMatrix:[Double], n: Int) -> [Double] {
        var res = [Double](repeating: 0, count: bMatrix.count)
        let rowSize = bMatrix.count / n
        
        for i in stride(from: n-1, through: 0, by: -1) {
            for j in stride(from: rowSize-1, through: 0, by: -1) {
                var val = bMatrix[j + rowSize * i]
                for k in stride(from: i-1, through: 0, by: -1) {
                    val -= res[j + rowSize * k] * bMatrix[j + rowSize * i]
                }
                res[j + rowSize * i] = val / lMatrix[i + 4 * i]
            }
        }
        return res
    }
    
    func update(mean: Matrix, covariance: Matrix, measurement: Matrix) -> KalmanData {
        let projection = project(mean: mean, covariance: covariance)
        
        let innovation = measurement - projection.mean.transpose()
        
        let chol_factor = Matrix(cholesky(matrix: projection.covariance.array.flatMap({$0}), n: 4))
        let cholMatrix = Matrix(stride(from: 0, to: chol_factor.count, by: 4).map {
            Array(chol_factor.grid[$0..<$0+4])
        })
        
        let solutionMatrix = (covariance <*> updateMatrix.transpose()).transpose()
        let flattenedSolutionMatrix = solutionMatrix.flatMap({$0})
        let yMatrix = solveCholeskyForward(lMatrix: chol_factor.grid, bMatrix: flattenedSolutionMatrix, n: 4)
        let flattenedGain = solveCholeskyBackward(lMatrix: cholMatrix.transpose().array.flatMap({$0}), bMatrix: yMatrix, n: 4)
        let kalmanGain =  Matrix(stride(from: 0, to: flattenedGain.count, by: 8).map {
            Array(flattenedGain[$0..<$0+8])
        }).transpose()
        
        let newMean = mean + innovation <*> kalmanGain.transpose()
        let newCovariance = covariance - (kalmanGain <*> projection.covariance <*> kalmanGain.transpose())
        return KalmanData(mean: newMean, covariance: newCovariance)
    }
    
    func kalmanLoop(mean: Matrix, covariance: Matrix, measurement: Matrix) -> KalmanData {
        let updateData = update(mean: mean, covariance: covariance, measurement: measurement)
        let predictedData = predict(mean: updateData.mean, covariance: updateData.covariance)
        return predictedData
        
    }
    
    let sentinel = CGRect(x: 0, y: 0, width: 0, height: 0)
    var frontKalman: KalmanData?
    var backKalman: KalmanData?
    
    func setupKalman() {
        frontKalman = initializeKalman(matrix: transformPrediction(bounds: self.frontBarbellPositions.first!))
    }
    
    func kalmanAction() {
        
        // Set to initial random value
        var z1: Matrix = frontKalman!.mean
        
        let frontBarbell = frontBarbellPositions.removeLast()
        
        if (!frontBarbell.equalTo(sentinel)) {
            z1 = transformPrediction(bounds: frontBarbell)
        } else {
            z1 = Matrix(Array(predict(mean: frontKalman!.mean, covariance: frontKalman!.covariance).mean.grid.prefix(4)))
        }
        
        
        frontKalman = kalmanLoop(mean: frontKalman!.mean, covariance: frontKalman!.covariance, measurement: z1)
       
        print(frontKalman!.getRect())
    
        frontBarbellPositions.append(frontKalman!.getRect())
        
        
    }
}

struct KalmanData {
    var mean: Matrix
    var covariance: Matrix
    
    func getRect() -> CGRect {
        let arr = mean.grid
        return CGRect(x: arr[0], y: arr[1], width: arr[2] * arr[3], height: arr[3])
    }
}

// MARK: - Bounding Box overlay drawing extension

extension BarbellManager {
    func createTextSubLayerInBounds(_ bounds: CGRect, identifier: String, confidence: Float) -> CATextLayer {
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
    
    func createRoundedRectLayerWithBounds(_ type: BarbellType, bounds: CGRect) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = bounds
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Found Object"
        if type == .front {
            shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 0.2, 0.4])
        } else {
            shapeLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.2, 1.0, 1.0, 0.4])
        }
        shapeLayer.cornerRadius = 7
        // .transform = CATransform3DMakeRotation(270.0 / 180.0 * .pi, 0.0, 0.0, 1.0)
        return shapeLayer
    }
    
    func createLineLayerWithBounds(_ bounds: CGRect) -> CALayer {
        let shapeLayer = CALayer()
        shapeLayer.bounds = CGRect(x: bounds.midX - 30, y: bounds.midY - 30, width: 30, height: 30)
        shapeLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shapeLayer.name = "Line"
        shapeLayer.backgroundColor = UIColor.red.cgColor
        shapeLayer.cornerRadius = 15
        return shapeLayer
    }
}

enum BarbellType {
    case front
}
