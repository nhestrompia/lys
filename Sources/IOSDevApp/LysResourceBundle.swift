import Foundation

enum LysResourceBundle {
  static let ui: Bundle = {
    if let resources = Bundle.main.resourceURL,
      let packaged = Bundle(url: resources.appending(path: "Lys_IOSDevUI.bundle"))
    {
      return packaged
    }
    return Bundle.module
  }()
}
