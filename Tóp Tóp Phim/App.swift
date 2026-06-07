//
//  App.swift
//  Tóp Tóp Phim
//
//  Created by leanh on 7/6/26.
//
 
import SwiftUI
import AVKit
import Combine
import Network
 
struct CustomVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.updatesNowPlayingInfoCenter = true
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    @Published var isConnected: Bool = true

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}

struct Movie: Codable, Identifiable {
    var id: String { slug }
    let slug: String
    let name: String
    let image: String
    let origin_name: String?
}

struct Episode: Codable, Identifiable {
    var id: String { name }
    let name: String
    let m3u8: String
}

struct Category: Codable, Identifiable {
    let id: String
    let name: String
}

struct Wrap<T: Codable>: Codable {
    let data: T
}

struct MovieListData: Codable {
    let items: [Movie]
}

struct MovieDetail: Codable {
    let name: String
    let origin_name: String
    let content: String
    let poster: String
    let year: Int
    let time: String
    let category: [Category]
    let episodes: [Episode]
    
    var cleanContent: String {
        return content
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var movies: [Movie] = []
    @Published var isLoading: Bool = false
    private let decoder = JSONDecoder()

    func loadHot() async {
        isLoading = true
        defer { isLoading = false }
        guard let url = URL(string: "https://phim.dailythuonghien.com/api/main.php?page=1") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try decoder.decode(Wrap<MovieListData>.self, from: data)
            movies = result.data.items
        } catch {
            print("Error loadHot: \(error)")
        }
    }

    func search(_ keyword: String) async {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            await loadHot()
            return
        }

        var comp = URLComponents(string: "https://phim.dailythuonghien.com/api/tim-kiem.php")
        comp?.queryItems = [.init(name: "keyword", value: text)]
        guard let url = comp?.url else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try decoder.decode(Wrap<MovieListData>.self, from: data)
            movies = result.data.items
        } catch {
            print("Error search: \(error)")
        }
    }

    func detail(slug: String) async -> MovieDetail? {
        var comp = URLComponents(string: "https://phim.dailythuonghien.com/api/xem.php")
        comp?.queryItems = [.init(name: "slug", value: slug)]
        guard let url = comp?.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let result = try decoder.decode(Wrap<MovieDetail>.self, from: data)
            return result.data
        } catch {
            print("Error detail: \(error)")
            return nil
        }
    }
}

struct ContentView: View {
    @StateObject private var store = Store()
    @StateObject private var network = NetworkMonitor()
    @State private var keyword = ""
    @State private var task: Task<Void, Never>?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ZStack {
            NavigationStack {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(store.movies) { movie in
                                NavigationLink {
                                    DetailView(slug: movie.slug, store: store)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        AsyncImage(url: URL(string: movie.image)) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(.gray.opacity(0.15))
                                                .overlay { ProgressView() }
                                        }
                                        .frame(height: 230)
                                        .frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))

                                        Text(movie.name)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                            .frame(height: 38, alignment: .topLeading)

                                        Text(movie.origin_name ?? "Đang cập nhật")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                    }
                }
                .navigationTitle("🔥 Tóp Tóp Phim")
                .searchable(text: $keyword, prompt: "Tìm tên phim...")
                .task {
                    if network.isConnected {
                        await store.loadHot()
                    }
                }
                .onChange(of: keyword) { _, value in
                    guard network.isConnected else { return }
                    task?.cancel()
                    task = Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        await store.search(value)
                    }
                }
                .onChange(of: network.isConnected) { _, isConnected in
                    if isConnected {
                        Task {
                            await store.loadHot()
                        }
                    }
                }
            }

            if store.isLoading {
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                ProgressView("Đang tải danh sách phim...")
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .shadow(radius: 10)
            }

            if !network.isConnected {
                Color(.systemBackground)
                    .edgesIgnoringSafeArea(.all)
                VStack(spacing: 16) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    Text("Mất kết nối Internet")
                        .font(.title3.bold())
                    Text("Vui lòng kiểm tra lại mạng wifi hoặc 5G. Ứng dụng sẽ tự động tải lại khi có mạng.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
    }
}

struct DetailView: View {
    let slug: String
    let store: Store

    @State private var movie: MovieDetail?
    @State private var player: AVPlayer?
    @State private var selectedEpisode: Episode?
    @State private var episodeSearchQuery = ""
    
    var filteredEpisodes: [Episode] {
        guard let movie = movie else { return [] }
        if episodeSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return movie.episodes
        }
        return movie.episodes.filter { $0.name.localizedCaseInsensitiveContains(episodeSearchQuery) }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let player = player {
                    CustomVideoPlayer(player: player)
                        .frame(height: 220)
                        .background(Color.black)
                        .cornerRadius(12)
                        .onAppear {
                            let audioSession = AVAudioSession.sharedInstance()
                            try? audioSession.setCategory(.playback, mode: .default, options: [])
                            try? audioSession.setActive(true)
                        }
                } else if let movie = movie {
                    AsyncImage(url: URL(string: movie.poster)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.1))
                    }
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .center) {
                        VStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.white.opacity(0.9))
                            Text("Chọn tập ở bên dưới để xem phim")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .shadow(radius: 3)
                        }
                    }
                }

                if let movie = movie {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(movie.name)
                            .font(.title3.bold())

                        Text(movie.origin_name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Năm: \(movie.year)")
                            Text("•")
                            Text("Thời lượng: \(movie.time)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(movie.category) { cat in
                                Text(cat.name)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.blue.opacity(0.12))
                                    .foregroundColor(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Chọn tập phim")
                                .font(.headline)
                            Spacer()
                            Text("\(movie.episodes.count) tập")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                                .font(.footnote)
                            TextField("Tìm nhanh số tập... (ví dụ: 1, 2, Full)", text: $episodeSearchQuery)
                                .font(.system(size: 14))
                                .keyboardType(.webSearch)
                            
                            if !episodeSearchQuery.isEmpty {
                                Button { episodeSearchQuery = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                        
                        if filteredEpisodes.isEmpty {
                            Text("Không tìm thấy tập nào tương ứng.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 10)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(filteredEpisodes) { episode in
                                        Button {
                                            guard let url = URL(string: episode.m3u8) else { return }
                                            
                                            player?.pause()
                                            player = nil
                                            
                                            selectedEpisode = episode
                                            player = AVPlayer(url: url)
                                            player?.play()
                                        } label: {
                                            Text(episode.name.replacingOccurrences(of: "Tập ", with: ""))
                                                .font(.system(size: 14, weight: .bold))
                                                .frame(minWidth: 44)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 10)
                                                .background(selectedEpisode?.name == episode.name ? Color.blue : Color.gray.opacity(0.15))
                                                .foregroundColor(selectedEpisode?.name == episode.name ? .white : .primary)
                                                .cornerRadius(8)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding(.top, 4)
                    
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nội dung cốt truyện")
                            .font(.headline)
                        Text(movie.cleanContent)
                            .font(.system(size: 15))
                            .lineSpacing(4)
                            .foregroundColor(.primary.opacity(0.85))
                    }

                } else {
                    HStack {
                        Spacer()
                        ProgressView("Đang tải dữ liệu phim...")
                        Spacer()
                    }
                    .padding(.top, 60)
                }
            }
            .padding()
        }
        .navigationTitle("Chi tiết phim")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            movie = await store.detail(slug: slug)
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

#Preview {
    ContentView()
}
