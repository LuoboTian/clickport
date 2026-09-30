// Operates only on a fresh temporary directory created by this process.
import Foundation
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("clickport-probe-" + UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
let source = root.appendingPathComponent("模板 空格%中文.json")
let data = Data("{}\n".utf8)
try data.write(to: source, options: .withoutOverwriting)
let copy = root.appendingPathComponent("新建文件.json")
try fm.copyItem(at: source, to: copy)
let copiedData = try Data(contentsOf: copy)
precondition(copiedData == data)
precondition(URL(string: source.absoluteString)?.path == source.path)
var hiddenURL = copy
var values = URLResourceValues()
values.isHidden = true
try hiddenURL.setResourceValues(values)
let hidden = try hiddenURL.resourceValues(forKeys: [.isHiddenKey]).isHidden
precondition(hidden == true)
values.isHidden = false
try hiddenURL.setResourceValues(values)
hiddenURL.removeAllCachedResourceValues()
let visible = try hiddenURL.resourceValues(forKeys: [.isHiddenKey]).isHidden
precondition(visible == false)
var preventedOverwrite = false
 do { try fm.copyItem(at: source, to: copy) } catch { preventedOverwrite = true }
precondition(preventedOverwrite)
print("PASS: URL round-trip, template byte-copy, hidden flag round-trip, existing destination preserved")
