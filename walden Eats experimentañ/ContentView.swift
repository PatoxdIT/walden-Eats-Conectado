import SwiftUI
import Combine
import FirebaseCore
import FirebaseFirestore // <-- NUEVO: Importamos la base de datos

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

// MARK: - FUNCIÓN DE GUARDADO DIRECTO LOCAL
func guardarEnTelefono(users: [UserProfile], cards: [CreditCard], history: [PastOrder]) {
    if let encoded = try? JSONEncoder().encode(users) { UserDefaults.standard.set(encoded, forKey: "WaldenData") }
    if let encoded = try? JSONEncoder().encode(cards) { UserDefaults.standard.set(encoded, forKey: "WaldenCards") }
    if let encoded = try? JSONEncoder().encode(history) { UserDefaults.standard.set(encoded, forKey: "WaldenHistory") }
}

func agruparItems(_ items: [FoodItem]) -> String {
    let dict = Dictionary(grouping: items, by: { $0.name })
    let contados = dict.map { "\($0.value.count)x \($0.key)" }
    return contados.sorted().joined(separator: ", ")
}

// MARK: - PUNTO DE ENTRADA
@main
struct WaldenEatsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    @StateObject var store = UserStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store)
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
    
    var body: some View {
        ZStack {
            if showSplash {
                SplashScreenView(isActive: $showSplash)
                    .transition(.opacity)
            } else {
                TabView {
                    MenuView(cart: $cart, users: $users, cards: $cards, history: $history)
                        .tabItem { Label("Menú", systemImage: "fork.knife") }
                    
                    HistoryView(history: $history, users: $users, cards: $cards)
                        .tabItem { Label("Mis Pedidos", systemImage: "clock.fill") }
                    
                    SettingsView(users: $users, cards: $cards, history: $history)
                        .tabItem { Label("Ajustes", systemImage: "person.crop.circle.fill") }
                }
            }
        }
        .onAppear {
            if let data = UserDefaults.standard.data(forKey: "WaldenData"), let decoded = try? JSONDecoder().decode([UserProfile].self, from: data) { users = decoded }
            if let data = UserDefaults.standard.data(forKey: "WaldenCards"), let decoded = try? JSONDecoder().decode([CreditCard].self, from: data) { cards = decoded }
            if let data = UserDefaults.standard.data(forKey: "WaldenHistory"), let decoded = try? JSONDecoder().decode([PastOrder].self, from: data) { history = decoded }
        }
    }
}

// MARK: - ANIMACIÓN DE INICIO
struct SplashScreenView: View {
    @Binding var isActive: Bool
    @State private var textScale: CGFloat = 0.8
    @State private var textOpacity: Double = 0.0
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Walden Eats").font(.system(size: 48, weight: .bold, design: .rounded)).foregroundColor(.accentColor).scaleEffect(textScale).opacity(textOpacity)
                Text("Pide, Paga y disfruta").font(.subheadline).foregroundColor(.secondary)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) { textScale = 1.0; textOpacity = 1.0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { isActive = false } }
        }
    }
}

// MARK: - MENÚ
struct MenuView: View {
    @Binding var cart: [FoodItem]
    @Binding var users: [UserProfile]
    @Binding var cards: [CreditCard]
    @Binding var history: [PastOrder]
    
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
            VStack(spacing: 0) {
                Text("¡Comida rica y nutritiva para tu día! 🌟")
                    .font(.headline).bold().foregroundColor(.white).multilineTextAlignment(.center)
                    .padding(.vertical, 24).frame(maxWidth: .infinity).background(Color.accentColor).cornerRadius(12)
                    .padding(.horizontal).padding(.top, 10).padding(.bottom, 20)
                
                List {
                    let categories = ["⭐ Especialidad por Día", "🌮 Platos", "🍉 Snacks y Fruta", "💧 Bebidas"]
                    ForEach(categories, id: \.self) { cat in
                        Section {
                            DisclosureGroup {
                                ForEach(menu.filter { $0.category == cat }) { item in
                                    let quantity = cart.filter { $0.name == item.name }.count
                                    let isAvailable = (cat != "⭐ Especialidad por Día" || item.dayOfWeek == currentDay)
                                    
                                    HStack {
                                        Text(item.icon).font(.title2)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.name).font(.title3).fontWeight(.medium)
                                                .foregroundColor(isAvailable ? .primary : .gray)
                                                .strikethrough(!isAvailable, color: .red)
                                            Text("$\(item.price, specifier: "%.2f")").font(.subheadline).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        
                                        if isAvailable {
                                            if quantity == 0 {
                                                Button(action: { cart.append(item) }) {
                                                    Image(systemName: "plus.circle.fill").font(.system(size: 30)).foregroundColor(.green)
                                                }.buttonStyle(BorderlessButtonStyle())
                                            } else {
                                                HStack(spacing: 15) {
                                                    Button(action: {
                                                        if let index = cart.lastIndex(where: { $0.name == item.name }) {
                                                            cart.remove(at: index)
                                                        }
                                                    }) {
                                                        Image(systemName: quantity == 1 ? "trash" : "minus").foregroundColor(.gray).bold()
                                                    }.buttonStyle(BorderlessButtonStyle())
                                                    
                                                    Text("\(quantity)").font(.title3).bold()
                                                    
                                                    Button(action: { cart.append(item) }) {
                                                        Image(systemName: "plus.circle.fill").font(.system(size: 30)).foregroundColor(.black)
                                                    }.buttonStyle(BorderlessButtonStyle())
                                                }
                                                .padding(.horizontal, 12).padding(.vertical, 6)
                                                .background(Color.white).cornerRadius(25)
                                                .overlay(RoundedRectangle(cornerRadius: 25).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                                .shadow(radius: 2)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 10)
                                }
                            } label: {
                                Text(cat).font(.title2).fontWeight(.semibold).padding(.vertical, 10)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                
                if !cart.isEmpty {
                    VStack {
                        NavigationLink(destination: CheckoutView(cart: $cart, users: $users, cards: $cards, history: $history)) {
                            Text("Pagar $\(cart.reduce(0){$0 + $1.price}, specifier: "%.2f")").bold().frame(maxWidth: .infinity).padding().background(Color.accentColor).foregroundColor(.white).cornerRadius(12)
                        }.padding()
                    }.background(Color(UIColor.systemGray6))
                }
            }
            .navigationTitle("Menu a escojer")
        }
    }
}

// MARK: - CHECKOUT (AQUÍ OCURRE LA MAGIA DE FIREBASE)
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
                Text("⚠️ Registra tu perfil y tarjeta en Ajustes").foregroundColor(.red).padding()
            } else {
                Section("Resumen") { Text(agruparItems(cart)).font(.subheadline) }
                Section("Usuario") {
                    Picker("¿Quién eres?", selection: $selUser) {
                        ForEach(0..<users.count, id: \.self) { Text(users[$0].name).tag($0) }
                    }
                }
                Section("Entrega") {
                    Picker("Receso", selection: $selectedRecess) {
                        Text("1er Receso").tag("1er Receso"); Text("2do Receso").tag("2do Receso")
                    }.pickerStyle(.segmented)
                }
                Section("Pago") {
                    Picker("Tarjeta", selection: $selCard) {
                        ForEach(0..<cards.count, id: \.self) { Text("**** \(cards[$0].lastFour)").tag($0) }
                    }
                }
                Button("Confirmar Pedido") {
                    // 1. Generamos el ID del pedido y los datos
                    let id = "\(String("ABCDEFGHIJKLMNOPQRSTUVWXYZ".randomElement()!))\(Int.random(in: 1...99))"
                    let orderString = agruparItems(cart)
                    let totalOrder = cart.reduce(0){$0 + $1.price}
                    
                    // 2. Guardamos localmente para el historial del teléfono
                    let order = PastOrder(orderID: id, date: Date(), userName: users[selUser].name, items: orderString, total: totalOrder, recess: selectedRecess)
                    history.insert(order, at: 0)
                    guardarEnTelefono(users: users, cards: cards, history: history)
                    
                    // 3. ENVÍO A FIREBASE (NUEVO)
                    let db = Firestore.firestore()
                    db.collection("pedidos").document(id).setData([
                        "orderID": id,
                        "userName": users[selUser].name,
                        "items": orderString,
                        "total": totalOrder,
                        "recess": selectedRecess,
                        "timestamp": FieldValue.serverTimestamp(), // Guarda la hora exacta
                        "status": "pendiente" // Esto le dirá a la cafetería que es un pedido nuevo
                    ]) { error in
                        if let error = error {
                            print("Error al guardar en Firebase: \(error.localizedDescription)")
                        } else {
                            print("¡Pedido \(id) enviado a Firebase con éxito!")
                        }
                    }
                    
                    showSuccess = true
                }.bold().frame(maxWidth: .infinity).foregroundColor(.accentColor)
            }
        }
        .fullScreenCover(isPresented: $showSuccess) {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 80)).foregroundColor(.green)
                Text("¡Listo!").font(.largeTitle).bold()
                Text("Tu pedido se ha enviado a la cafetería").foregroundColor(.secondary)
                Button("Volver") { cart.removeAll(); showSuccess = false }.padding().background(Color.accentColor).foregroundColor(.white).cornerRadius(10)
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
            List {
                ForEach(history) { order in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(order.userName).bold()
                            Text("#\(order.orderID ?? "")").foregroundColor(.secondary)
                            Spacer()
                            Text(order.date, style: .date).font(.caption)
                        }
                        Text(order.items).font(.subheadline).foregroundColor(.primary)
                        HStack {
                            Text(order.recess).font(.caption).padding(4).background(Color.accentColor.opacity(0.1)).cornerRadius(5)
                            Spacer()
                            Text("$\(order.total, specifier: "%.2f")").bold()
                        }
                        NavigationLink(destination: ClaimView(order: order)) {
                            Text("¿Problemas con el pedido?").font(.caption).foregroundColor(.red)
                        }.padding(.top, 5)
                    }
                    .padding(.vertical, 5)
                }
                .onDelete { offsets in
                    history.remove(atOffsets: offsets)
                    guardarEnTelefono(users: users, cards: cards, history: history)
                }
                
                if !history.isEmpty {
                    Button("Borrar todo el historial") {
                        history.removeAll()
                        guardarEnTelefono(users: users, cards: cards, history: history)
                    }.foregroundColor(.red).frame(maxWidth: .infinity).padding()
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
            Section("Detalles") { Text(order.items) }
            Section("¿Qué pasó?") { TextEditor(text: $text).frame(height: 100) }
            Button("Enviar Reporte") { sent = true }.disabled(text.isEmpty)
        }
        .fullScreenCover(isPresented: $sent) {
            VStack(spacing: 20) {
                Image(systemName: "paperplane.fill").font(.system(size: 80)).foregroundColor(.blue)
                Text("Reporte Enviado").font(.title).bold()
                Button("Entendido") { sent = false; dismiss() }.padding().background(Color.blue).foregroundColor(.white).cornerRadius(10)
            }
        }
    }
}

// MARK: - AJUSTES
struct SettingsView: View {
    @Binding var users: [UserProfile]
    @Binding var cards: [CreditCard]
    @Binding var history: [PastOrder]
    @State private var nName = ""; @State private var nGrade = ""
    @State private var cName = ""; @State private var cNum = ""; @State private var cExp = ""; @State private var cCvv = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Usuarios") {
                    ForEach(users) { user in
                        HStack {
                            Text("\(user.name) (\(user.grade))")
                            Spacer()
                            Button(action: {
                                users.removeAll(where: {$0.id == user.id})
                                guardarEnTelefono(users: users, cards: cards, history: history)
                            }) { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    DisclosureGroup("Añadir Usuario") {
                        TextField("Nombre", text: $nName)
                        TextField("Grado", text: $nGrade)
                        Button("Guardar") {
                            users.append(UserProfile(name: nName, age: 15, grade: nGrade))
                            guardarEnTelefono(users: users, cards: cards, history: history)
                            nName = ""; nGrade = ""
                        }.disabled(nName.isEmpty)
                    }
                }
                
                Section("Tarjetas") {
                    ForEach(cards) { card in
                        HStack {
                            Text("**** \(card.lastFour)")
                            Spacer()
                            Button(action: {
                                cards.removeAll(where: {$0.id == card.id})
                                guardarEnTelefono(users: users, cards: cards, history: history)
                            }) { Image(systemName: "trash").foregroundColor(.red) }.buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    DisclosureGroup("Añadir Tarjeta") {
                        TextField("Titular", text: $cName)
                        TextField("Número", text: $cNum).keyboardType(.numberPad)
                        HStack {
                            TextField("MM/AA", text: $cExp)
                            TextField("CVV", text: $cCvv).keyboardType(.numberPad)
                        }
                        Button("Guardar") {
                            cards.append(CreditCard(holderName: cName, lastFour: String(cNum.suffix(4)), expiry: cExp))
                            guardarEnTelefono(users: users, cards: cards, history: history)
                            cName = ""; cNum = ""; cExp = ""; cCvv = ""
                        }.disabled(cNum.count < 15)
                    }
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}
