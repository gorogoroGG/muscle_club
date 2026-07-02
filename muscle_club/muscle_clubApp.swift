//
//  muscle_clubApp.swift
//  muscle_club
//
//  Created by ゴロゴロ on 2026/06/29.
//

import SwiftUI

@main
@MainActor
struct muscle_clubApp: App {
    @StateObject private var store = GymStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onOpenURL { url in
                    Task {
                        await store.handleOpenURL(url)
                    }
                }
        }
    }
}
