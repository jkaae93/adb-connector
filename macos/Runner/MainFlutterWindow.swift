// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Cocoa
import FlutterMacOS
import desktop_multi_window
import ObjectiveC

private var logWindowDelegateKey: UInt8 = 0

private class LogWindowDelegate: NSObject, NSWindowDelegate {
  private let channel: FlutterMethodChannel
  private var closing = false
  private var finished = false

  init(controller: FlutterViewController) {
    channel = FlutterMethodChannel(
      name: "adb_connector/log_window",
      binaryMessenger: controller.engine.binaryMessenger
    )
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard !closing else { return false }
    closing = true
    let finish = { [weak self, weak sender] in
      guard let self = self, let window = sender, !self.finished else { return }
      self.finished = true
      window.delegate = nil
      window.close()
    }
    channel.invokeMethod("windowClosing", arguments: nil) { _ in
      DispatchQueue.main.async(execute: finish)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: finish)
    return false
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = NSRect(
      x: self.frame.origin.x,
      y: self.frame.origin.y,
      width: 1120,
      height: 760
    )
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 600, height: 400)
    self.title = "ADB Connector"

    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      guard let window = controller.view.window else { return }
      window.title = "기기 로그"
      window.minSize = NSSize(width: 600, height: 400)
      window.center()
      let delegate = LogWindowDelegate(controller: controller)
      objc_setAssociatedObject(window, &logWindowDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      window.delegate = delegate
    }

    super.awakeFromNib()
  }
}
