import SwiftUI
import Photos
import CoreLocation
import AVKit
import MetalKit

struct Constants {
    static let Success: Color = Color(red: 0, green: 0.81, blue: 0.18).opacity(0.4)
    static let Warning: Color = Color(red: 1, green: 0.23, blue: 0.29).opacity(0.4)
    static let TransparentSuccess: Color = Color(red: 0, green: 0.81, blue: 0.18).opacity(0.4)
    static let TransparentWarning: Color = Color(red: 1, green: 0.23, blue: 0.29).opacity(0.4)
}

private let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

private enum SessionKeys {
    static let seenIdentifiers  = "seenIdentifiers"
    static let savedDate        = "savedDate"
}

struct ContentView: View {
    @State private var datesToReview: [(month: Int, day: Int)] = []
    @State private var dateIndex: Int = 0
    @State private var assets: [PHAsset] = []
    @State private var photoIndex: Int = 0
    @State private var seenIdentifiers: Set<String> = []
    @State private var failedIdentifiers: Set<String> = []
    @State private var pendingDeletion: [PHAsset] = []
    @State private var currentImage: UIImage? = nil
    @State private var currentVideoURL: URL? = nil
    @State private var currentMediaType: PHAssetMediaType = .image
    @State private var dragOffset: CGSize = .zero
    @State private var isLoading: Bool = false
    @State private var isDeleting: Bool = false
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var displayedDateLabel: String = ""
    @State private var yearTag: String? = nil
    @State private var locationTag: String? = nil
    @State private var viewHistory: [(asset: PHAsset, wasMarkedForDeletion: Bool)] = []
    @State private var lastPromptedCount: Int = 0
    @State private var showDeletionPrompt: Bool = false
    @State private var toastMessage: String = ""
    @State private var toastColor: Color = .white
    @State private var showToast: Bool = false
    @State private var showDatePicker: Bool = false
    @State private var selectedDate: Date = Date()
    @State private var isLightBackground: Bool = false
    @State private var isZoomed: Bool = false
    @State private var currentImageRequestID: PHImageRequestID?
    @State private var currentGeocoderTask: CLGeocoder?

    private let deletionPromptThreshold = 15
    private let maxHistorySize = 50  // Максимум 50 шагов назад
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    private var currentAsset: PHAsset? {
        guard photoIndex < assets.count else { return nil }
        return assets[photoIndex]
    }
    private var canGoBack: Bool { !viewHistory.isEmpty }

    var body: some View {
        if isPreview {
            previewPlaceholder
        } else {
            ZStack {
                Color.black.ignoresSafeArea()
                mainContent
            }
            .onAppear { requestPhotoAccess() }
            .sheet(isPresented: $showDeletionPrompt) { deletionPromptSheet }
            .sheet(isPresented: $showDatePicker) { datePickerSheet }
        }
    }

    private var previewPlaceholder: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.clock")
                    .imageScale(.large)
                    .foregroundColor(.white.opacity(0.4))
                Text("Preview Mode")
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private var mainContent: some View {
        Group {
            if authorizationStatus == .denied || authorizationStatus == .restricted {
                accessDeniedView
            } else if isLoading && assets.isEmpty {
                loadingView(text: "Загружаем фото…")
            } else if currentAsset == nil && dateIndex >= datesToReview.count {
                completionView
            } else if currentAsset != nil {
                cardView
            } else {
                loadingView(text: "Следующая дата…")
            }
        }
    }

    private func loadingView(text: String) -> some View {
        VStack(spacing: 12) {
            ProgressView().tint(.white)
            Text(text).foregroundColor(.white.opacity(0.6))
        }
    }

    private var cardView: some View {
        GeometryReader { geometry in
            ZStack {
                // Слой с фото и оверлеями - может двигаться и вращаться
                ZStack(alignment: .center) {
                    fullscreenPhoto
                        .clipShape(RoundedRectangle(cornerRadius: screenCornerRadius(for: geometry.size)))
                    bottomGradient
                    if dragOffset.width < -30 { deleteOverlay }
                    if dragOffset.width > 30  { keepOverlay }
                    locationName
                    
                    // Теги при свайпе
                    if dragOffset.width < -30 {
                        deleteSwipeTag
                    }
                    if dragOffset.width > 30 {
                        keepSwipeTag
                    }
                }
                .offset(dragOffset)
                .rotationEffect(.degrees(Double(dragOffset.width) / 20))
                .animation(.interactiveSpring(), value: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { dragOffset = $0.translation }
                        .onEnded   { handleSwipeEnd(translation: $0.translation) }
                )
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isZoomed.toggle()
                    }
                }

                // Слой UI - всегда поверх, не двигается
                VStack {
                    dateHeader
                    Spacer()
                    actionButtons
                        .padding(.bottom, 16)
                }
                .allowsHitTesting(true)

                toastOverlay
            }
        }
    }
    
    private func screenCornerRadius(for size: CGSize) -> CGFloat {
        // Для iPhone 15/16 Pro и подобных моделей с экраном около 6.1-6.7"
        // используем радиус 55pt
        let screenHeight = size.height
        if screenHeight >= 800 { // Современные iPhone
            return 55
        } else if screenHeight >= 667 { // Старые iPhone
            return 40
        } else { // Очень маленькие экраны
            return 30
        }
    }

    private var fullscreenPhoto: some View {
        GeometryReader { geometry in
            Group {
                if currentMediaType == .video, let url = currentVideoURL {
                    VideoPlayerView(url: url, isZoomed: isZoomed)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else if currentMediaType == .video && currentVideoURL == nil {
                    Color.black
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay(DotsLoaderView())
                } else if let img = currentImage {
                    ZStack {
                        Color.black
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: isZoomed ? .fit : .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    }
                } else {
                    Color.black
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay(DotsLoaderView())
                }
            }
        }
        .ignoresSafeArea()
    }

    private var bottomGradient: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(isZoomed ? 0 : 0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: min(300, geometry.size.height * 0.4))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isZoomed)
            }
        }
        .ignoresSafeArea()
    }

    private var locationName: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                HStack {
                    if let loc = locationTag {
                        Text(loc)
                            .font(Font.system(size: 48, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.bottom, 160)
            }
        }
    }

    private var deleteOverlay: some View {
        DeleteOverlayView(opacity: Double(min(abs(dragOffset.width) / 100.0, 1.0)))
    }

    private var keepOverlay: some View {
        KeepOverlayView(opacity: Double(min(abs(dragOffset.width) / 100.0, 1.0)))
    }
    
    // Тег "Удалить" при свайпе влево
    private var deleteSwipeTag: some View {
        HStack {
            Spacer()
            Text("Удалить")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .padding(16)
                .background(
                    ZStack {
                        // Base blur effect
                        Rectangle()
                            .fill(.ultraThinMaterial)
                        
                        // Additional darkening
                        Color.black.opacity(isLightBackground ? 0.5 : 0.3)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 8)
                .padding(.trailing, 16)
        }
    }
    
    // Тег "Оставить" при свайпе вправо
    private var keepSwipeTag: some View {
        HStack {
            Text("Оставить")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .padding(16)
                .background(
                    ZStack {
                        // Base blur effect
                        Rectangle()
                            .fill(.ultraThinMaterial)
                        
                        // Additional darkening
                        Color.black.opacity(isLightBackground ? 0.5 : 0.3)
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 8)
                .padding(.leading, 16)
            Spacer()
        }
    }

    private var dateHeader: some View {
        Button {
            if dateIndex < datesToReview.count {
                let pair = datesToReview[dateIndex]
                var comps = DateComponents()
                comps.year  = Calendar.current.component(.year, from: Date())
                comps.month = pair.month
                comps.day   = pair.day
                selectedDate = Calendar.current.date(from: comps) ?? Date()
            }
            showDatePicker = true
        } label: {
            VStack(spacing: 4) {
                Text("В ЭТОТ ДЕНЬ")
                    .font(Font.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(displayedDateLabel)
                    .font(Font.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(16)
            .background(
                ZStack {
                    // Base blur effect
                    Rectangle()
                        .fill(.ultraThinMaterial)
                    
                    // Additional darkening
                    Color.black.opacity(isLightBackground ? 0.5 : 0.3)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .padding(.top, 10)
    }

    private var datePickerSheet: some View {
        NavigationView {
            VStack {
                DatePicker(
                    "",
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .onChange(of: selectedDate) { newDate in
                    jumpToDate(newDate)
                    showDatePicker = false
                }
            }
            .navigationTitle("Выберите дату")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { showDatePicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func jumpToDate(_ date: Date) {
        let cal = Calendar.current
        let m = cal.component(.month, from: date)
        let d = cal.component(.day,   from: date)
        if let idx = datesToReview.firstIndex(where: { $0.month == m && $0.day == d }) {
            dateIndex  = idx
            photoIndex = 0
            assets     = []
            currentImage    = nil
            currentVideoURL = nil
            loadCurrentDate()
        } else {
            showToastMessage("Нет фото за эту дату", color: Color(white: 0.3))
        }
    }

    private var toastOverlay: some View {
        Group {
            if showToast {
                Text(toastMessage)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(toastColor.opacity(0.85))
                    .clipShape(Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 12)
            }
        }
    }

    // MARK: - Action Buttons
    // Размер иконки: 32x32
    // Зона нажатия: 56x56
    // Внутренние отступы панели: 16px
    // Внешние отступы от краев: 16px
    // Максимальная ширина панели: 460px
    // Распределение кнопок: auto (равномерно)
    private var actionButtons: some View {
        HStack(spacing: 0) {
            deleteButton
            Spacer()
            trashCounterButton
            Spacer()
            undoButton
            Spacer()
            keepButton
        }
        .padding(16)
        .background(
            ZStack {
                // Base blur effect
                Rectangle()
                    .fill(.ultraThinMaterial)
                
                // Additional darkening
                Color.black.opacity(isLightBackground ? 0.5 : 0.3)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    // deleteButton: иконка 32x32 (42x42 при свайпе), видимая зона 56x56, невидимая зона нажатия 64x64
    private var deleteButton: some View {
        Button { animateCardOff(toLeft: true) { markForDeletion() } } label: {
            let isActive = dragOffset.width < -30
            let iconSize: CGFloat = isActive ? 42 : 32
            
            Image("Delete Solid")
                .resizable()
                .renderingMode(.template)
                .foregroundColor(isActive
                    ? Color(red: 1, green: 0.231, blue: 0.188)
                    : Color(red: 0.83, green: 0.83, blue: 0.83))
                .frame(width: iconSize, height: iconSize)
                .shadow(
                    color: isActive ? Color.black.opacity(0.35) : .clear,
                    radius: 16,
                    x: 0,
                    y: 6
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
        }
    }

    // keepButton: иконка 32x32 (42x42 при свайпе), видимая зона 56x56, невидимая зона нажатия 64x64
    private var keepButton: some View {
        Button { animateCardOff(toLeft: false) { keepPhoto() } } label: {
            let isActive = dragOffset.width > 30
            let iconSize: CGFloat = isActive ? 42 : 32
            
            Image("Heart Solid")
                .resizable()
                .renderingMode(.template)
                .foregroundColor(isActive
                    ? Color(red: 0.196, green: 0.843, blue: 0.294)
                    : Color(red: 0.83, green: 0.83, blue: 0.83))
                .frame(width: iconSize, height: iconSize)
                .shadow(
                    color: isActive ? Color.black.opacity(0.35) : .clear,
                    radius: 16,
                    x: 0,
                    y: 6
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
        }
    }

    private var trashCounterButton: some View {
        Button { showDeletionPrompt = true } label: {
            Text("\(pendingDeletion.count)")
                .font(Font.system(size: 28, weight: .bold))
                .foregroundColor(pendingDeletion.isEmpty 
                    ? Color(red: 0.83, green: 0.83, blue: 0.83).opacity(0.5)
                    : Color(red: 0.83, green: 0.83, blue: 0.83))
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
        }
        .disabled(pendingDeletion.isEmpty)
    }

    private var undoButton: some View {
        Button(action: undoLastAction) {
            Image("Undo Solid")
                .resizable()
                .renderingMode(.template)
                .foregroundColor(canGoBack
                    ? Color(red: 0.83, green: 0.83, blue: 0.83)
                    : Color(red: 0.83, green: 0.83, blue: 0.83).opacity(0.35))
                .frame(width: 32, height: 32)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
                .frame(width: 64, height: 64)
                .contentShape(Rectangle())
        }
        .disabled(!canGoBack)
    }

    private var deletionPromptSheet: some View {
        VStack(spacing: 24) {
            Image(systemName: "trash.circle.fill")
                .resizable()
                .frame(width: 48, height: 48)
                .foregroundColor(.red)
            Text("Удалить отмеченные фото?")
                .multilineTextAlignment(.center)
            Text("Вы отметили \(pendingDeletion.count) фото. Удалим сейчас?")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            VStack(spacing: 12) {
                Button {
                    showDeletionPrompt = false
                    deleteAllPending()
                } label: {
                    HStack {
                        Spacer()
                        Text(isDeleting ? "Удаление…" : "Удалить \(pendingDeletion.count) фото")
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isDeleting)
                Button("Позже") {
                    lastPromptedCount = pendingDeletion.count
                    showDeletionPrompt = false
                }
                .foregroundColor(.secondary)
                .padding(.top, 20)
            }
            .padding(.horizontal)
        }
        .padding(.top, 32)
        .padding(.bottom, 24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var completionView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "checkmark.seal.fill")
                    .imageScale(.large)
                    .foregroundColor(.green)
                Text("Все фото просмотрены")
                    .foregroundColor(.white)
                Text("Просмотрено дат: \(datesToReview.count)")
                    .foregroundColor(.white.opacity(0.5))
                if !pendingDeletion.isEmpty {
                    Text("На удаление: \(pendingDeletion.count) фото")
                        .foregroundColor(.white.opacity(0.6))
                    Button(action: deleteAllPending) {
                        Text(isDeleting ? "Удаление…" : "Удалить \(pendingDeletion.count) фото")
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(isDeleting ? Color.gray : Color.red)
                            .clipShape(Capsule())
                    }
                    .disabled(isDeleting)
                }
                Button(action: restartSorting) {
                    Text("Начать сначала")
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding()
        }
    }

    private var accessDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.slash")
                .imageScale(.large)
                .foregroundColor(.white.opacity(0.4))
            Text("Нет доступа к фотографиям")
                .foregroundColor(.white)
            Text("Разрешите доступ в Настройках → Конфиденциальность → Фото")
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Открыть настройки") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func showToastMessage(_ message: String, color: Color) {
        toastMessage = message
        toastColor   = color
        withAnimation(.spring()) { showToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut) { showToast = false }
        }
    }

    private func requestPhotoAccess() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            loadSession()
            buildDateList()
        } else if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    authorizationStatus = newStatus
                    if newStatus == .authorized || newStatus == .limited {
                        loadSession()
                        buildDateList()
                    }
                }
            }
        } else {
            DispatchQueue.main.async { authorizationStatus = status }
        }
    }

    private func loadSession() {
        let today = todayString()
        let saved = UserDefaults.standard.string(forKey: SessionKeys.savedDate) ?? ""
        if saved == today {
            let arr = UserDefaults.standard.stringArray(forKey: SessionKeys.seenIdentifiers) ?? []
            seenIdentifiers = Set(arr)
        } else {
            seenIdentifiers = []
            saveSession()
        }
    }

    private func saveSession() {
        UserDefaults.standard.set(Array(seenIdentifiers), forKey: SessionKeys.seenIdentifiers)
        UserDefaults.standard.set(todayString(), forKey: SessionKeys.savedDate)
    }

    private func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func buildDateList() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let calendar  = Calendar.current
            let today     = Date()
            let fetchOptions = PHFetchOptions()
            let allAssets = PHAsset.fetchAssets(with: fetchOptions)
            var uniqueDays = Set<String>()
            allAssets.enumerateObjects { asset, _, _ in
                guard asset.mediaType == .image || asset.mediaType == .video else { return }
                guard let date = asset.creationDate else { return }
                let c = calendar.dateComponents([.month, .day], from: date)
                if let m = c.month, let d = c.day {
                    uniqueDays.insert(String(format: "%02d-%02d", m, d))
                }
            }
            var ordered: [(month: Int, day: Int)] = []
            for offset in 0..<366 {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                let c = calendar.dateComponents([.month, .day], from: day)
                guard let m = c.month, let d = c.day else { continue }
                let key = String(format: "%02d-%02d", m, d)
                guard uniqueDays.contains(key) else { continue }
                if !ordered.contains(where: { $0.month == m && $0.day == d }) {
                    ordered.append((month: m, day: d))
                }
            }
            DispatchQueue.main.async {
                datesToReview = ordered
                dateIndex     = 0
                isLoading     = false
                loadCurrentDate()
            }
        }
    }

    private func loadCurrentDate() {
        guard dateIndex < datesToReview.count else {
            assets = []; photoIndex = 0; currentImage = nil
            return
        }
        let pair     = datesToReview[dateIndex]
        let calendar = Calendar.current
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var fetched = fetchAssets(month: pair.month, day: pair.day, calendar: calendar)
            let seen = seenIdentifiers
            fetched = fetched.filter { !seen.contains($0.localIdentifier) }
            var comps   = DateComponents()
            comps.year  = calendar.component(.year, from: Date())
            comps.month = pair.month
            comps.day   = pair.day
            let refDate   = calendar.date(from: comps) ?? Date()
            let formatter = DateFormatter()
            formatter.locale     = Locale(identifier: "ru_RU")
            formatter.dateFormat = "d MMM yyyy"
            var label = formatter.string(from: refDate)
            
            // Убираем точку после сокращения месяца, если она есть
            label = label.replacingOccurrences(of: ".", with: "")
            
            // Обрезаем название месяца до 3 букв
            let components = label.split(separator: " ")
            if components.count == 3 {
                let day = components[0]
                let month = components[1]
                let year = components[2]
                let shortMonth = String(month.prefix(3))
                label = "\(day) \(shortMonth) \(year)"
            }
            
            DispatchQueue.main.async {
                isLoading = false
                if fetched.isEmpty {
                    dateIndex += 1
                    loadCurrentDate()
                } else {
                    assets             = fetched
                    photoIndex         = 0
                    currentImage       = nil
                    currentVideoURL    = nil
                    displayedDateLabel = label
                    loadCurrentImage()
                }
            }
        }
    }

    private func fetchAssets(month: Int, day: Int, calendar: Calendar) -> [PHAsset] {
        let currentYear = calendar.component(.year, from: Date())
        var predicates: [NSPredicate] = []
        for year in 1970...currentYear {
            var c = DateComponents()
            c.year = year; c.month = month; c.day = day
            c.hour = 0; c.minute = 0; c.second = 0
            guard let start = calendar.date(from: c),
                  let end   = calendar.date(byAdding: .day, value: 1, to: start)
            else { continue }
            predicates.append(NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@",
                start as NSDate, end as NSDate))
        }
        guard !predicates.isEmpty else { return [] }
        let opts = PHFetchOptions()
        let mediaFilter = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                      PHAssetMediaType.image.rawValue,
                                      PHAssetMediaType.video.rawValue)
        opts.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSCompoundPredicate(orPredicateWithSubpredicates: predicates),
            mediaFilter
        ])
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var result: [PHAsset] = []
        PHAsset.fetchAssets(with: opts).enumerateObjects { a, _, _ in result.append(a) }
        return result
    }

    private func loadCurrentImage() {
        guard photoIndex < assets.count else { return }
        
        // Отменяем предыдущие запросы
        if let requestID = currentImageRequestID {
            PHImageManager.default().cancelImageRequest(requestID)
            currentImageRequestID = nil
        }
        
        currentGeocoderTask?.cancelGeocode()
        currentGeocoderTask = nil
        
        let asset = assets[photoIndex]
        yearTag = nil; locationTag = nil
        currentImage = nil; currentVideoURL = nil
        currentMediaType = asset.mediaType

        if failedIdentifiers.contains(asset.localIdentifier) {
            seenIdentifiers.insert(asset.localIdentifier)
            advanceToNext(); return
        }
        if let date = asset.creationDate {
            yearTag = "\(Calendar.current.component(.year, from: date))"
        }
        if let loc = asset.location { 
            let geocoder = CLGeocoder()
            currentGeocoderTask = geocoder
            reverseGeocode(location: loc, geocoder: geocoder)
        }

        if asset.mediaType == .video {
            let videoOpts = PHVideoRequestOptions()
            videoOpts.deliveryMode = .automatic
            videoOpts.isNetworkAccessAllowed = true
            PHImageManager.default().requestAVAsset(forVideo: asset, options: videoOpts) { avAsset, _, info in
                let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
                guard !isCancelled else { return }
                if let urlAsset = avAsset as? AVURLAsset {
                    DispatchQueue.main.async { 
                        currentVideoURL = urlAsset.url 
                    }
                } else if let _ = info?[PHImageErrorKey] {
                    let id = asset.localIdentifier
                    DispatchQueue.main.async {
                        guard !failedIdentifiers.contains(id) else { return }
                        failedIdentifiers.insert(id)
                        seenIdentifiers.insert(id)
                        advanceToNext()
                    }
                }
            }
        } else {
            let opts = PHImageRequestOptions()
            opts.deliveryMode            = .opportunistic
            opts.isNetworkAccessAllowed  = true
            opts.allowSecondaryDegradedImage = true
            
            // Используем размер экрана для оптимизации памяти
            let screenScale = UIScreen.main.scale
            let screenSize = UIScreen.main.bounds.size
            let targetSize = CGSize(
                width: screenSize.width * screenScale,
                height: screenSize.height * screenScale
            )
            
            currentImageRequestID = PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: opts
            ) { image, info in
                let isDegraded  = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                let isCancelled = (info?[PHImageCancelledKey]         as? Bool) ?? false
                let hasError    =  info?[PHImageErrorKey] != nil
                guard !isCancelled else { return }
                
                if let image = image {
                    DispatchQueue.main.async {
                        currentImage = image
                        analyzeImageBrightness(image)
                        
                        // Очищаем requestID когда получили финальное изображение
                        if !isDegraded {
                            currentImageRequestID = nil
                        }
                    }
                } else if hasError && !isDegraded {
                    let id = asset.localIdentifier
                    DispatchQueue.main.async {
                        guard !failedIdentifiers.contains(id) else { return }
                        failedIdentifiers.insert(id)
                        seenIdentifiers.insert(id)
                        currentImageRequestID = nil
                        advanceToNext()
                    }
                }
            }
        }
    }

    private func reverseGeocode(location: CLLocation, geocoder: CLGeocoder) {
        Task {
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                guard let placemark = placemarks.first else { return }
                let name = placemark.locality 
                    ?? placemark.subLocality 
                    ?? placemark.administrativeArea 
                    ?? placemark.country
                await MainActor.run {
                    locationTag = name
                }
            } catch {
                // Silently fail - location is optional feature
                print("Geocoding error: \(error.localizedDescription)")
            }
        }
    }

    private func analyzeImageBrightness(_ image: UIImage) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let cgImage = image.cgImage else { return }
            let width = 100; let height = 100
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bytesPerPixel = 4
            let bytesPerRow = bytesPerPixel * width
            var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
            guard let context = CGContext(
                data: &pixelData, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            var totalBrightness: CGFloat = 0
            for i in 0..<(width * height) {
                let o = i * bytesPerPixel
                let r = CGFloat(pixelData[o]) / 255.0
                let g = CGFloat(pixelData[o+1]) / 255.0
                let b = CGFloat(pixelData[o+2]) / 255.0
                totalBrightness += (0.299*r + 0.587*g + 0.114*b)
            }
            let avg = totalBrightness / CGFloat(width * height)
            DispatchQueue.main.async {
                isLightBackground = avg > 0.6
            }
        }
    }

    private func handleSwipeEnd(translation: CGSize) {
        if      translation.width < -100 { animateCardOff(toLeft: true)  { markForDeletion() } }
        else if translation.width >  100 { animateCardOff(toLeft: false) { keepPhoto() } }
        else                             { withAnimation(.spring()) { dragOffset = .zero } }
    }

    private func animateCardOff(toLeft: Bool, completion: @escaping () -> Void) {
        feedbackGenerator.prepare()
        feedbackGenerator.impactOccurred()
        withAnimation(.easeInOut(duration: 0.3)) {
            dragOffset = CGSize(width: toLeft ? -600 : 600, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dragOffset = .zero
            completion()
        }
    }

    private func keepPhoto() {
        guard let asset = currentAsset else { return }
        
        // Добавляем в историю
        viewHistory.append((asset: asset, wasMarkedForDeletion: false))
        
        // Ограничиваем размер истории для экономии памяти
        if viewHistory.count > maxHistorySize {
            viewHistory.removeFirst()
        }
        
        seenIdentifiers.insert(asset.localIdentifier)
        saveSession()
        advanceToNext()
    }

    private func markForDeletion() {
        guard let asset = currentAsset else { return }
        
        // Добавляем в историю
        viewHistory.append((asset: asset, wasMarkedForDeletion: true))
        
        // Ограничиваем размер истории для экономии памяти
        if viewHistory.count > maxHistorySize {
            viewHistory.removeFirst()
        }
        
        seenIdentifiers.insert(asset.localIdentifier)
        pendingDeletion.append(asset)
        saveSession()
        advanceToNext()
        checkDeletionPrompt()
    }

    private func undoLastAction() {
        // Проверяем границы истории
        guard !viewHistory.isEmpty else { return }
        
        // Извлекаем последнее действие из истории
        let action = viewHistory.removeLast()
        
        // Удаляем из просмотренных
        seenIdentifiers.remove(action.asset.localIdentifier)
        
        // Если было отмечено на удаление - убираем из корзины
        if action.wasMarkedForDeletion {
            pendingDeletion.removeAll { $0.localIdentifier == action.asset.localIdentifier }
        }
        
        saveSession()
        
        // Возвращаемся к предыдущему фото
        // Проверяем, есть ли оно в текущем массиве assets
        if photoIndex > 0 {
            // Если можем просто вернуться на шаг назад в текущем массиве
            photoIndex -= 1
        } else {
            // Если мы в начале массива - вставляем asset в начало
            assets.insert(action.asset, at: 0)
            photoIndex = 0
        }
        
        // Очищаем текущие данные и загружаем предыдущее фото
        currentImage = nil
        currentVideoURL = nil
        isZoomed = false
        
        // Загружаем предыдущее изображение с плавной анимацией
        withAnimation(.easeInOut(duration: 0.2)) {
            loadCurrentImage()
        }
    }

    private func checkDeletionPrompt() {
        let count = pendingDeletion.count
        if count - lastPromptedCount >= deletionPromptThreshold {
            lastPromptedCount = count
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showDeletionPrompt = true }
        }
    }

    private func advanceToNext() {
        currentImage = nil; currentVideoURL = nil; yearTag = nil; locationTag = nil
        isLightBackground = false; isZoomed = false
        let next = photoIndex + 1
        if next < assets.count { photoIndex = next; loadCurrentImage() }
        else { dateIndex += 1; photoIndex = 0; assets = []; loadCurrentDate() }
    }

    private func deleteAllPending() {
        guard !pendingDeletion.isEmpty else { return }
        isDeleting = true
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(pendingDeletion as NSArray)
        }) { success, _ in
            DispatchQueue.main.async {
                isDeleting = false
                if success { pendingDeletion = []; lastPromptedCount = 0 }
            }
        }
    }

    private func restartSorting() {
        pendingDeletion = []
        seenIdentifiers = []
        failedIdentifiers = []
        viewHistory = []  // Очищаем историю
        lastPromptedCount = 0
        saveSession()
        buildDateList()
    }
}

struct VideoPlayerView: UIViewControllerRepresentable {
    let url: URL
    let isZoomed: Bool
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let c = AVPlayerViewController()
        c.player = AVPlayer(url: url)
        c.showsPlaybackControls = true
        c.videoGravity = isZoomed ? .resizeAspect : .resizeAspectFill
        c.player?.play()
        return c
    }
    
    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        // Обновляем videoGravity при изменении isZoomed
        vc.videoGravity = isZoomed ? .resizeAspect : .resizeAspectFill
        
        if let cur = vc.player?.currentItem,
           let a = cur.asset as? AVURLAsset, a.url != url {
            vc.player?.replaceCurrentItem(with: AVPlayerItem(url: url))
            vc.player?.play()
        }
    }
}

struct DeleteOverlayView: View {
    let opacity: Double
    
    var body: some View {
        GeometryReader { geometry in
            LinearGradient(
                stops: [
                    Gradient.Stop(color: .black.opacity(0), location: 0.00),
                    Gradient.Stop(color: Constants.Warning, location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(opacity)
        }
    }
}

struct KeepOverlayView: View {
    let opacity: Double
    
    var body: some View {
        GeometryReader { geometry in
            LinearGradient(
                stops: [
                    Gradient.Stop(color: .black.opacity(0), location: 0.00),
                    Gradient.Stop(color: Constants.Success, location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(opacity)
        }
    }
}

struct PhotoTagView: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}

struct DotsLoaderView: View {
    @State private var phase: Int = 0
    @State private var timer: Timer?
    
    private let allDots: [(Int, Int)] = [
        (-1,-1),(0,-1),(1,-1),
        (-1, 0),       (1, 0),
        (-1, 1),(0, 1),(1, 1),
        (-1, 2),(0, 2),(1, 2)
    ]
    private let hiddenPerPhase: [Set<Int>] = [
        [6,8],[6,9],[1,3,7,11],[3,4],[4,6],[1,6,9],[1,2,9],[0,10],[0,7,10]
    ]
    private let spacing: CGFloat = 9
    private let dotSize: CGFloat = 6

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width/2; let cy = size.height/2
            let hidden = phase < hiddenPerPhase.count ? hiddenPerPhase[phase] : []
            for (i, dot) in allDots.enumerated() {
                guard !hidden.contains(i) else { continue }
                let x = cx + CGFloat(dot.0)*spacing - dotSize/2
                let y = cy + CGFloat(dot.1)*spacing - dotSize/2
                ctx.fill(Path(ellipseIn: CGRect(x:x,y:y,width:dotSize,height:dotSize)),
                         with: .color(.white.opacity(0.85)))
            }
        }
        .onAppear { startAnimation() }
        .onDisappear { stopAnimation() }
    }

    private func startAnimation() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            withAnimation(.linear(duration: 0.15)) { phase = (phase+1) % 9 }
        }
    }
    
    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Metal Liquid Glass Component
struct MetalLiquidGlass: View {
    let baseColor: Color
    let cornerRadius: CGFloat
    
    var body: some View {
        // Use Metal shader for liquid glass effect
        MetalLiquidGlassView(baseColor: baseColor, cornerRadius: cornerRadius)
            .allowsHitTesting(false)
    }
}

// MARK: - Liquid Glass Background Component (Fallback)
struct LiquidGlassBackground: View {
    let baseColor: Color
    
    var body: some View {
        ZStack {
            // Base color layer с блюром
            baseColor
                .blur(radius: 25)
            
            // Слой с легкой матовостью (frost effect ~43%)
            Color.white.opacity(0.15)
                .blur(radius: 5)
            
            // Градиент для имитации рефракции и глубины
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.25), location: 0.0),
                    .init(color: Color.clear, location: 0.4),
                    .init(color: Color.clear, location: 0.6),
                    .init(color: Color.black.opacity(0.1), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Световой блик под углом -45° (highlight effect)
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.35), location: 0.0),
                    .init(color: Color.white.opacity(0.15), location: 0.3),
                    .init(color: Color.clear, location: 0.5)
                ],
                startPoint: .init(x: 0.15, y: 0.15),
                endPoint: .init(x: 0.85, y: 0.85)
            )
            
            // Chromatic dispersion на краях (имитация дисперсии ~55%)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.1),
                    Color.blue.opacity(0.05),
                    Color.clear,
                    Color.red.opacity(0.03),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Внутреннее свечение (internal glow)
            RadialGradient(
                colors: [
                    Color.white.opacity(0.15),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 100
            )
            .blendMode(.plusLighter)
        }
    }
}

#Preview { ContentView() }
