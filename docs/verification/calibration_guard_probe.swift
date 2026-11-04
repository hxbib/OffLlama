import Foundation

let profile = try CalibrationProfile.load(from: URL(fileURLWithPath: CommandLine.arguments[1]))
let expected = 0.90
print("defaultTau", profile.defaultTau, "expected", expected, "equal", profile.defaultTau == expected, "bits", String(profile.defaultTau.bitPattern, radix: 16), String(expected.bitPattern, radix: 16))
print("promptStyle", profile.promptStyle.rawValue, profile.promptStyle == .fewShot)
print("thresholdOverrides", profile.tau, profile.tau.values.allSatisfy { $0 == 0.90 })
print("temperatureOverrides", profile.temperature, profile.temperature.values.allSatisfy { $0 == 1 })
print("finitePriors", profile.prior.values.allSatisfy { $0.allSatisfy(\.isFinite) })
for set in OptionSets.staticSets {
    let key = DecisionPrompt.priorKey(set)
    print(key, "actual", profile.prior[key]?.count ?? -1, "expected", set.activeLetters.count)
}
for n in 2...8 {
    for kind in ["contactPick", "eventPick", "skillPick"] {
        let key = "\(kind)#\(n)"
        print(key, "actual", profile.prior[key]?.count ?? -1, "expected", n)
    }
}
