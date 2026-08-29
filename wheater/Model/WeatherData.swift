//
//  WeatherData.swift
//  wheater
//
//  Created by Hanif Fadillah Amrynudin on 01/09/22.
//

import Foundation
import Foundation

struct WeatherDataMain: Decodable {
    let weatherData: [WeatherData]
}

struct WeatherData: Decodable {
    
    let name: String
    let wind: Wind
    let main: Main
    let weather: [Weather]
    
}

struct Wind: Decodable {
    let speed: Float
}

struct Main: Decodable {
    let temp: Float
    let humidity: Int
}

struct Weather: Decodable {
    let main: String
    let id: Int
}

