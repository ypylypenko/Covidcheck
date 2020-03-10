//
//  DataManager.swift
//  Coronacheck
//
//  Created by Julian Schiavo on 30/1/2020.
//  Copyright © 2020 Julian Schiavo. All rights reserved.
//

import Foundation

class DataManager: ObservableObject {
    
    enum DataManagerError: Error {
        case failedToLoad
        
        var localizedDescription: String {
            switch self {
            case .failedToLoad: return "Failed to load data."
            }
        }
    }
    
    struct RawData: Codable {
        var title: String
        //        var lastUpdatedDate: Date
        var rawCountries: [RawCountryInfo]
        
        var countries: [CountryInfo] {
            rawCountries.map { $0.country }
        }
        
        enum CodingKeys: String, CodingKey {
            case title
            //            case lastUpdatedDate = "last_updated"
            case rawCountries = "entries"
        }
    }
    
    @Published var countryGroups = [RegionInfo]()
    @Published var expandedRegions = [Region]()
    @Published var currentCaseDifference = 0
    
    private var baseURL: URL
    
    // MARK: - Status
    
    enum Status {
        case fetchStarting(URL)
        case fetchSuccessful(URL)
        case fetchFailed(URL, Error?)
        case decodeSuccessful
        case decodeFailed(URL?, Error?)
        case custom(String)
    }
    
    static func request(ofType type: String, didChangeStatus status: Status) {
        switch status {
        case let .fetchStarting(url):
            print("Starting \(type) request with URL:", url)
        case let .fetchSuccessful(url):
            print("\(type) request (URL: \(url)) finished successfully")
        case let .fetchFailed(url, error):
            print("\(type) request (URL: \(url)) failed with error:", error as Any)
        case .decodeSuccessful:
            print("\(type) decoding finished successfully")
        case let .decodeFailed(url, error):
            print("\(type) decoding failed with URL:", url ?? "", "and error:", error as Any)
        case let .custom(text):
            print("\(type) \(text)")
        }
    }
    
    // MARK: - Data
    
    var overallCountry: CountryInfo {
        let infectionCount = countryGroups.flatMap { $0.countries }.map { $0.infectionCount }.reduce(0, +)
        let deathCount = countryGroups.flatMap { $0.countries }.map { $0.deathCount }.reduce(0, +)
        let recoveredCount = countryGroups.flatMap { $0.countries }.map { $0.recoveredCount }.reduce(0, +)
        
        return CountryInfo(name: "Overall", infectionCount: infectionCount, deathCount: deathCount, recoveredCount: recoveredCount, difference: currentCaseDifference, lastUpdated: "", comments: "")
    }
    
    func updateData() {
        fetchData { result in
            switch result {
            case let .success(countries):
                self.createCountryRegionList(countries: countries)
            case let .failure(error):
                print("Failed to update data with error", error.localizedDescription)
            }
        }
    }
    
    func createCountryRegionList(countries: [CountryInfo]) {
        var countryGroups = [RegionInfo]()
        
        for region in Region.allCases {
            let regionCountries = countries
                .filter { $0.infectionCount > 0 }
                .filter { $0.data?.region ?? .restOfTheWorld == region }
                .sorted { $0.infectionCount > $1.infectionCount }
            let countryGroup = RegionInfo(region: region, countries: regionCountries)
            countryGroups.append(countryGroup)
        }
        
        countryGroups = countryGroups.filter { !$0.countries.isEmpty }
        countryGroups.sort { $0.totalInfectionCount > $1.totalInfectionCount }
        
        DispatchQueue.main.async {
            self.countryGroups = countryGroups
            self.updateDifferenceData()
        }
    }
    
    private func fetchData(completion: @escaping (Result<[CountryInfo], Error>) -> Void) {
        let type = "FetchData"
                
        let url = baseURL.appendingPathComponent("/sheet/wuhan/viruscases.json")
        DataManager.request(ofType: type, didChangeStatus: .fetchStarting(url))
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                DataManager.request(ofType: type, didChangeStatus: .fetchFailed(url, error))
                completion(.failure(error ?? DataManagerError.failedToLoad))
                return
            }
            DataManager.request(ofType: type, didChangeStatus: .fetchSuccessful(url))
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                let rawData = try decoder.decode(RawData.self, from: data)
                DataManager.request(ofType: type, didChangeStatus: .decodeSuccessful)
                completion(.success(rawData.countries))
            } catch {
                DataManager.request(ofType: type, didChangeStatus: .decodeFailed(url, error))
                completion(.failure(error))
            }
        }
        task.resume()
    }
    
    // MARK: - Region Expansion
    
    var areAllRegionsExpanded: Bool {
        expandedRegions == Region.allCases
    }
    
    func toggleAllRegionsExpanded() {
        if areAllRegionsExpanded {
            expandedRegions = []
        } else {
            expandedRegions = Region.allCases
        }
    }
    
    // MARK: - Case Difference
    
    private func updateDifferenceData() {
        let oldInfectionCount = UserDefaults.standard.integer(forKey: "InfectionCount")
        let oldDeathCount = UserDefaults.standard.integer(forKey: "DeathCount")
        let oldRecoveredCount = UserDefaults.standard.integer(forKey: "RecoveredCount")
        
        let infectionCount = countryGroups.flatMap { $0.countries }.map { $0.infectionCount }.reduce(0, +)
        let deathCount = countryGroups.flatMap { $0.countries }.map { $0.deathCount }.reduce(0, +)
        let recoveredCount = countryGroups.flatMap { $0.countries }.map { $0.recoveredCount }.reduce(0, +)
        
        guard oldInfectionCount != infectionCount || oldDeathCount != deathCount || oldRecoveredCount != recoveredCount else { return }
        
        UserDefaults.standard.set(infectionCount, forKey: "InfectionCount")
        UserDefaults.standard.set(deathCount, forKey: "DeathCount")
        UserDefaults.standard.set(recoveredCount, forKey: "RecoveredCount")
        
        let oldCurrentCaseCount = oldInfectionCount - oldDeathCount - oldRecoveredCount
        let newCurrentCaseCount = infectionCount - deathCount - recoveredCount
        currentCaseDifference = newCurrentCaseCount - oldCurrentCaseCount
    }
    
    // MARK: - Singleton
    
    static var shared = DataManager()
    private init() {
        let baseURLString = "https://interactive-static.scmp.com"
        guard let baseURL = URL(string: baseURLString) else {
            fatalError("Invalid base URL - you are stupid!")
        }
        self.baseURL = baseURL
        
        updateData()
    }
    
}
