//
//  WeatherOffloadBridge.swift
//  MinisApp
//
//  iOS 15 backport: WeatherKit is iOS 16+. Stubbed.
//

import Foundation

@objc public class WeatherOffloadBridge: NSObject {

    @objc public static func fetchWeather(
        forLatitude lat: Double,
        longitude lng: Double,
        completion: @escaping (NSDictionary?, Error?) -> Void
    ) {
        // iOS 15 backport: WeatherKit not available
        let error = NSError(domain: "WeatherOffload", code: -1, 
                           userInfo: [NSLocalizedDescriptionKey: "WeatherKit requires iOS 16+"])
        completion(nil, error)
    }
}
