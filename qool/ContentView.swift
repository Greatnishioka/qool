import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppRootViewModel.bootstrap()

    var body: some View {
        AppRootView(viewModel: viewModel)
    }
}
