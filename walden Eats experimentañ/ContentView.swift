import SwiftUI
import UIKit
import Combine
import UserNotifications
import FirebaseCore
import FirebaseFirestore
import CryptoKit

// MARK: - FIREBASE APP DELEGATE
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        configureNotifications(application: application)
        return true
    }

    private func configureNotifications(application: UIApplication) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ Error pidiendo permisos de notificación: \(error.localizedDescription)")
            } else {
                print("✅ Permisos de notificación: \(granted)")
            }
        }

        DispatchQueue.main.async {
            application.registerForRemoteNotifications()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
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
    var status: String
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

func minutosDelDia(_ date: Date = Date()) -> Int {
    let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
}

func sePuedePedir(recess: String, en date: Date = Date()) -> Bool {
    let nowMinutes = minutosDelDia(date)
    let inicio = 5 * 60 // 5:00 AM

    switch recess {
    case "1er Receso":
        let cierre = (9 * 60) + 15 // 9:15 AM
        return nowMinutes >= inicio && nowMinutes < cierre

    case "2do Receso":
        let cierre = (12 * 60) + 5 // 12:05 PM
        return nowMinutes >= inicio && nowMinutes < cierre

    default:
        return false
    }
}

func recesosDisponiblesHoy(en date: Date = Date()) -> [String] {
    ["1er Receso", "2do Receso"].filter { sePuedePedir(recess: $0, en: date) }
}

func mensajeHorarioPedidos(en date: Date = Date()) -> String {
    if sePuedePedir(recess: "1er Receso", en: date) && sePuedePedir(recess: "2do Receso", en: date) {
        return "Puedes pedir para 1er y 2do receso."
    } else if sePuedePedir(recess: "1er Receso", en: date) {
        return "Solo puedes pedir para 1er receso hasta las 9:14 AM."
    } else if sePuedePedir(recess: "2do Receso", en: date) {
        return "Solo puedes pedir para 2do receso hasta las 12:04 PM."
    } else {
        return "Fuera de horario. El 1er receso se pide de 5:00 AM a 9:14 AM y el 2do de 5:00 AM a 12:04 PM."
    }
}

func fechaPedidoTexto(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "es_MX")
    formatter.dateFormat = "d/MMMM/yy"
    return formatter.string(from: date).lowercased()
}

func estadoPedidoLegible(_ status: String) -> String {
    switch status.lowercased() {
    case "pendiente":
        return "Pendiente"
    case "en preparación", "en preparacion":
        return "En preparación"
    case "listo", "listo para recoger":
        return "Listo para recoger"
    case "entregado":
        return "Entregado"
    default:
        return status.capitalized
    }
}

func colorEstado(_ status: String) -> Color {
    switch status.lowercased() {
    case "pendiente":
        return .orange
    case "en preparación", "en preparacion":
        return .blue
    case "listo", "listo para recoger":
        return .green
    case "entregado":
        return .gray
    default:
        return .accentColor
    }
}

func yaNotificadoPedido(_ orderID: String) -> Bool {
    let ids = UserDefaults.standard.stringArray(forKey: "WaldenNotifiedReadyOrders") ?? []
    return ids.contains(orderID)
}

func marcarPedidoComoNotificado(_ orderID: String) {
    var ids = UserDefaults.standard.stringArray(forKey: "WaldenNotifiedReadyOrders") ?? []
    if !ids.contains(orderID) {
        ids.append(orderID)
        UserDefaults.standard.set(ids, forKey: "WaldenNotifiedReadyOrders")
    }
}

func mandarNotificacionPedidoListo(orderID: String, userName: String) {
    let content = UNMutableNotificationContent()
    content.title = "Pedido listo para recoger"
    content.body = "Tu pedido #\(orderID) de \(userName) ya está listo para recoger."
    content.sound = .default

    let request = UNNotificationRequest(
        identifier: "pedido-listo-\(orderID)",
        content: content,
        trigger: nil
    )

    UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
            print("❌ Error enviando notificación local: \(error.localizedDescription)")
        } else {
            print("✅ Notificación local enviada para pedido \(orderID)")
        }
    }
}

// MARK: - PASSWORD SECURITY
func generarSalt() -> String {
    UUID().uuidString.replacingOccurrences(of: "-", with: "")
}

func hashPassword(_ password: String, salt: String) -> String {
    let input = salt + password
    let digest = SHA256.hash(data: Data(input.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

func passwordFuerte(_ password: String) -> Bool {
    password.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8
}

// MARK: - FIREBASE SERVICE
final class FirebaseWalletService: ObservableObject {
    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var ordersListener: ListenerRegistration?

    deinit {
        listeners.forEach { $0.remove() }
        ordersListener?.remove()
    }

    func stopListeners() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        ordersListener?.remove()
        ordersListener = nil
    }

    // MARK: ACCESS USERS
    func createAccessUser(
        email: String,
        password: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let cleanEmail = normalizarCorreo(email)

        guard correoWaldenValido(cleanEmail) else {
            completion(.failure(NSError(
                domain: "FirebaseWalletService",
                code: 2001,
                userInfo: [NSLocalizedDescriptionKey: "Solo se permiten correos institucionales."]
            )))
            return
        }

        guard passwordFuerte(password) else {
            completion(.failure(NSError(
                domain: "FirebaseWalletService",
                code: 2002,
                userInfo: [NSLocalizedDescriptionKey: "La contraseña debe tener mínimo 8 caracteres."]
            )))
            return
        }

        let ref = db.collection("accessUsers").document(cleanEmail)

        ref.getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if snapshot?.exists == true {
                completion(.failure(NSError(
                    domain: "FirebaseWalletService",
                    code: 2003,
                    userInfo: [NSLocalizedDescriptionKey: "Ese correo ya tiene cuenta creada."]
                )))
                return
            }

            let salt = generarSalt()
            let hash = hashPassword(password, salt: salt)

            ref.setData([
                "email": cleanEmail,
                "passwordSalt": salt,
                "passwordHash": hash,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ]) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    print("✅ Cuenta de acceso creada: \(cleanEmail)")
                    completion(.success(()))
                }
            }
        }
    }

    func verifyAccessUser(
        email: String,
        password: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let cleanEmail = normalizarCorreo(email)
        let ref = db.collection("accessUsers").document(cleanEmail)

        ref.getDocument { snapshot, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = snapshot?.data(), snapshot?.exists == true else {
                completion(.failure(NSError(
                    domain: "FirebaseWalletService",
                    code: 2004,
                    userInfo: [NSLocalizedDescriptionKey: "No existe una cuenta para ese correo."]
                )))
                return
            }

            let salt = data["passwordSalt"] as? String ?? ""
            let savedHash = data["passwordHash"] as? String ?? ""

            guard !salt.isEmpty, !savedHash.isEmpty else {
                completion(.failure(NSError(
                    domain: "FirebaseWalletService",
                    code: 2005,
                    userInfo: [NSLocalizedDescriptionKey: "La cuenta no tiene contraseña válida registrada."]
                )))
                return
            }

            let incomingHash = hashPassword(password, salt: salt)

            if incomingHash == savedHash {
                completion(.success(()))
            } else {
                completion(.failure(NSError(
                    domain: "FirebaseWalletService",
                    code: 2006,
                    userInfo: [NSLocalizedDescriptionKey: "Contraseña incorrecta."]
                )))
            }
        }
    }

    func updatePassword(
        email: String,
        currentPassword: String,
        newPassword: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let cleanEmail = normalizarCorreo(email)

        guard passwordFuerte(newPassword) else {
            completion(.failure(NSError(
                domain: "FirebaseWalletService",
                code: 2007,
                userInfo: [NSLocalizedDescriptionKey: "La nueva contraseña debe tener mínimo 8 caracteres."]
            )))
            return
        }

        verifyAccessUser(email: cleanEmail, password: currentPassword) { [weak self] result in
            switch result {
            case .success:
                guard let self else { return }
                let newSalt = generarSalt()
                let newHash = hashPassword(newPassword, salt: newSalt)

                self.db.collection("accessUsers").document(cleanEmail).setData([
                    "passwordSalt": newSalt,
                    "passwordHash": newHash,
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true) { error in
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: WALLET DATA
    func syncUsersBalances(appVM: AppViewModel) {
        listeners.forEach { $0.remove() }
        listeners.removeAll()

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

    func listenOrders(for email: String, appVM: AppViewModel) {
        ordersListener?.remove()
        let cleanEmail = normalizarCorreo(email)

        ordersListener = db.collection("pedidos")
            .whereField("email", isEqualTo: cleanEmail)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ Error escuchando pedidos del usuario: \(error.localizedDescription)")
                    return
                }

                guard let documents = snapshot?.documents else { return }

                DispatchQueue.main.async {
                    for doc in documents {
                        let data = doc.data()
                        let orderID = data["orderID"] as? String ?? doc.documentID
                        let userName = data["userName"] as? String ?? "Alumno"
                        let items = data["items"] as? String ?? ""
                        let total = data["total"] as? Double ?? (data["total"] as? NSNumber)?.doubleValue ?? 0.0
                        let recess = data["recess"] as? String ?? "1er Receso"
                        let status = data["status"] as? String ?? "pendiente"
                        let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? Date()

                        if let index = appVM.history.firstIndex(where: { $0.orderID == orderID }) {
                            appVM.history[index].status = status
                        } else {
                            let newOrder = PastOrder(
                                orderID: orderID,
                                date: timestamp,
                                userName: userName,
                                items: items,
                                total: total,
                                recess: recess,
                                status: status
                            )
                            appVM.history.insert(newOrder, at: 0)
                        }

                        if status.lowercased() == "listo" || status.lowercased() == "listo para recoger" {
                            if !yaNotificadoPedido(orderID) {
                                mandarNotificacionPedidoListo(orderID: orderID, userName: userName)
                                marcarPedidoComoNotificado(orderID)
                            }
                        }
                    }

                    appVM.history.sort { $0.date > $1.date }
                    appVM.persist()
                }
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
            "status": "pendiente",
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
    @Published var isAuthenticating = false

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

        if let email = loggedEmail, !email.isEmpty {
            firebase.listenOrders(for: email, appVM: self)
        }
    }

    func stopServerSync() {
        firebase.stopListeners()
    }

    func login(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let cleanEmail = normalizarCorreo(email)

        guard correoWaldenValido(cleanEmail) else {
            completion(.failure(NSError(
                domain: "AppViewModel",
                code: 3001,
                userInfo: [NSLocalizedDescriptionKey: "Solo se permiten correos con dominio @waldendos.edu.mx"]
            )))
            return
        }

        guard !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(NSError(
                domain: "AppViewModel",
                code: 3002,
                userInfo: [NSLocalizedDescriptionKey: "Ingresa una contraseña."]
            )))
            return
        }

        isAuthenticating = true

        firebase.verifyAccessUser(email: cleanEmail, password: password) { [weak self] result in
            DispatchQueue.main.async {
                self?.isAuthenticating = false

                switch result {
                case .success:
                    guardarSesion(email: cleanEmail)
                    self?.loggedEmail = cleanEmail
                    self?.startServerSync()
                    completion(.success(()))

                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func registerAccess(email: String, password: String, completion: @escaping (Result<Void, Error>) -> Void) {
        isAuthenticating = true
        firebase.createAccessUser(email: email, password: password) { [weak self] result in
            DispatchQueue.main.async {
                self?.isAuthenticating = false
                completion(result)
            }
        }
    }

    func changePassword(currentPassword: String, newPassword: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let email = loggedEmail else {
            completion(.failure(NSError(
                domain: "AppViewModel",
                code: 3003,
                userInfo: [NSLocalizedDescriptionKey: "No hay sesión activa."]
            )))
            return
        }

        firebase.updatePassword(email: email, currentPassword: currentPassword, newPassword: newPassword) { result in
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func logout() {
        cerrarSesionLocal()
        loggedEmail = nil
        stopServerSync()
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
    @State private var showRegister = false

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

                            Text("Correo institucional y contraseña verificada con Firebase")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
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
                                login()
                            } label: {
                                HStack {
                                    Spacer()
                                    if appVM.isAuthenticating {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text("Entrar")
                                            .font(.headline.bold())
                                    }
                                    Spacer()
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                            }
                            .disabled(appVM.isAuthenticating)

                            Button("Crear cuenta") {
                                showRegister = true
                            }
                            .disabled(appVM.isAuthenticating)
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
            .sheet(isPresented: $showRegister) {
                RegisterAccessView()
            }
        }
    }

    private func login() {
        errorText = ""
        appVM.login(email: email, password: password) { result in
            switch result {
            case .success:
                errorText = ""
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
    }
}

// MARK: - REGISTER ACCESS
struct RegisterAccessView: View {
    @EnvironmentObject var appVM: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorText = ""
    @State private var successText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Crear cuenta de acceso") {
                    TextField("correo@waldendos.edu.mx", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Contraseña", text: $password)
                    SecureField("Confirmar contraseña", text: $confirmPassword)

                    Text("Mínimo 8 caracteres.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !errorText.isEmpty {
                        Text(errorText)
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    if !successText.isEmpty {
                        Text(successText)
                            .foregroundColor(.green)
                            .font(.caption)
                    }

                    Button {
                        register()
                    } label: {
                        HStack {
                            Spacer()
                            if appVM.isAuthenticating {
                                ProgressView()
                            } else {
                                Text("Crear cuenta").bold()
                            }
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Registro")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func register() {
        errorText = ""
        successText = ""

        guard password == confirmPassword else {
            errorText = "Las contraseñas no coinciden."
            return
        }

        appVM.registerAccess(email: email, password: password) { result in
            switch result {
            case .success:
                successText = "Cuenta creada correctamente."
                password = ""
                confirmPassword = ""
            case .failure(let error):
                errorText = error.localizedDescription
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
                                Text(recesosDisponiblesHoy().isEmpty ? "Fuera de horario" : "Enviar pedido")
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
                        .background(recesosDisponiblesHoy().isEmpty ? Color.gray : Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .padding()
                    }
                    .disabled(recesosDisponiblesHoy().isEmpty)
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

                    Text("Tarjeta manual, saldo en servidor y login verificado")
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

    var recesosDisponibles: [String] {
        recesosDisponiblesHoy()
    }

    var puedeConfirmarPedido: Bool {
        !recesosDisponibles.isEmpty && sePuedePedir(recess: selectedRecess)
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
                    if recesosDisponibles.isEmpty {
                        Text("Fuera de horario de pedidos.")
                            .foregroundColor(.red)
                            .font(.headline)

                        Text("1er Receso (10:00): de 5:00 AM a 9:14 AM")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("2do Receso (12:50): de 5:00 AM a 12:04 PM")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Picker("Receso", selection: $selectedRecess) {
                            ForEach(recesosDisponibles, id: \.self) { recess in
                                Text(recess).tag(recess)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(mensajeHorarioPedidos())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                    .disabled(isProcessing || appVM.users.isEmpty || appVM.cart.isEmpty || !puedeConfirmarPedido)
                    .foregroundColor(.accentColor)
                }
            }
        }
        .onAppear {
            if let primero = recesosDisponibles.first {
                selectedRecess = primero
            }
        }
        .onChange(of: recesosDisponibles) { _, nuevos in
            if !nuevos.contains(selectedRecess), let primero = nuevos.first {
                selectedRecess = primero
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

                Text("El pedido se guardó como pendiente. Cuando Gourmet lo marque como listo, aquí se actualizará y te llegará un aviso.")
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

        guard sePuedePedir(recess: selectedRecess) else {
            paymentError = "Ya no está disponible el horario para \(selectedRecess)."
            return
        }

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
                                    Text(fechaPedidoTexto(order.date))
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

                                    Text(estadoPedidoLegible(order.status))
                                        .font(.caption.bold())
                                        .padding(6)
                                        .background(colorEstado(order.status).opacity(0.12))
                                        .foregroundColor(colorEstado(order.status))
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

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""
    @State private var passwordError = ""
    @State private var passwordSuccess = ""

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
                        appVM.logout()
                    }
                    .foregroundColor(.red)
                }

                Section("Cambiar contraseña") {
                    SecureField("Contraseña actual", text: $currentPassword)
                    SecureField("Nueva contraseña", text: $newPassword)
                    SecureField("Confirmar nueva contraseña", text: $confirmNewPassword)

                    Text("La nueva contraseña debe tener mínimo 8 caracteres.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !passwordError.isEmpty {
                        Text(passwordError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    if !passwordSuccess.isEmpty {
                        Text(passwordSuccess)
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    Button("Actualizar contraseña") {
                        updatePassword()
                    }
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

    private func updatePassword() {
        passwordError = ""
        passwordSuccess = ""

        guard newPassword == confirmNewPassword else {
            passwordError = "Las nuevas contraseñas no coinciden."
            return
        }

        appVM.changePassword(currentPassword: currentPassword, newPassword: newPassword) { result in
            switch result {
            case .success:
                passwordSuccess = "Contraseña actualizada correctamente."
                currentPassword = ""
                newPassword = ""
                confirmNewPassword = ""

            case .failure(let error):
                passwordError = error.localizedDescription
            }
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
