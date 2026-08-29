import SwiftUI
import Combine

class AnniversaryViewModel: ObservableObject {
    @Published var daysSinceAnniversaryString: String = ""
    @Published var nextAnniversary: String = ""
    @Published var daysSince: Double = 0.0

    private let anniversaryDate: Date
    private var timer: AnyCancellable?

    init() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        self.anniversaryDate = dateFormatter.date(from: "2024-03-12")! // 修改为你的纪念日日期
        
        updateAnniversaryData()
        
        // 每秒更新一次数据
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                self.updateAnniversaryData()
            }
    }
    
    private func updateAnniversaryData() {
        let currentDate = Date()
        let calendar = Calendar.current
        
        // 计算距离纪念日的天数
        let timeIntervalSince = currentDate.timeIntervalSince(anniversaryDate)
        let daysSince = timeIntervalSince / (24 * 60 * 60)
        self.daysSince = daysSince
        self.daysSinceAnniversaryString = String(format: "🐰兔可可已经到来%.3f天啦", daysSince)

        // 计算下一个100天纪念日
        let next100DayMark = ((Int(daysSince) / 100) + 1) * 100
        let nextAnniversaryDate = calendar.date(byAdding: .day, value: next100DayMark, to: anniversaryDate)!
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        self.nextAnniversary = "🌿下一个纪念日是 \(dateFormatter.string(from: nextAnniversaryDate))"
    }
    
    deinit {
        timer?.cancel() // 停止计时器
    }
}
