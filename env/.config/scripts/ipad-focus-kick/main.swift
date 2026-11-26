// Runs after every Option+I (Quick Connect toggle). Records which side now owns
// the keyboard in the Karabiner variable `uc_keyboard_remote`, so the Karabiner
// Option+I rule knows whether the next press heads to the iPad. Universal Control
// does not forward CGEvents posted on the Mac, so the Cmd+Space/Esc that hands
// keyboard focus back to the iPad app is emitted by Karabiner's virtual keyboard.
import Darwin
import Foundation
import notify

let logURL = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/ipad-focus-kick.log")
func log(_ message: String) {
    let line = "\(Date()) \(message)\n"
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile(); handle.write(line.data(using: .utf8)!); try? handle.close()
    } else { try? line.write(to: logURL, atomically: true, encoding: .utf8) }
}

var token: Int32 = -1
guard notify_register_check("user.uid.\(getuid()).com.apple.universalcontrol.inputstate", &token) == NOTIFY_STATUS_OK
else { exit(1) }
func keyboardIsRemote() -> Bool {
    var state: UInt64 = 0
    return notify_get_state(token, &state) == NOTIFY_STATUS_OK && state & 1 != 0
}

// Returning to the Mac, macOS reactivates some window of its own choosing once
// Universal Control gives up the keyboard. Remember the yabai window that had
// focus before going to the iPad (`--record`, run before the toggle) and
// refocus it on the way back.
let savedWindow = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches/ipad-focus-kick.window")
let yabai = "/opt/homebrew/bin/yabai"
func run(_ path: String, _ arguments: [String]) -> (Int32, Data) {
    let task = Process(), pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arguments
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    guard (try? task.run()) != nil else { return (-1, Data()) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return (task.terminationStatus, data)
}

if CommandLine.arguments.contains("--record") {
    // Only when leaving the Mac; pressing Option+I on the iPad must keep the saved window.
    guard !keyboardIsRemote() else { exit(0) }
    let (status, data) = run(yabai, ["-m", "query", "--windows", "--window"])
    if status == 0, let window = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let id = window["id"] as? Int {
        try? String(id).write(to: savedWindow, atomically: true, encoding: .utf8)
        log("recorded window \(id) \(window["app"] ?? "")")
    }
    exit(0)
}

// Quick Connect has normally switched ownership by the time this runs; allow a
// short settle before reading it.
usleep(300_000)
let remote = keyboardIsRemote()

let task = Process()
task.executableURL = URL(fileURLWithPath: "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli")
task.arguments = ["--set-variables", "{\"uc_keyboard_remote\":\(remote ? 1 : 0)}"]
try? task.run()
task.waitUntilExit()
log("remote=\(remote) karabiner=\(task.terminationStatus)")

if !remote, let id = try? String(contentsOf: savedWindow, encoding: .utf8) {
    try? FileManager.default.removeItem(at: savedWindow)
    // macOS may still be reactivating its own choice; focus after it settles.
    usleep(150_000)
    let (status, _) = run(yabai, ["-m", "window", "--focus", id.trimmingCharacters(in: .whitespacesAndNewlines)])
    log("refocused window \(id) status=\(status)")
}
