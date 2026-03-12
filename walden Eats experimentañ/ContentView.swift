import SwiftUI
import Combine
import FirebaseCore
import FirebaseFirestore

// MARK: - CONFIGURACIÓN DE FIREBASE
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

// MARK: - MODELOS DE DATOS
struct UserProfile: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var age: Int
    var grade: String
    var email: String = ""
    var accountCode: String = ""
    var accountFunds: Int = 0

    enum CodingKeys: String, CodingKey {
        case id, name, age, grade, email, accountCode, accountFunds
    }

    init(id: UUID = UUID(), name: String, age: Int, grade: String, email: String = "", accountCode: String = "", accountFunds: Int = 0) {
        self.id = id
        self.name = name
        self.age = age
        self.grade = grade
        self.email = email
        self.accountCode = accountCode
        self.accountFunds = accountFunds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        age = try container.decodeIfPresent(Int.self, forKey: .age) ?? 15
        grade = try container.decodeIfPresent(String.self, forKey: .grade) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        accountCode = try container.decodeIfPresent(String.self, forKey: .accountCode) ?? ""
        accountFunds = try container.decodeIfPresent(Int.self, forKey: .accountFunds) ?? 0
    }
}

struct CreditCard: Identifiable, Codable, Equatable {
    var id = UUID()
    var holderName: String
    var lastFour: String
    var expiry: String
}

struct FoodItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let price: Double
    let category: String
    let icon: String
    var dayOfWeek: Int? = nil
}

struct PastOrder: Identifiable, Codable, Equatable {
    var id = UUID()
    var orderID: String?
    let date: Date
    let userName: String
    let items: String
    let total: Double
    let recess: String
}

// MARK: - SESIÓN
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

// MARK: - GUARDADO LOCAL
func guardarEnTelefono(users: [UserProfile], cards: [CreditCard], history: [PastOrder]) {
    if let encoded = try? JSONEncoder().encode(users) {
        UserDefaults.standard.set(encoded, forKey: "WaldenData")
    }
    if let encoded = try? JSONEncoder().encode(cards) {
        UserDefaults.standard.set(encoded, forKey: "WaldenCards")
    }
    if let encoded = try? JSONEncoder().encode(history) {
        UserDefaults.standard.set(encoded, forKey: "WaldenHistory")
    }
}

func agruparItems(_ items: [FoodItem]) -> String {
    let dict = Dictionary(grouping: items, by: { $0.name })
    let contados = dict.map { "\($0.value.count)x \($0.key)" }
    return contados.sorted().joined(separator: ", ")
}

func generarCodigoCuenta() -> String {
    String(Int.random(in: 10000000...99999999))
}

func generarFondosAleatorios() -> Int {
    Int.random(in: 50...2500)
}

// MARK: - PUNTO DE ENTRADA
@main
struct WaldenEatsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var store = UserStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

class UserStore: ObservableObject {
    @Published var users: [UserProfile] = []
    @Published var cards: [CreditCard] = []
    @Published var history: [PastOrder] = []
}

// MARK: - VISTA PRINCIPAL
struct ContentView: View {
    @State private var showSplash = true
    @State private var users: [UserProfile] = []
    @State private var cards: [CreditCard] = []
    @State private var history: [PastOrder] = []
    @State private var cart: [FoodItem] = []
    @State private var loggedEmail: String? = nil

    var body: some View {
        ZStack {
            if showSplash {
                SplashScreenView(isActive: $showSplash)
                    .transition(.opacity)
            } else if loggedEmail == nil {
                LoginView(loggedEmail: $loggedEmail)
            } else {
                TabView {
                    MenuView(cart: $cart, users: $users, cards: $cards, history: $history)
                        .tabItem { Label("Menú", systemImage: "fork.knife") }

                    HistoryView(history: $history, users: $users, cards: $cards)
                        .tabItem { Label("Pedidos", systemImage: "clock.fill") }

                    SettingsView(users: $users, cards: $cards, history: $history, loggedEmail: $loggedEmail)
                        .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }

                    AccountView(users: $users, cards: $cards, history: $history, loggedEmail: $loggedEmail)
                        .tabItem { Label("Cuenta", systemImage: "person.crop.circle.fill") }
                }
            }
        }
        .onAppear {
            if let data = UserDefaults.standard.data(forKey: "WaldenData"),
               let decoded = try? JSONDecoder().decode([UserProfile].self, from: data) {
                users = decoded
            }

            if let data = UserDefaults.standard.data(forKey: "WaldenCards"),
               let decoded = try? JSONDecoder().decode([CreditCard].self, from: data) {
                cards = decoded
            }

            if let data = UserDefaults.standard.data(forKey: "WaldenHistory"),
               let decoded = try? JSONDecoder().decode([PastOrder].self, from: data) {
                history = decoded
            }

            loggedEmail = cargarSesion()
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

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isActive = false
                }
            }
        }
    }
}

// MARK: - LOGIN
struct LoginView: View {
    @Binding var loggedEmail: String?
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
                                loggedEmail = cleanEmail
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

                        VStack(spacing: 6) {
                            Text("Dominio permitido")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("@waldendos.edu.mx")
                                .font(.headline.bold())
                                .foregroundColor(.accentColor)
                        }

                        Spacer(minLength: 30)
                    }
                    .padding()
                }
            }
        }
    }
}

// MARK: - MENÚ
struct MenuView: View {
    @Binding var cart: [FoodItem]
    @Binding var users: [UserProfile]
    @Binding var cards: [CreditCard]
    @Binding var history: [PastOrder]

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
                                                let quantity = cart.filter { $0.name == item.name }.count
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
                                                            Text("$\(item.price, specifier: "%.2f")")
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
                                                            Button(action: {
                                                                cart.append(item)
                                                            }) {
                                                                Image(systemName: "plus.circle.fill")
                                                                    .font(.system(size: 34))
                                                                    .foregroundColor(.green)
                                                            }
                                                            .buttonStyle(.borderless)
                                                        } else {
                                                            HStack(spacing: 12) {
                                                                Button(action: {
                                                                    if let index = cart.lastIndex(where: { $0.name == item.name }) {
                                                                        cart.remove(at: index)
                                                                    }
                                                                }) {
                                                                    Image(systemName: quantity == 1 ? "trash.fill" : "minus.circle.fill")
                                                                        .font(.system(size: 24))
                                                                        .foregroundColor(quantity == 1 ? .red : .orange)
                                                                }
                                                                .buttonStyle(.borderless)

                                                                Text("\(quantity)")
                                                                    .font(.headline.bold())
                                                                    .frame(minWidth: 20)

                                                                Button(action: {
                                                                    cart.append(item)
                                                                }) {
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
                                                            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
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
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 24)
                                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                                )
                            }

                            Color.clear.frame(height: cart.isEmpty ? 12 : 100)
                        }
                        .padding()
                    }
                }

                if !cart.isEmpty {
                    NavigationLink(destination: CheckoutView(cart: $cart, users: $users, cards: $cards, history: $history)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ir a pagar")
                                    .font(.headline.bold())

                                Text("\(cart.count) artículo(s)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.88))
                            }

                            Spacer()

                            Text("$\(cart.reduce(0) { $0 + $1.price }, specifier: "%.2f")")
                                .font(.headline.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.18))
                                .clipShape(Capsule())
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: Color.accentColor.opacity(0.26), radius: 10, x: 0, y: 6)
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

                    Text("Comida rica y nutritiva para tu día 🌟")
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

            HStack(spacing: 8) {
                pill("Rápido")
                pill("Seguro")
                pill("Escolar")
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

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.18))
            .foregroundColor(.white)
            .clipShape(Capsule())
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
    @Binding var cart: [FoodItem]
    @Binding var users: [UserProfile]
    @Binding var cards: [CreditCard]
    @Binding var history: [PastOrder]

    @State private var selUser = 0
    @State private var selCard = 0
    @State private var selectedRecess = "1er Receso"
    @State private var showSuccess = false

    var body: some View {
        Form {
            if users.isEmpty || cards.isEmpty {
                Text("⚠️ Registra tu perfil y tarjeta en Ajustes")
                    .foregroundColor(.red)
                    .padding()
            } else {
                Section("Resumen") {
                    Text(agruparItems(cart))
                        .font(.subheadline)

                    Text("Total: $\(cart.reduce(0) { $0 + $1.price }, specifier: "%.2f")")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                }

                Section("Usuario") {
                    Picker("¿Quién eres?", selection: $selUser) {
                        ForEach(0..<users.count, id: \.self) {
                            Text(users[$0].name).tag($0)
                        }
                    }
                }

                Section("Entrega") {
                    Picker("Receso", selection: $selectedRecess) {
                        Text("1er Receso").tag("1er Receso")
                        Text("2do Receso").tag("2do Receso")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Pago") {
                    Picker("Tarjeta", selection: $selCard) {
                        ForEach(0..<cards.count, id: \.self) {
                            Text("**** \(cards[$0].lastFour)").tag($0)
                        }
                    }
                }

                Button("Confirmar Pedido") {
                    let id = "\(String("ABCDEFGHIJKLMNOPQRSTUVWXYZ".randomElement()!))\(Int.random(in: 1...99))"
                    let orderString = agruparItems(cart)
                    let totalOrder = cart.reduce(0) { $0 + $1.price }

                    let order = PastOrder(
                        orderID: id,
                        date: Date(),
                        userName: users[selUser].name,
                        items: orderString,
                        total: totalOrder,
                        recess: selectedRecess
                    )

                    history.insert(order, at: 0)
                    guardarEnTelefono(users: users, cards: cards, history: history)

                    let db = Firestore.firestore()
                    db.collection("pedidos").document(id).setData([
                        "orderID": id,
                        "userName": users[selUser].name,
                        "items": orderString,
                        "total": totalOrder,
                        "recess": selectedRecess,
                        "timestamp": FieldValue.serverTimestamp(),
                        "status": "pendiente"
                    ]) { error in
                        if let error = error {
                            print("Error al guardar en Firebase: \(error.localizedDescription)")
                        } else {
                            print("¡Pedido \(id) enviado a Firebase con éxito!")
                        }
                    }

                    showSuccess = true
                }
                .bold()
                .frame(maxWidth: .infinity)
                .foregroundColor(.accentColor)
            }
        }
        .navigationTitle("Pago")
        .fullScreenCover(isPresented: $showSuccess) {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)

                Text("¡Listo!")
                    .font(.largeTitle)
                    .bold()

                Text("Tu pedido se ha enviado a la cafetería")
                    .foregroundColor(.secondary)

                Button("Volver") {
                    cart.removeAll()
                    showSuccess = false
                }
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
    }
}

// MARK: - HISTORIAL
struct HistoryView: View {
    @Binding var history: [PastOrder]
    @Binding var users: [UserProfile]
    @Binding var cards: [CreditCard]

    var body: some View {
        NavigationStack {
            Group {
                if history.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 52))
                            .foregroundColor(.accentColor)

                        Text("Aún no hay pedidos")
                            .font(.title2.bold())

                        Text("Cuando hagas tu primer pedido aparecerá aquí.")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(history) { order in
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
                                    .foregroundColor(.primary)

                                HStack {
                                    Text(order.recess)
                                        .font(.caption)
                                        .padding(6)
                                        .background(Color.accentColor.opacity(0.12))
                                        .cornerRadius(8)

                                    Spacer()

                                    Text("$\(order.total, specifier: "%.2f")")
                                        .bold()
                                }

                                NavigationLink(destination: ClaimView(order: order)) {
                                    Text("¿Problemas con el pedido?")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                .padding(.top, 4)
                            }
                            .padding(.vertical, 6)
                        }
                        .onDelete { offsets in
                            history.remove(atOffsets: offsets)
                            guardarEnTelefono(users: users, cards: cards, history: history)
                        }

                        if !history.isEmpty {
                            Button("Borrar todo el historial") {
                                history.removeAll()
                                guardarEnTelefono(users: users, cards: cards, history: history)
                            }
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("Mis Pedidos")
        }
    }
}

// MARK: - QUEJAS
struct ClaimView: View {
    let order: PastOrder
    @State private var text = ""
    @State private var sent = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section("Detalles") {
                Text(order.items)
            }

            Section("¿Qué pasó?") {
                TextEditor(text: $text)
                    .frame(height: 100)
            }

            Button("Enviar Reporte") {
                sent = true
            }
            .disabled(text.isEmpty)
        }
        .navigationTitle("Reporte")
        .fullScreenCover(isPresented: $sent) {
            VStack(spacing: 20) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)

                Text("Reporte Enviado")
                    .font(.title)
                    .bold()

                Button("Entendido") {
                    sent = false
                    dismiss()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
    }
}

// MARK: - AJUSTES
struct SettingsView: View {
    @Binding var users: [UserProfile]
    @Binding var cards: [CreditCard]
    @Binding var history: [PastOrder]
    @Binding var loggedEmail: String?

    @State private var nName = ""
    @State private var nGrade = ""
    @State private var nEmail = ""

    @State private var cName = ""
    @State private var cNum = ""
    @State private var cExp = ""
    @State private var cCvv = ""

    @State private var emailError = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuración de cuenta") {
                    HStack {
                        Image(systemName: "envelope.badge.fill")
                            .foregroundColor(.accentColor)
                        Text(loggedEmail ?? "Sin sesión")
                            .font(.subheadline)
                    }

                    Button("Cerrar sesión") {
                        cerrarSesionLocal()
                        loggedEmail = nil
                    }
                    .foregroundColor(.red)
                }

                Section("Usuarios / Estudiantes") {
                    ForEach(users) { user in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(user.name) (\(user.grade))")
                                    .font(.headline)
                                Spacer()
                                Button(action: {
                                    users.removeAll(where: { $0.id == user.id })
                                    guardarEnTelefono(users: users, cards: cards, history: history)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }

                            if !user.email.isEmpty {
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if !user.accountCode.isEmpty {
                                Text("Cuenta: \(user.accountCode)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text("Fondos: $\(user.accountFunds)")
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)
                        }
                        .padding(.vertical, 4)
                    }

                    DisclosureGroup("Añadir Usuario") {
                        TextField("Nombre", text: $nName)
                        TextField("Grado", text: $nGrade)

                        TextField("Correo institucional", text: $nEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        if !emailError.isEmpty {
                            Text(emailError)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Button("Guardar") {
                            let cleanEmail = normalizarCorreo(nEmail)

                            guard correoWaldenValido(cleanEmail) else {
                                emailError = "El estudiante debe usar correo @waldendos.edu.mx"
                                return
                            }

                            emailError = ""

                            users.append(
                                UserProfile(
                                    name: nName,
                                    age: 15,
                                    grade: nGrade,
                                    email: cleanEmail,
                                    accountCode: generarCodigoCuenta(),
                                    accountFunds: generarFondosAleatorios()
                                )
                            )

                            guardarEnTelefono(users: users, cards: cards, history: history)
                            nName = ""
                            nGrade = ""
                            nEmail = ""
                        }
                        .disabled(nName.isEmpty || nGrade.isEmpty || nEmail.isEmpty)
                    }
                }

                Section("Tarjetas") {
                    ForEach(cards) { card in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("**** \(card.lastFour)")
                                Text(card.holderName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button(action: {
                                cards.removeAll(where: { $0.id == card.id })
                                guardarEnTelefono(users: users, cards: cards, history: history)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }

                    DisclosureGroup("Añadir Tarjeta") {
                        TextField("Titular", text: $cName)
                        TextField("Número", text: $cNum)
                            .keyboardType(.numberPad)

                        HStack {
                            TextField("MM/AA", text: $cExp)
                            TextField("CVV", text: $cCvv)
                                .keyboardType(.numberPad)
                        }

                        Button("Guardar") {
                            cards.append(CreditCard(holderName: cName, lastFour: String(cNum.suffix(4)), expiry: cExp))
                            guardarEnTelefono(users: users, cards: cards, history: history)
                            cName = ""
                            cNum = ""
                            cExp = ""
                            cCvv = ""
                        }
                        .disabled(cNum.count < 15)
                    }
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}

// MARK: - CUENTA
struct AccountView: View {
    @Binding var users: [UserProfile]
    @Binding var cards: [CreditCard]
    @Binding var history: [PastOrder]
    @Binding var loggedEmail: String?

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
                                Text(loggedEmail ?? "Sin correo")
                                    .font(.headline)

                                Text("Acceso válido para Walden Dos")
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
                        Text("Fondos de la cuenta")
                            .font(.title3.bold())

                        if users.isEmpty {
                            Text("No hay cuentas de estudiantes registradas.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(users.indices, id: \.self) { index in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(users[index].name)
                                                .font(.headline)

                                            Text(users[index].grade)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        Spacer()

                                        Text("$\(users[index].accountFunds)")
                                            .font(.headline.bold())
                                            .foregroundColor(.accentColor)
                                    }

                                    if !users[index].email.isEmpty {
                                        Text(users[index].email)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    if !users[index].accountCode.isEmpty {
                                        Text("Cuenta: \(users[index].accountCode)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Button("Fondos de la cuenta") {
                                        users[index].accountFunds = generarFondosAleatorios()

                                        if users[index].accountCode.isEmpty {
                                            users[index].accountCode = generarCodigoCuenta()
                                        }

                                        guardarEnTelefono(users: users, cards: cards, history: history)
                                    }
                                    .font(.subheadline.bold())
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
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
