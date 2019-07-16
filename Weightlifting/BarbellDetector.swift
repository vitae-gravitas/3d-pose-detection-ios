//
//  BarbellDetector.swift
//  Weightlifting
//
//  Created by Avinash Jain on 7/5/19.
//  Copyright © 2019 Avinash Jain. All rights reserved.
//

import CoreML
import Vision

public class BarbellDetector {
    // MARK: - Variables
    private let visionQueue = DispatchQueue(label: "com.viseo.ARML.visionqueue")
    
    private lazy var predictionRequest: VNCoreMLRequest = {
        // Load the ML model through its generated class and create a Vision request for it.
        do {
            let model = try VNCoreMLModel(for: BarbellModel().model)
            let request = VNCoreMLRequest(model: model)
            
            // This setting determines if images are scaled or cropped to fit our 224x224 input size. Here we try scaleFill so we don't cut part of the image.
            request.imageCropAndScaleOption = .scaleFill
            return request
        } catch {
            fatalError("can't load Vision ML model: \(error)")
        }
    }()
    
    // MARK: - Public functions
    public func performDetection(inputBuffer: CVPixelBuffer, completion: @escaping (_ outputObservation: [VNRecognizedObjectObservation]?, _ error: Error?) -> Void) {
        // Right orientation because the pixel data for image captured by an iOS device is encoded in the camera sensor's native landscape orientation
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: inputBuffer, orientation: .up)
        
        // We perform our CoreML Requests asynchronously.
        visionQueue.async {
            // Run our CoreML Request
            do {
                try requestHandler.perform([self.predictionRequest])
                
                guard let observations = self.predictionRequest.results as! [VNRecognizedObjectObservation]? else {
                    completion(nil, nil)
                    throw NSError()
                }
                
                // The resulting image (mask) is available as observation.pixelBuffer
                completion(observations, nil)
            } catch {
                completion(nil, error)
            }
        }
    }
}
