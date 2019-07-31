//
//  BarbellManager.swift
//  Weightlifting
//
//  Created by Avinash Jain on 7/23/19.
//  Copyright © 2019 Avinash Jain. All rights reserved.
//

import Foundation
import UIKit

class BarbellManager {
    var frontBarbellInitial: CGPoint?
    var backBarbellInitial: CGPoint?
    
    var frontBarbellPositions: [CGRect] = []
    var backBarbellPositions: [CGRect] = []
    
    init () {
        self.frontBarbellInitial = nil
        self.backBarbellInitial = nil
    }
    
    func setBarbellInitial(position: CGPoint, type: BarbellType) {
        switch (type) {
        case .front:
            self.frontBarbellInitial = position
        case .back:
            self.backBarbellInitial = position
        }
    }
    
    func analyzeObservation(objectBounds: CGRect) -> (CGRect?, BarbellType?) {
        
        guard let frontInit = frontBarbellInitial else {
            return (nil, nil)
        }
        
        if frontBarbellPositions.count == 0 && objectBounds.contains(frontInit) {
            return updatePosition(position: objectBounds, type: .front)
        }
        
        //&& (frontBarbellPositions.last!.intersects(objectBounds))
        if frontBarbellPositions.count > 0 && frontBarbellPositions.last!.intersects(objectBounds) {
            return updatePosition(position: objectBounds, type: .front)
        }
        
        guard let backInit = backBarbellInitial else {
            return (nil, nil)
        }
        
        if backBarbellPositions.count == 0 && objectBounds.contains(backInit) {
            return updatePosition(position: objectBounds, type: .back)
        }
        
        if backBarbellPositions.count > 0 && backBarbellPositions.last!.intersects(objectBounds) {
            return updatePosition(position: objectBounds, type: .back)
        }
        
        return (nil, nil)
    }
    
    func updatePosition(position: CGRect, type: BarbellType) -> (CGRect?, BarbellType) {
        switch (type) {
        case .front:
            self.frontBarbellPositions.append(updateBarbellRect(frontBarbellPositions, position))
            return (self.frontBarbellPositions.last, .front)
        case .back:
            self.backBarbellPositions.append(updateBarbellRect(backBarbellPositions, position))
            return (self.backBarbellPositions.last, .back)
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
    case back
}
