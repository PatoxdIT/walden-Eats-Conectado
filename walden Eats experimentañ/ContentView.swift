import SwiftUI
import UIKit
import Combine
import FirebaseCore
import FirebaseFirestore

// MARK: - FIREBASE APP DELEGATE
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

// MARK: - MODELOS
struct UserProfile: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var age: Int
    var grade: String
    var email: String = ""
    var studentCardNumber: String = ""
    var identifierCode: String = ""
    var accountFunds: Double = 0.0

    enum CodingKeys: String, CodingKey {
        case id, name, age, grade, email, studentCardNumber, identifierCode, accountFunds
    }

    init(
        id: UUID = UUID(),
        name: String,
        age: Int,
        grade: String,
        email: String = "",
        studentCardNumber: String = "",
        identifierCode: String = "",
        accountFunds: Double = 0.0
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.grade = grade
        self.email = email
        self.studentCardNumber = studentCardNumber
        self.identifierCode = identifierCode
        self.accountFunds = accountFunds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        age = try container.decodeIfPresent(Int.self, forKey: .age) ?? 15
        grade = try container.decodeIfPresent(String.self, forKey: .grade) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        studentCardNumber = try container.decodeIfPresent(String.self, forKey: .studentCardNumber) ?? ""
        identifierCode = try container.decodeIfPresent(String.self, forKey: .identifierCode) ?? ""
        accountFunds = try container.decodeIfPresent(Double.self, forKey: .accountFunds) ?? 0.0
    }
}

struct FoodItem: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let price: Double
    let category: String
    let icon: String
    var dayOfWeek: Int?

    init(id: UUID = UUID(), name: String, price: Double, category: String, icon: String, dayOfWeek: Int? = nil) {
        self.id = id
        self.name = name
        self.price = price
        self.category = category
        self.icon = icon
        self.dayOfWeek = dayOfWeek
    }
}

struct PastOrder: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var orderID: String?
    let date: Date
    let userName: String
    let items: String
    let total: Double
    let recess: String
    let status: String
}

// MARK: - HELPERS
func normalizarCorreo(_ email: String) -> String {
    email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

func correoWaldenValido(_ email: String) -> Bool {
    let limpio = normalizarCorreo(email)
    return limpio.contains("@") && limpio.hasSuffix("@waldendos.edu.mx")
}

func guardarSesion(email: String) {
    UserDefaults.standard.set(normalizarCorreo(email), forKey: "WaldenLoggedEmail")
}

func cargarSesion() -> String? {
    UserDefaults.standard.string(forKey: "WaldenLoggedEmail")
}

func cerrarSesionLocal() {
    UserDefaults.standard.removeObject(forKey: "WaldenLoggedEmail")
}

func guardarEnTelefono(users: [UserProfile], history: [PastOrder]) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    if let encoded = try? encoder.encode(users) {
        UserDefaults.standard.set(encoded, forKey: "WaldenData")
    }

    if let encoded = try? encoder.encode(history) {
        UserDefaults.standard.set(encoded, forKey: "WaldenHistory")
    }
}

func cargarUsuariosLocal() -> [UserProfile] {
    guard let data = UserDefaults.standard.data(forKey: "WaldenData") else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([UserProfile].self, from: data)) ?? []
}

func cargarHistorialLocal() -> [PastOrder] {
    guard let data = UserDefaults.standard.data(forKey: "WaldenHistory") else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([PastOrder].self, from: data)) ?? []
}

func agruparItems(_ items: [FoodItem]) -> String {
    let dict = Dictionary(grouping: items, by: { $0.name })
    let contados = dict.map { "\($0.value.count)x \($0.key)" }
    return contados.sorted().joined(separator: ", ")
}

func formatearNumeroTarjeta(_ number: String) -> String {
    let limpio = number.replacingOccurrences(of: " ", with: "")
    return stride(from: 0, to: limpio.count, by: 4).map { index in
        let start = limpio.index(limpio.startIndex, offsetBy: index)
        let end = limpio.index(start, offsetBy: min(4, limpio.count - index), limitedBy: limpio.endIndex) ?? limpio.endIndex
        return String(limpio[start..<end])
    }.joined(separator: " ")
}

func tarjetaEnmascarada(_ number: String) -> String {
    let limpio = number.replacingOccurrences(of: " ", with: "")
    guard limpio.count >= 4 else { return limpio }
    return "•••• •••• •••• \(limpio.suffix(4))"
}

func money(_ value: Double) -> String {
    String(format: "$%.2f", value)
}

// MARK: - FIREBASE SERVICE
final class FirebaseWalletService: ObservableObject {
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []

    deinit {
        listeners.forEach { $0.remove() }
    }

    func stopListeners() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
    }

    func syncUsersBalances(appVM: AppViewModel) {
        stopListeners()

        for user in appVM.users {
            guard !user.email.isEmpty else { continue }
            let docID = normalizarCorreo(user.email)

            let listener = db.collection("students").document(docID).addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ Error escuchando saldo de \(docID): \(error.localizedDescription)")
                    return
                }

                guard let data = snapshot?.data() else { return }

                let remoteFunds = data["accountFunds"] as? Double ?? (data["accountFunds"] as? NSNumber)?.doubleValue ?? 0.0
                let remoteCard = data["studentCardNumber"] as? String ?? user.studentCardNumber
                let remoteCode = data["identifierCode"] as? String ?? user.identifierCode

                DispatchQueue.main.async {
                    if let index = appVM.users.firstIndex(where: { normalizarCorreo($0.email) == docID }) {
                        appVM.users[index].accountFunds = remoteFunds
                        appVM.users[index].studentCardNumber = remoteCard
                        appVM.users[index].identifierCode = remoteCode
                        guardarEnTelefono(users: appVM.users, history: appVM.history)
                    }
                }
            }

            listeners.append(listener)
        }
    }

    func createOrUpdateStudent(_ user: UserProfile) {
        guard !user.email.isEmpty else { return }
        let docID = normalizarCorreo(user.email)

        db.collection("students").document(docID).setData([
            "name": user.name,
            "age": user.age,
            "grade": user.grade,
            "email": docID,
            "studentCardNumber": user.studentCardNumber,
            "identifierCode": user.identifierCode,
            "accountFunds": user.accountFunds,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true) { error in
            if let error = error {
                print("❌ Error actualizando alumno: \(error.localizedDescription)")
            } else {
                print("✅ Alumno actualizado en students/\(docID)")
            }
        }
    }

    func sendOrder(
        user: UserProfile,
        cart: [FoodItem],
        recess: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let orderID = "\(String("ABCDEFGHIJKLMNOPQRSTUVWXYZ".randomElement()!))\(Int.random(in: 10...99))"
        let itemsText = agruparItems(cart)
        let total = cart.reduce(0) { $0 + $1.price }

        let data: [String: Any] = [
            "orderID": orderID,
            "userName": user.name,
            "email": normalizarCorreo(user.email),
            "items": itemsText,
            "total": total,
            "recess": recess,
            "timestamp": Timestamp(date: Date()),
            "status": "pendiente", // IMPORTANTE: Gourmet debe ver pedidos pendientes
            "studentCardNumber": user.studentCardNumber,
            "identifierCode": user.identifierCode
        ]

        db.collection("pedidos").document(orderID).setData(data) { error in
            if let error = error {
                print("❌ Error al guardar pedido en Firebase: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                print("✅ Pedido guardado en Firebase con ID: \(orderID)")
                completion(.success(orderID))
            }
        }
    }

    func deductBalance(
        for user: UserProfile,
        amount: Double,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let docID = normalizarCorreo(user.email)
        let studentRef = db.collection("students").document(docID)

        db.runTransaction({ transaction, errorPointer -> Any? in
            let snapshot: DocumentSnapshot
            do {
                snapshot = try transaction.getDocument(studentRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            let currentFunds = snapshot.data()?["accountFunds"] as? Double
                ?? (snapshot.data()?["accountFunds"] as? NSNumber)?.doubleValue
                ?? 0.0

            let newBalance = currentFunds - amount
            if newBalance < 0 {
                let error = NSError(
                    domain: "FirebaseWalletService",
                    code: 1001,
                    userInfo: [NSLocalizedDescriptionKey: "Saldo insuficiente en servidor."]
                )
                errorPointer?.pointee = error
                return nil
            }

            transaction.updateData([
                "accountFunds": newBalance,
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: studentRef)

            return nil
        }) { _, error in
            if let error = error {
                print("❌ Error descontando saldo: \(error.localizedDescription)")
                completion(.failure(error))
            } else {
                print("✅ Saldo descontado correctamente")
                completion(.success(()))
            }
        }
    }
}

// MARK: - VIEW MODEL
final class AppViewModel: ObservableObject {
    @Published var users: [UserProfile] = []
    @Published var history: [PastOrder] = []
    @Published var cart: [FoodItem] = []
    @Published var loggedEmail: String? = nil

    let firebase = FirebaseWalletService()

    init() {
        users = cargarUsuariosLocal()
        history = cargarHistorialLocal()
        loggedEmail = cargarSesion()
    }

    func persist() {
        guardarEnTelefono(users: users, history: history)
    }

    func startServerSync() {
        firebase.syncUsersBalances(appVM: self)
    }

    func stopServerSync() {
        firebase.stopListeners()
    }

    func addStudent(name: String, grade: String, email: String, cardNumber: String, identifierCode: String) -> Bool {
        let cleanEmail = normalizarCorreo(email)
        let cleanCard = cardNumber.replacingOccurrences(of: " ", with: "")
        let cleanCode = identifierCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        guard correoWaldenValido(cleanEmail) else { return false }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !grade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !cleanCard.isEmpty else { return false }
        guard !cleanCode.isEmpty else { return false }

        if users.contains(where: { normalizarCorreo($0.email) == cleanEmail }) {
            return false
        }

        let newUser = UserProfile(
            name: name,
            age: 15,
            grade: grade,
            email: cleanEmail,
            studentCardNumber: cleanCard,
            identifierCode: cleanCode,
            accountFunds: 0
        )

        users.append(newUser)
        persist()
        firebase.createOrUpdateStudent(newUser)
        startServerSync()
        return true
    }

    func removeStudent(_ user: UserProfile) {
        users.removeAll { $0.id == user.id }
        persist()
        startServerSync()
    }
}

// MARK: - APP
@main
struct WaldenEatsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var appVM = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appVM)
        }
    }
}

// MARK: - ROOT VIEW
struct ContentView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var showSplash = true

    var body: some View {
        ZStack {
            if showSplash {
                SplashScreenView(isActive: $showSplash)
            } else if appVM.loggedEmail == nil {
                LoginView()
            } else {
                TabView {
                    MenuView()
                        .tabItem { Label("Menú", systemImage: "fork.knife") }

                    HistoryView()
                        .tabItem { Label("Pedidos", systemImage: "clock.fill") }

                    SettingsView()
                        .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }

                    AccountView()
                        .tabItem { Label("Cuenta", systemImage: "person.crop.circle.fill") }
                }
                .onAppear {
                    appVM.startServerSync()
                }
            }
        }
    }
}

// MARK: - SPLASH
struct SplashScreenView: View {
    @Binding var isActive: Bool
    @State private var textScale: CGFloat = 0.85
    @State private var textOpacity: Double = 0.0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    Color(UIColor.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 110, height: 110)

                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(Color.white, Color.accentColor)
                }

                Text("Walden Eats")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundColor(.accentColor)
                    .scaleEffect(textScale)
                    .opacity(textOpacity)

                Text("Pide, paga y disfruta")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .opacity(textOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.78)) {
                textScale = 1.0
                textOpacity = 1.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isActive = false
                }
            }
        }
    }
}

// MARK: - LOGIN
struct LoginView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.14),
                        Color(UIColor.systemBackground),
                        Color(UIColor.systemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        Spacer(minLength: 40)

                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 120, height: 120)

                            Image(systemName: "building.columns.circle.fill")
                                .font(.system(size: 66))
                                .foregroundStyle(.white, Color.accentColor)
                        }

                        VStack(spacing: 8) {
                            Text("Inicio de sesión")
                                .font(.system(size: 30, weight: .heavy, design: .rounded))

                            Text("Solo pueden entrar correos institucionales")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        VStack(spacing: 14) {
                            TextField("correo@waldendos.edu.mx", text: $email)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16))

                            SecureField("Contraseña", text: $password)
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16))

                            if !errorText.isEmpty {
                                Text(errorText)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Button {
                                let cleanEmail = normalizarCorreo(email)

                                guard correoWaldenValido(cleanEmail) else {
                                    errorText = "Solo se permiten correos con dominio @waldendos.edu.mx"
                                    return
                                }

                                guard !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                    errorText = "Ingresa una contraseña"
                                    return
                                }

                                errorText = ""
                                guardarSesion(email: cleanEmail)
                                appVM.loggedEmail = cleanEmail
                                appVM.startServerSync()
                            } label: {
                                Text("Entrar")
                                    .font(.headline.bold())
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                            }
                        }
                        .padding(20)
                        .background(Color(UIColor.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 8)

                        Spacer(minLength: 30)
                    }
                    .padding()
                }
            }
        }
    }
}

// MARK: - MENU
struct MenuView: View {
    @EnvironmentObject var appVM: AppViewModel
    @State private var expandedCategories: Set<String> = [
        "⭐ Especialidad por Día",
        "🌮 Platos",
        "🍉 Snacks y Fruta",
        "💧 Bebidas"
    ]

    var currentDay: Int { Calendar.current.component(.weekday, from: Date()) }

    let menu = [
        FoodItem(name: "Mollete", price: 15.0, category: "🌮 Platos", icon: "🥖"),
        FoodItem(name: "Torta de Salchicha", price: 35.0, category: "🌮 Platos", icon: "🥪"),
        FoodItem(name: "Sopes", price: 25.0, category: "🌮 Platos", icon: "🥙"),
        FoodItem(name: "Tacos de Frijol", price: 30.0, category: "🌮 Platos", icon: "🌮"),
        FoodItem(name: "Salchipulpos", price: 30.0, category: "🌮 Platos", icon: "🐙"),
        FoodItem(name: "Banderilla", price: 25.0, category: "🌮 Platos", icon: "🌭"),
        FoodItem(name: "Enfrijoladas", price: 35.0, category: "🌮 Platos", icon: "🥘"),
        FoodItem(name: "Elote Cocido", price: 25.0, category: "🌮 Platos", icon: "🌽"),
        FoodItem(name: "Tlacoyo", price: 25.0, category: "🌮 Platos", icon: "🫓"),

        FoodItem(name: "Chilaquiles (Lunes)", price: 40.0, category: "⭐ Especialidad por Día", icon: "🥣", dayOfWeek: 2),
        FoodItem(name: "Torta de Milanesa (Martes)", price: 35.0, category: "⭐ Especialidad por Día", icon: "🥩", dayOfWeek: 3),
        FoodItem(name: "Hot cakes (Miércoles)", price: 25.0, category: "⭐ Especialidad por Día", icon: "🥞", dayOfWeek: 4),
        FoodItem(name: "Taco de Bistec (Jueves)", price: 30.0, category: "⭐ Especialidad por Día", icon: "🌯", dayOfWeek: 5),
        FoodItem(name: "Pambazo (Viernes)", price: 30.0, category: "⭐ Especialidad por Día", icon: "🍔", dayOfWeek: 6),

        FoodItem(name: "Palomitas", price: 12.0, category: "🍉 Snacks y Fruta", icon: "🍿"),
        FoodItem(name: "Vaso de Jícama", price: 20.0, category: "🍉 Snacks y Fruta", icon: "🥕"),
        FoodItem(name: "Vaso de Zanahoria", price: 20.0, category: "🍉 Snacks y Fruta", icon: "🥕"),
        FoodItem(name: "Vaso de Pepino", price: 20.0, category: "🍉 Snacks y Fruta", icon: "🥒"),
        FoodItem(name: "Vaso de Sandía", price: 20.0, category: "🍉 Snacks y Fruta", icon: "🍉"),
        FoodItem(name: "Vaso de Mango", price: 28.0, category: "🍉 Snacks y Fruta", icon: "🥭"),
        FoodItem(name: "Jicaleta", price: 15.0, category: "🍉 Snacks y Fruta", icon: "🍭"),
        FoodItem(name: "Congelada", price: 15.0, category: "🍉 Snacks y Fruta", icon: "🧊"),

        FoodItem(name: "Agua Grande", price: 14.0, category: "💧 Bebidas", icon: "💧"),
        FoodItem(name: "Agua Chica", price: 10.0, category: "💧 Bebidas", icon: "🚰")
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    headerView

                    ScrollView {
                        VStack(spacing: 16) {
                            let categories = ["⭐ Especialidad por Día", "🌮 Platos", "🍉 Snacks y Fruta", "💧 Bebidas"]

                            ForEach(categories, id: \.self) { cat in
                                VStack(spacing: 0) {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            toggleCategory(cat)
                                        }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(cat)
                                                    .font(.headline)
                                                    .foregroundColor(.primary)

                                                Text("\(menu.filter { $0.category == cat }.count) productos")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }

                                            Spacer()

                                            Image(systemName: expandedCategories.contains(cat) ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                                                .font(.title3)
                                                .foregroundColor(.accentColor)
                                        }
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 18)
                                                .fill(Color(UIColor.secondarySystemBackground))
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    if expandedCategories.contains(cat) {
                                        VStack(spacing: 12) {
                                            ForEach(menu.filter { $0.category == cat }) { item in
                                                let quantity = appVM.cart.filter { $0.name == item.name }.count
                                                let isAvailable = (cat != "⭐ Especialidad por Día" || item.dayOfWeek == currentDay)

                                                HStack(spacing: 14) {
                                                    ZStack {
                                                        RoundedRectangle(cornerRadius: 16)
                                                            .fill(isAvailable ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.12))
                                                            .frame(width: 58, height: 58)

                                                        Text(item.icon)
                                                            .font(.system(size: 28))
                                                    }

                                                    VStack(alignment: .leading, spacing: 6) {
                                                        Text(item.name)
                                                            .font(.headline)
                                                            .foregroundColor(isAvailable ? .primary : .gray)
                                                            .strikethrough(!isAvailable, color: .red)

                                                        HStack(spacing: 8) {
                                                            Text(money(item.price))
                                                                .font(.subheadline)
                                                                .foregroundColor(.secondary)

                                                            if quantity > 0 {
                                                                Text("\(quantity) en carrito")
                                                                    .font(.caption.bold())
                                                                    .padding(.horizontal, 10)
                                                                    .padding(.vertical, 5)
                                                                    .background(Color.accentColor.opacity(0.14))
                                                                    .foregroundColor(.accentColor)
                                                                    .clipShape(Capsule())
                                                            }
                                                        }

                                                        if !isAvailable {
                                                            Text("No disponible hoy")
                                                                .font(.caption)
                                                                .foregroundColor(.red)
                                                        }
                                                    }

                                                    Spacer()

                                                    if isAvailable {
                                                        if quantity == 0 {
                                                            Button {
                                                                appVM.cart.append(item)
                                                            } label: {
                                                                Image(systemName: "plus.circle.fill")
                                                                    .font(.system(size: 34))
                                                                    .foregroundColor(.green)
                                                            }
                                                            .buttonStyle(.borderless)
                                                        } else {
                                                            HStack(spacing: 12) {
                                                                Button {
                                                                    if let index = appVM.cart.lastIndex(where: { $0.name == item.name }) {
                                                                        appVM.cart.remove(at: index)
                                                                    }
                                                                } label: {
                                                                    Image(systemName: quantity == 1 ? "trash.fill" : "minus.circle.fill")
                                                                        .font(.system(size: 24))
                                                                        .foregroundColor(quantity == 1 ? .red : .orange)
                                                                }
                                                                .buttonStyle(.borderless)

                                                                Text("\(quantity)")
                                                                    .font(.headline.bold())
                                                                    .frame(minWidth: 20)

                                                                Button {
                                                                    appVM.cart.append(item)
                                                                } label: {
                                                                    Image(systemName: "plus.circle.fill")
                                                                        .font(.system(size: 28))
                                                                        .foregroundColor(.green)
                                                                }
                                                                .buttonStyle(.borderless)
                                                            }
                                                            .padding(.horizontal, 12)
                                                            .padding(.vertical, 8)
                                                            .background(Color.white)
                                                            .clipShape(Capsule())
                                                            .overlay(
                                                                Capsule()
                                                                    .stroke(Color.gray.opacity(0.22), lineWidth: 1)
                                                            )
                                                        }
                                                    }
                                                }
                                                .padding(14)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 20)
                                                        .fill(Color(UIColor.systemBackground))
                                                )
                                            }
                                        }
                                        .padding(.top, 12)
                                    }
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 24)
                                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                                )
                            }

                            Color.clear.frame(height: appVM.cart.isEmpty ? 12 : 100)
                        }
                        .padding()
                    }
                }

                if !appVM.cart.isEmpty {
                    NavigationLink(destination: CheckoutView()) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enviar pedido")
                                    .font(.headline.bold())
                                Text("\(appVM.cart.count) artículo(s)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.88))
                            }

                            Spacer()

                            Text(money(appVM.cart.reduce(0) { $0 + $1.price }))
                                .font(.headline.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.18))
                                .clipShape(Capsule())
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .padding()
                    }
                }
            }
            .navigationTitle("Menú")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Walden Eats")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    Text("Tarjeta manual y saldo desde servidor")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.92))
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 58, height: 58)

                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white, .white)
                }
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .padding()
    }

    private func toggleCategory(_ category: String) {
        if expandedCategories.contains(category) {
            expandedCategories.remove(category)
        } else {
            expandedCategories.insert(category)
        }
    }
}

// MARK: - CHECKOUT
struct CheckoutView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedUserIndex = 0
    @State private var selectedRecess = "1er Receso"
    @State private var showSuccess = false
    @State private var paymentError = ""
    @State private var isProcessing = false

    var totalOrder: Double {
        appVM.cart.reduce(0) { $0 + $1.price }
    }

    var body: some View {
        Form {
            if appVM.users.isEmpty {
                Text("⚠️ Registra un estudiante en Ajustes")
                    .foregroundColor(.red)
                    .padding()
            } else {
                Section("Resumen") {
                    Text(agruparItems(appVM.cart))
                    Text("Total: \(money(totalOrder))")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                }

                Section("Estudiante") {
                    Picker("¿Quién eres?", selection: $selectedUserIndex) {
                        ForEach(0..<appVM.users.count, id: \.self) { i in
                            Text(appVM.users[i].name).tag(i)
                        }
                    }

                    let user = appVM.users[selectedUserIndex]

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tarjeta registrada manualmente")
                            .font(.headline)
                        Text("Número: \(formatearNumeroTarjeta(user.studentCardNumber))")
                            .font(.subheadline)
                        Text("Código identificador: \(user.identifierCode)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Saldo en servidor: \(money(user.accountFunds))")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                    .padding(.vertical, 6)
                }

                Section("Entrega") {
                    Picker("Receso", selection: $selectedRecess) {
                        Text("1er Receso").tag("1er Receso")
                        Text("2do Receso").tag("2do Receso")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Pedido") {
                    if !paymentError.isEmpty {
                        Text(paymentError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    Button {
                        confirmOrder()
                    } label: {
                        HStack {
                            Spacer()
                            if isProcessing {
                                ProgressView()
                            } else {
                                Text("Confirmar Pedido")
                                    .bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(isProcessing || appVM.users.isEmpty || appVM.cart.isEmpty)
                    .foregroundColor(.accentColor)
                }
            }
        }
        .navigationTitle("Pago")
        .fullScreenCover(isPresented: $showSuccess) {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 82))
                    .foregroundColor(.green)

                Text("Pedido enviado")
                    .font(.largeTitle)
                    .bold()

                Text("El pedido se guardó como pendiente y el saldo se descontó en Firebase.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Volver") {
                    appVM.cart.removeAll()
                    showSuccess = false
                    dismiss()
                }
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding()
        }
    }

    private func confirmOrder() {
        guard appVM.users.indices.contains(selectedUserIndex) else { return }
        let user = appVM.users[selectedUserIndex]

        guard !user.studentCardNumber.isEmpty else {
            paymentError = "El estudiante no tiene una tarjeta registrada."
            return
        }

        guard !user.identifierCode.isEmpty else {
            paymentError = "El estudiante no tiene código identificador."
            return
        }

        guard user.accountFunds >= totalOrder else {
            paymentError = "Saldo insuficiente según el servidor."
            return
        }

        paymentError = ""
        isProcessing = true

        let itemsSnapshot = appVM.cart
        let totalSnapshot = totalOrder

        appVM.firebase.sendOrder(
            user: user,
            cart: itemsSnapshot,
            recess: selectedRecess
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let orderID):
                    appVM.firebase.deductBalance(for: user, amount: totalSnapshot) { balanceResult in
                        DispatchQueue.main.async {
                            isProcessing = false

                            switch balanceResult {
                            case .success:
                                let order = PastOrder(
                                    orderID: orderID,
                                    date: Date(),
                                    userName: user.name,
                                    items: agruparItems(itemsSnapshot),
                                    total: totalSnapshot,
                                    recess: selectedRecess,
                                    status: "pendiente"
                                )
                                appVM.history.insert(order, at: 0)
                                appVM.persist()
                                appVM.startServerSync()
                                showSuccess = true

                            case .failure(let error):
                                paymentError = "Pedido enviado, pero no se pudo descontar saldo: \(error.localizedDescription)"
                            }
                        }
                    }

                case .failure(let error):
                    isProcessing = false
                    paymentError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - HISTORY
struct HistoryView: View {
    @EnvironmentObject var appVM: AppViewModel

    var body: some View {
        NavigationStack {
            Group {
                if appVM.history.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 52))
                            .foregroundColor(.accentColor)

                        Text("Aún no hay pedidos")
                            .font(.title2.bold())

                        Text("Cuando mandes tu primer pedido aparecerá aquí.")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(appVM.history) { order in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(order.userName).bold()
                                    Text("#\(order.orderID ?? "")")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(order.date, style: .date)
                                        .font(.caption)
                                }

                                Text(order.items)
                                    .font(.subheadline)

                                HStack {
                                    Text(order.recess)
                                        .font(.caption)
                                        .padding(6)
                                        .background(Color.accentColor.opacity(0.12))
                                        .cornerRadius(8)

                                    Text(order.status.capitalized)
                                        .font(.caption.bold())
                                        .padding(6)
                                        .background(
                                            (order.status.lowercased() == "pendiente" ? Color.orange : Color.green).opacity(0.12)
                                        )
                                        .cornerRadius(8)

                                    Spacer()

                                    Text(money(order.total))
                                        .bold()
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .onDelete { offsets in
                            appVM.history.remove(atOffsets: offsets)
                            appVM.persist()
                        }
                    }
                }
            }
            .navigationTitle("Mis Pedidos")
        }
    }
}

// MARK: - SETTINGS
struct SettingsView: View {
    @EnvironmentObject var appVM: AppViewModel

    @State private var nName = ""
    @State private var nGrade = ""
    @State private var nEmail = ""
    @State private var nCardNumber = ""
    @State private var nIdentifierCode = ""
    @State private var formError = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuración de cuenta") {
                    HStack {
                        Image(systemName: "envelope.badge.fill")
                            .foregroundColor(.accentColor)
                        Text(appVM.loggedEmail ?? "Sin sesión")
                            .font(.subheadline)
                    }

                    Button("Cerrar sesión") {
                        cerrarSesionLocal()
                        appVM.loggedEmail = nil
                        appVM.stopServerSync()
                    }
                    .foregroundColor(.red)
                }

                Section("Estudiantes registrados") {
                    if appVM.users.isEmpty {
                        Text("No hay estudiantes registrados.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(appVM.users) { user in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("\(user.name) (\(user.grade))")
                                        .font(.headline)

                                    Spacer()

                                    Button {
                                        appVM.removeStudent(user)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.borderless)
                                }

                                Text(user.email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("Tarjeta: \(tarjetaEnmascarada(user.studentCardNumber))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("Código: \(user.identifierCode)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text("Saldo del servidor: \(money(user.accountFunds))")
                                    .font(.caption.bold())
                                    .foregroundColor(.accentColor)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Agregar estudiante con tarjeta manual") {
                    TextField("Nombre", text: $nName)
                    TextField("Grado", text: $nGrade)

                    TextField("Correo institucional", text: $nEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Número de tarjeta", text: $nCardNumber)
                        .keyboardType(.numberPad)

                    TextField("Código identificador", text: $nIdentifierCode)
                        .textInputAutocapitalization(.characters)

                    if !formError.isEmpty {
                        Text(formError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Button("Guardar") {
                        let ok = appVM.addStudent(
                            name: nName,
                            grade: nGrade,
                            email: nEmail,
                            cardNumber: nCardNumber,
                            identifierCode: nIdentifierCode
                        )

                        if ok {
                            formError = ""
                            nName = ""
                            nGrade = ""
                            nEmail = ""
                            nCardNumber = ""
                            nIdentifierCode = ""
                        } else {
                            formError = "Revisa nombre, grado, correo institucional, número de tarjeta y código. También puede que ese correo ya esté registrado."
                        }
                    }
                    .disabled(
                        nName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        nGrade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        nEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        nCardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        nIdentifierCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}

// MARK: - ACCOUNT
struct AccountView: View {
    @EnvironmentObject var appVM: AppViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cuenta institucional")
                            .font(.title2.bold())

                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 34))
                                .foregroundColor(.accentColor)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(appVM.loggedEmail ?? "Sin correo")
                                    .font(.headline)

                                Text("Tarjetas registradas manualmente")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tarjetas estudiantiles")
                            .font(.title3.bold())

                        if appVM.users.isEmpty {
                            Text("No hay cuentas de estudiantes registradas.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(appVM.users) { user in
                                VStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 14) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text("Tarjeta estudiantil")
                                                    .font(.caption.bold())
                                                    .foregroundColor(.white.opacity(0.85))

                                                Text(user.name)
                                                    .font(.title3.bold())
                                                    .foregroundColor(.white)
                                            }

                                            Spacer()

                                            Image(systemName: "creditcard.fill")
                                                .font(.title2)
                                                .foregroundColor(.white.opacity(0.9))
                                        }

                                        VStack(alignment: .leading, spacing: 10) {
                                            Text(formatearNumeroTarjeta(user.studentCardNumber))
                                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                                .foregroundColor(.white)

                                            Text("Código identificador: \(user.identifierCode)")
                                                .font(.subheadline)
                                                .foregroundColor(.white.opacity(0.92))

                                            Text("Saldo leído del servidor: \(money(user.accountFunds))")
                                                .font(.headline.bold())
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        LinearGradient(
                                            colors: [Color.accentColor, Color.blue.opacity(0.75)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 24))
                                }
                                .padding()
                                .background(Color(UIColor.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                            }
                        }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                }
                .padding()
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Cuenta")
        }
    }
}

