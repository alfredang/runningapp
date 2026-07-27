import SwiftUI
import MapKit

/// Manage favourite destinations: add the current spot as "Home", search for a
/// place by name, pick one to route to, or delete.
struct DestinationsView: View {
    @EnvironmentObject private var viewModel: RunViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.destinations.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Destinations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddDestinationView().environmentObject(viewModel)
            }
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(viewModel.destinations) { destination in
                    row(for: destination)
                }
            }
            .padding(20)
        }
    }

    private func row(for destination: Destination) -> some View {
        let isSelected = viewModel.selectedDestination?.id == destination.id

        return Button {
            if isSelected {
                viewModel.clearDestination()
            } else {
                viewModel.selectDestination(destination)
                dismiss()
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: destination.symbolName)
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : Theme.info)
                    .frame(width: 44, height: 44)
                    .background((isSelected ? Theme.accent : Theme.info).opacity(0.12),
                                in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(destination.name)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    if !destination.address.isEmpty {
                        Text(destination.address)
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                }
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deleteDestination(destination.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 52))
                .foregroundStyle(Theme.inkSecondary)
            Text("No destinations yet")
                .font(.title3.bold())
                .foregroundStyle(Theme.ink)
            Text("Save places you run to — like Home or the park — and RunTrack GPS will show you the shortest route there.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)

            Button {
                showAddSheet = true
            } label: {
                Label("Add Destination", systemImage: "plus")
                    .font(.headline)
                    .frame(minHeight: 50)
                    .padding(.horizontal, 24)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.top, 6)
        }
        .padding(40)
    }
}

// MARK: - Add destination

/// Creates a favourite either from the runner's current GPS position or from a
/// place-name search (MapKit local search).
struct AddDestinationView: View {
    @EnvironmentObject private var viewModel: RunViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = "Home"
    @State private var symbolName = "house.fill"
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    nameField
                    symbolPicker
                    currentLocationButton
                    searchSection
                }
                .padding(20)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Add Destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            TextField("Home", text: $name)
                .font(.title3)
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var symbolPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Icon")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Destination.symbolChoices, id: \.self) { symbol in
                        Button {
                            symbolName = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .foregroundStyle(symbolName == symbol ? .white : Theme.ink)
                                .frame(width: 50, height: 50)
                                .background(symbolName == symbol ? Theme.accent : Theme.card,
                                            in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var currentLocationButton: some View {
        Button {
            if viewModel.saveCurrentLocationAsDestination(
                name: trimmedName.isEmpty ? "Home" : trimmedName,
                symbolName: symbolName) {
                dismiss()
            }
        } label: {
            Label("Use My Current Location", systemImage: "location.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Or search for a place")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.inkSecondary)
                TextField("Address or place name", text: $searchText)
                    .submitLabel(.search)
                    .onSubmit(runSearch)
                if isSearching { ProgressView().controlSize(.small) }
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))

            ForEach(searchResults, id: \.self) { item in
                Button {
                    select(item)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name ?? "Unknown place")
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.ink)
                        Text(Self.address(for: item))
                            .font(.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle(padding: 14, cornerRadius: 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func runSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        // Bias results to where the runner actually is.
        if let current = viewModel.location.currentLocation?.coordinate {
            request.region = MKCoordinateRegion(center: current,
                                                latitudinalMeters: 30_000,
                                                longitudinalMeters: 30_000)
        }

        Task {
            let response = try? await MKLocalSearch(request: request).start()
            await MainActor.run {
                searchResults = Array((response?.mapItems ?? []).prefix(8))
                isSearching = false
            }
        }
    }

    private func select(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        let resolvedName = trimmedName.isEmpty ? (item.name ?? "Destination") : trimmedName
        viewModel.saveDestination(
            Destination(name: resolvedName,
                        symbolName: symbolName,
                        coordinate: Coordinate(coordinate),
                        address: Self.address(for: item)))
        dismiss()
    }

    /// A one-line postal address from a map item's placemark.
    private static func address(for item: MKMapItem) -> String {
        let mark = item.placemark
        return [mark.subThoroughfare, mark.thoroughfare, mark.locality, mark.postalCode]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
