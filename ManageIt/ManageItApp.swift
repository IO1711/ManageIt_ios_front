//
//  ManageItApp.swift
//  ManageIt
//
//  Created by Bilolbek Rayimov on 12/05/26.
//

import SwiftUI

@main
struct ManageItApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(appModel: appModel)
        }
    }
}
