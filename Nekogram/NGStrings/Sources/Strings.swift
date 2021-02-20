//
//  Strings.swift
//  _idx_AccountContext_7AD52E5C_ios_min9.0
//
//  Created by 梨子 on 2021/2/20.
//

import Foundation
import AppBundle

private func gd(locale: String) -> [String : String] {
    guard let mainPath = getAppBundle().path(forResource: locale, ofType: "lproj"), let bundle = Bundle(path: mainPath) else {
        return [:]
    }
    guard let path = bundle.path(forResource: "NekoLocalizable", ofType: "strings") else {
        return [:]
    }
    guard let dict = NSDictionary(contentsOf: URL(fileURLWithPath: path)) as? [String: String] else {
        return [:]
    }
    return dict
}

let nekoLocales: [String : [String : String]] = [
    "en": gd(locale: "en"),
    "zh-hans": gd(locale: "zh-Hans"),
    "zh-hant": gd(locale: "zh-Hant"),
    "zh-hk": gd(locale: "zh-HK"),
    "ja": gd(locale: "ja"),
]

public func getLangFallback(_ lang: String) -> String {
    switch (lang) {
    case "zh-hant":
        return "zh-hans"
    case "zh-hk":
        return "zh-hans"
    default:
        return "en"
    }
}

func getFallbackKey(_ key: String) -> String {
    switch (key) {
    default:
        return key
    }
}

public func l(_ key: String, _ locale: String = "en") -> String {
    var lang = locale
    let key = getFallbackKey(key)
    let rawSuffix = "-raw"
    if lang.hasSuffix(rawSuffix) {
        lang = String(lang.dropLast(rawSuffix.count))
    }
    
    if !nekoLocales.keys.contains(lang) {
        lang = "en"
    }
    
    var result = "[MISSING STRING. PLEASE UPDATE APP]"
    
    if let res = ngWebLocales[lang]?[key], !res.isEmpty {
        result = res
    } else if let res = nekoLocales[lang]?[key], !res.isEmpty {
        result = res
    } else if let res = nekoLocales[getLangFallback(lang)]?[key], !res.isEmpty {
        result = res
    } else if let res = nekoLocales["en"]?[key], !res.isEmpty {
        result = res
    } else if !key.isEmpty {
        result = key
    }
    
    return result
}


public func getStringsUrl(_ lang: String) -> String {
    return "https://raw.githubusercontent.com/satouriko/nekolite-ios/master/Telegram/Telegram-iOS/" + lang + ".lproj/NekoLocalizable.strings"
}


var ngWebLocales: [String: [String: String]] = [:]

func getWebDict(_ lang: String) -> [String : String]? {
    return NSDictionary(contentsOf: URL(string: getStringsUrl(lang))!) as? [String : String]
}

public func downloadLocale(_ locale: String) -> Void {
    do {
        var lang = locale
        let rawSuffix = "-raw"
        if lang.hasSuffix(rawSuffix) {
            lang = String(lang.dropLast(rawSuffix.count))
        }
        if let localeDict = try getWebDict(lang) {
            ngWebLocales[lang] = localeDict
        }
    } catch {
        return
    }
}
