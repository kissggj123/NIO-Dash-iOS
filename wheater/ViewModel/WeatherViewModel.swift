//
//  WeatherManager.swift
//  wheater
//
//  Created by Hanif Fadillah Amrynudin on 01/09/22.
//

import Foundation
import CoreLocation
import ActivityKit

class WeatherViewModel : ObservableObject {
    
    // 您的 @Published 属性保持不变
    @Published var weatherViewModel = [WeatherModel]()
    // 这个属性不再需要，因为 ContentState 是在需要时动态创建的
    // @Published var weatherAttributes = [WheaterAttributes.ContentState]()
    
    let weatherURL = "https://api.openweathermap.org/data/2.5/weather?appid=a1faa9b0d55de0551810719a5bca6491&units=metric"
    
    // --- 关键修正 1：修改 fetchWeather(CityName:) ---
    // 虽然这个函数在当前设计中不直接需要回调，但保持 API 一致性是个好习惯
    func fetchWeather(CityName: String) {
        // 为了安全，对城市名称进行 URL 编码
        guard let encodedCityName = CityName.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else { return }
        let urlString = "\(weatherURL)&q=\(encodedCityName)"
        performRequest(with: urlString)
    }
    
    // --- 关键修正 2：为 fetchWeather(latitude:longitude:) 添加回调闭包 ---
    // 我们在函数定义中添加了一个可选的回调参数 completion
    func fetchWeather(latitude: CLLocationDegrees, longitude: CLLocationDegrees, completion: ((String?) -> Void)? = nil) {
        let urlString = "\(weatherURL)&lat=\(latitude)&lon=\(longitude)"
        // 将回调闭包传递给 performRequest
        performRequest(with: urlString, completion: completion)
    }
    
    // --- 关键修正 3：让 performRequest 能够处理回调 ---
    // 我们在这里也添加了回调参数
    func performRequest(with urlString: String, completion: ((String?) -> Void)? = nil) {
        if let url = URL(string: urlString) {
            let session = URLSession(configuration: .default)
            
            // 在创建 task 时，我们将回调闭包捕获到 handle 函数中
            let task = session.dataTask(with: url) { data, response, error in
                self.handle(data: data, response: response, error: error, completion: completion)
            }
            task.resume()
        }
    }
    
    // --- 关键修正 4：让 handle 函数能够执行回调 ---
    func handle(data: Data?, response: URLResponse?, error: Error?, completion: ((String?) -> Void)? = nil) {
        if error != nil {
            print(error!.localizedDescription)
            completion?(nil) // 如果出错，返回 nil
            return
        }
        
        if let safeData = data {
            // parseJSON 现在会返回解析出的模型
            if let weather = parseJSON(safeData) {
                DispatchQueue.main.async {
                    // 更新我们的 UI 数据
                    self.weatherViewModel = [weather]
                    // 成功后，通过回调返回城市名称
                    completion?(weather.nameCity)
                }
            } else {
                completion?(nil) // 如果解析失败，返回 nil
            }
        }
    }
    
    // --- 关键修正 5：修改 parseJSON 的返回值和内部逻辑 ---
    func parseJSON(_ wheaterData: Data) -> WeatherModel? {
        let decoder = JSONDecoder()
        do {
            let decodedData = try decoder.decode(WeatherData.self, from: wheaterData)
            
            let name = decodedData.name
            let speedWind = decodedData.wind.speed
            let temp = decodedData.main.temp
            let hum = decodedData.main.humidity
            let id = decodedData.weather[0].id
            let desc = decodedData.weather[0].main
            
            // 创建模型并直接返回，不再在这里更新 @Published 属性
            let weather = WeatherModel(conditionId: id, nameCity: name, wind: Float(speedWind), temp: Float(temp), hum: hum, desc: desc)
            return weather
            
        } catch {
            print("JSON Parsing Error: \(error)")
            return nil
        }
    }
    
    // 您需要一个 WeatherData 结构体来解码 JSON，如果还没有，请添加这个
    struct WeatherData: Codable {
        let name: String
        let main: Main
        let weather: [Weather]
        let wind: Wind
    }

    struct Main: Codable {
        let temp: Double
        let humidity: Int
    }

    struct Weather: Codable {
        let id: Int
        let main: String
    }
    
    struct Wind: Codable {
        let speed: Double
    }
}
