import Foundation

// MARK: - KNS User model

struct KNSUser: Identifiable, Equatable {
    let id: Int            // list position 000–099
    var userID: String
    var password: String
    var description: String
    var rxOnly: Bool       // true = RX only, false = TX/RX
    var disabled: Bool     // true = temporarily disabled
}

// MARK: - KenwoodKNS

enum KenwoodKNS {

    enum AccountType: String {
        case administrator = "0"
        case user          = "1"
    }

    enum KNSMode: Int, CaseIterable {
        case off      = 0
        case lan      = 1
        case internet = 2
        var label: String {
            switch self {
            case .off:      return "Off"
            case .lan:      return "LAN Only"
            case .internet: return "Internet"
            }
        }
    }

    /// VoIP jitter buffer — P1 raw value (×20 ms).
    enum JitterBuffer: Int, CaseIterable {
        case ms80  = 4
        case ms200 = 10
        case ms500 = 25
        case ms800 = 40
        var label: String {
            switch self {
            case .ms80:  return "80 ms"
            case .ms200: return "200 ms"
            case .ms500: return "500 ms"
            case .ms800: return "800 ms"
            }
        }
    }

    /// Session timeout — P1 raw value (00–13).
    enum SessionTimeout: Int, CaseIterable {
        case min1  = 0,  min2,  min3
        case min5  = 3,  min10 = 4, min15 = 5
        case min20 = 6,  min30 = 7, min40 = 8, min50 = 9
        case min60 = 10, min90 = 11, min120 = 12, unlimited = 13
        var label: String {
            switch self {
            case .min1:      return "1 min"
            case .min2:      return "2 min"
            case .min3:      return "3 min"
            case .min5:      return "5 min"
            case .min10:     return "10 min"
            case .min15:     return "15 min"
            case .min20:     return "20 min"
            case .min30:     return "30 min"
            case .min40:     return "40 min"
            case .min50:     return "50 min"
            case .min60:     return "60 min"
            case .min90:     return "90 min"
            case .min120:    return "120 min"
            case .unlimited: return "Unlimited"
            }
        }
    }

    // MARK: - Connection / Login

    static func knsConnect() -> String { "##CN;" }

    /// ##ID login frame — P1 account type, P2 2-digit account length,
    /// P3 2-digit password length, then account string, then password string.
    static func knsLogin(accountType: AccountType = .administrator,
                         account: String, password: String) -> String {
        let accountLen  = String(format: "%02d", account.utf8.count)
        let passwordLen = String(format: "%02d", password.utf8.count)
        return "##ID\(accountType.rawValue)\(accountLen)\(passwordLen)\(account)\(password);"
    }

    // MARK: - ##KN0  KNS operation mode  (admin only, set + read)

    static func readKNSMode()           -> String { "##KN0;" }
    static func setKNSMode(_ m: KNSMode) -> String { "##KN0\(m.rawValue);" }

    // MARK: - ##KN1  Change administrator credentials  (admin only, set only)
    //  Format: ##KN1 + P1(2,curIDlen) + P2(2,curPWlen) + P3(2,newIDlen)
    //               + P4(2,newPWlen) + curID + curPW + newID + newPW + ;

    static func changeAdminCredentials(currentID: String, currentPW: String,
                                       newID: String,     newPW: String) -> String {
        let p1 = String(format: "%02d", currentID.utf8.count)
        let p2 = String(format: "%02d", currentPW.utf8.count)
        let p3 = String(format: "%02d", newID.utf8.count)
        let p4 = String(format: "%02d", newPW.utf8.count)
        return "##KN1\(p1)\(p2)\(p3)\(p4)\(currentID)\(currentPW)\(newID)\(newPW);"
    }

    // MARK: - ##KN2  Built-in VoIP function  (admin only, set + read)

    static func readVoIPEnabled()          -> String { "##KN2;" }
    static func setVoIPEnabled(_ on: Bool) -> String { "##KN2\(on ? 1 : 0);" }

    // MARK: - ##KN4  VoIP jitter buffer  (admin only, set + read)

    static func readVoIPJitterBuffer()              -> String { "##KN4;" }
    static func setVoIPJitterBuffer(_ b: JitterBuffer) -> String {
        String(format: "##KN4%02d;", b.rawValue)
    }

    // MARK: - ##KN5  Speaker mute during remote operation  (admin only, set + read)

    static func readSpeakerMute()          -> String { "##KN5;" }
    static func setSpeakerMute(_ on: Bool) -> String { "##KN5\(on ? 1 : 0);" }

    // MARK: - ##KN6  KNS access log  (admin only, set + read)

    static func readAccessLog()          -> String { "##KN6;" }
    static func setAccessLog(_ on: Bool) -> String { "##KN6\(on ? 1 : 0);" }

    // MARK: - ##KN7  Registered user remote operation  (admin only, set + read)

    static func readUserRemoteOps()          -> String { "##KN7;" }
    static func setUserRemoteOps(_ on: Bool) -> String { "##KN7\(on ? 1 : 0);" }

    // MARK: - ##KN8  User list count  (read-only, any user)

    static func readUserCount() -> String { "##KN8;" }

    // MARK: - ##KN9  Add user  (admin only, set only)
    //  Format: ##KN9 + P2(2,IDlen) + P3(2,PWlen) + P4(3,descLen)
    //               + userID + password + description + restriction(1) + enabled(1) + ;

    static func addUser(userID: String, password: String, description: String,
                        rxOnly: Bool, disabled: Bool) -> String {
        let p2 = String(format: "%02d", userID.utf8.count)
        let p3 = String(format: "%02d", password.utf8.count)
        let p4 = String(format: "%03d", description.utf8.count)
        return "##KN9\(p2)\(p3)\(p4)\(userID)\(password)\(description)\(rxOnly ? 1 : 0)\(disabled ? 1 : 0);"
    }

    // MARK: - ##KNA  Read / edit user  (admin: all; user: own entry only)
    //  Read format:  ##KNA + P1(3,number) + ;
    //  Set format:   ##KNA + P1(3) + P2(2,IDlen) + P3(2,PWlen) + P4(3,descLen)
    //                     + userID + password + description + restriction(1) + enabled(1) + ;

    static func readUser(number: Int) -> String {
        String(format: "##KNA%03d;", number)
    }

    static func editUser(number: Int, userID: String, password: String,
                         description: String, rxOnly: Bool, disabled: Bool) -> String {
        let p1 = String(format: "%03d", number)
        let p2 = String(format: "%02d", userID.utf8.count)
        let p3 = String(format: "%02d", password.utf8.count)
        let p4 = String(format: "%03d", description.utf8.count)
        return "##KNA\(p1)\(p2)\(p3)\(p4)\(userID)\(password)\(description)\(rxOnly ? 1 : 0)\(disabled ? 1 : 0);"
    }

    // MARK: - ##KNB  Delete user  (admin only, set only)

    static func deleteUser(number: Int) -> String {
        String(format: "##KNB%03d;", number)
    }

    // MARK: - ##KNC  Welcome message  (any user, set + read)
    //  P1 is always a literal space before the message text.

    static func readWelcomeMessage()             -> String { "##KNC;" }
    static func setWelcomeMessage(_ msg: String) -> String { "##KNC \(msg);" }
    static func clearWelcomeMessage()            -> String { "##KNC ;" }

    // MARK: - ##KND  Session timeout  (admin only, set + read)

    static func readSessionTimeout()                  -> String { "##KND;" }
    static func setSessionTimeout(_ t: SessionTimeout) -> String {
        String(format: "##KND%02d;", t.rawValue)
    }

    // MARK: - ##KNE  Change current user's own password  (any user)

    static func changePassword(_ newPassword: String) -> String {
        "##KNE\(newPassword);"
    }
}
