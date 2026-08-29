//
//  LocationViewModel.swift
//  wheater
//
//  Created by Hanif Fadillah Amrynudin on 04/09/22.
//

import Foundation
import CoreLocation
import CoreLocationUI

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()

    @Published var location: CLLocationCoordinate2D?

    override init() {
        super.init()
        
        manager.requestWhenInUseAuthorization()
        
        manager.delegate = self
    }

    func requestLocation() {
        manager.requestLocation()
        print(manager.location?.coordinate.latitude ?? "test")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.first?.coordinate
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print(error)
    }
}
