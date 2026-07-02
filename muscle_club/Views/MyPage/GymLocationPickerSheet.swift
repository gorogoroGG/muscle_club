import Combine
import MapKit
import SwiftUI

struct GymLocationPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: GymStore

    @StateObject private var searchModel = GymLocationSearchModel()

    @State private var gymName = ""
    @State private var radiusMeters: Double = 120
    @State private var selectedCoordinate = CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125)
    @State private var cameraPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    )

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        CardView(title: "SEARCH") {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("ジムを検索")
                                    .font(.headline)
                                    .foregroundStyle(AppPalette.textPrimary)

                                TextField("駅名・ジム名・住所で検索", text: $searchModel.query)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .appInputChrome()

                                if !searchModel.suggestions.isEmpty {
                                    VStack(spacing: 10) {
                                        ForEach(searchModel.suggestions) { suggestion in
                                            Button {
                                                Task {
                                                    await selectSuggestion(suggestion)
                                                }
                                            } label: {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(suggestion.title)
                                                        .font(.subheadline.weight(.semibold))
                                                        .foregroundStyle(AppPalette.textPrimary)
                                                    if !suggestion.subtitle.isEmpty {
                                                        Text(suggestion.subtitle)
                                                            .font(.caption)
                                                            .foregroundStyle(AppPalette.textSecondary)
                                                    }
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(12)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                        .fill(Color.white.opacity(0.05))
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }

                        CardView(title: "MAP") {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("地図を動かしてピン位置を調整")
                                    .font(.headline)
                                    .foregroundStyle(AppPalette.textPrimary)

                                ZStack {
                                    Map(position: $cameraPosition, interactionModes: .all)
                                        .frame(height: 320)
                                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                        .onMapCameraChange(frequency: .continuous) { context in
                                            selectedCoordinate = context.region.center
                                        }

                                    VStack(spacing: 0) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 34, weight: .bold))
                                            .foregroundStyle(AppPalette.danger)
                                            .shadow(color: .black.opacity(0.28), radius: 12, y: 6)

                                        Image(systemName: "triangle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(AppPalette.danger)
                                            .rotationEffect(.degrees(180))
                                            .offset(y: -8)
                                    }
                                }

                                Text("検索結果を選んだあと、地図を少し動かして細かく合わせられます。")
                                    .font(.caption)
                                    .foregroundStyle(AppPalette.textSecondary)
                            }
                        }

                        CardView(title: "DETAIL") {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("登録内容")
                                    .font(.headline)
                                    .foregroundStyle(AppPalette.textPrimary)

                                TextField("ジム名", text: $gymName)
                                    .appInputChrome()

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("到着判定の半径")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(AppPalette.textPrimary)
                                        Spacer()
                                        Text("\(Int(radiusMeters))m")
                                            .font(.subheadline)
                                            .foregroundStyle(AppPalette.textSecondary)
                                    }

                                    Slider(value: $radiusMeters, in: 80...300, step: 10)
                                        .tint(AppPalette.accentSecondary)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("選択中の座標")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppPalette.textSecondary)
                                    Text(String(format: "%.5f, %.5f", selectedCoordinate.latitude, selectedCoordinate.longitude))
                                        .font(.caption)
                                        .foregroundStyle(AppPalette.textSecondary)
                                }
                            }
                        }

                        Button("この位置で登録") {
                            store.saveGymLocation(
                                named: gymName,
                                coordinate: selectedCoordinate,
                                radiusMeters: radiusMeters
                            )
                            dismiss()
                        }
                        .buttonStyle(PrimaryActionButtonStyle(tint: AppPalette.accentSecondary))
                    }
                    .padding(20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("ジム位置を登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                configureInitialState()
            }
        }
    }

    private func configureInitialState() {
        if let gymLocation = store.gymLocation {
            gymName = gymLocation.name
            radiusMeters = gymLocation.radiusMeters
            selectedCoordinate = gymLocation.coordinate
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: gymLocation.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        }
    }

    private func selectSuggestion(_ suggestion: GymLocationSuggestion) async {
        guard let result = await searchModel.resolve(suggestion: suggestion) else { return }
        selectedCoordinate = result.coordinate
        if gymName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            gymName = result.name
        }
        cameraPosition = .region(
            MKCoordinateRegion(
                center: result.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            )
        )
        searchModel.clearSuggestions()
    }
}

private final class GymLocationSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet {
            completer.queryFragment = query
        }
    }
    @Published var suggestions: [GymLocationSuggestion] = []

    private let completer: MKLocalSearchCompleter

    override init() {
        self.completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results.prefix(6).map { result in
            GymLocationSuggestion(title: result.title, subtitle: result.subtitle)
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        suggestions = []
    }

    func clearSuggestions() {
        suggestions = []
    }

    func resolve(suggestion: GymLocationSuggestion) async -> GymLocationResolvedResult? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = suggestion.subtitle.isEmpty
            ? suggestion.title
            : "\(suggestion.title) \(suggestion.subtitle)"

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else { return nil }
            return GymLocationResolvedResult(
                name: item.name ?? suggestion.title,
                coordinate: item.placemark.coordinate
            )
        } catch {
            return nil
        }
    }
}

private struct GymLocationSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
}

private struct GymLocationResolvedResult {
    let name: String
    let coordinate: CLLocationCoordinate2D
}
