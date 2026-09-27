import SwiftUI
import PalmyCore

@main struct PalmyApp: App {
    @StateObject private var model: AppModel
    init() {
        #if DEBUG
        let endpoint = "http://127.0.0.1:8100/api/v1"
        #else
        let endpoint = Bundle.main.object(forInfoDictionaryKey: "PalmyAPIURL") as? String ?? ""
        #endif
        _model = StateObject(wrappedValue: AppModel(apiFactory: {
            guard let url = URL(string: endpoint) else { throw APIError(status: 0, message: "Layanan belum dikonfigurasi.") }
            return try API(baseURL: url)
        }))
    }
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .tint(PalmyTheme.primary)
                .preferredColorScheme(.light)
                .overlay { if phase != .active { PalmyTheme.canvas.ignoresSafeArea().overlay(Text("Palmy").font(.largeTitle.bold()).foregroundStyle(PalmyTheme.primary)) } }
                .onChange(of: phase) { _, phase in if phase == .background { model.didEnterBackground() } }
        }
    }
}

enum PalmyTheme {
    static let canvas = Color(red: 245/255, green: 247/255, blue: 242/255)
    static let primary = Color(red: 33/255, green: 78/255, blue: 59/255)
    static let soft = Color(red: 229/255, green: 237/255, blue: 229/255)
    static let accent = Color(red: 214/255, green: 240/255, blue: 120/255)
    static let ink = Color(red: 21/255, green: 41/255, blue: 31/255)
}


struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var tab = 0
    var body: some View {
        Group {
            if model.identity == nil { WelcomeView(model: model) }
            else {
                TabView(selection: $tab) {
                    DashboardView(model: model).tabItem { Label("Beranda", systemImage: "house") }.tag(0)
                    FinanceView(model: model).tabItem { Label("Keuangan", systemImage: "creditcard") }.tag(1)
                    ProfileView(model: model).tabItem { Label("Profil", systemImage: "person.crop.circle") }.tag(2)
                }
            }
        }
        .foregroundStyle(PalmyTheme.ink)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                if model.busy { ProgressView("Memuat…").frame(maxWidth: .infinity).padding(8).background(.white) }
                if !model.message.isEmpty { Text(model.message).font(.footnote).foregroundStyle(model.isError ? .red : PalmyTheme.primary).frame(maxWidth: .infinity).padding(10).background(PalmyTheme.soft) }
            }
        }
    }
}

struct WelcomeView: View {
    @ObservedObject var model: AppModel
    @State private var recovery = ""
    @State private var recoverMode = false
    @State private var acknowledged = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Palmy").font(.largeTitle.bold()).foregroundStyle(PalmyTheme.primary)
                    Text("Ruang tenang untuk keuangan Anda").font(.title2.bold())
                    Text("Profil dienkripsi di perangkat. Data keuangan tetap dapat dibaca layanan. Hindari informasi pribadi dalam nama dompet dan catatan.").font(.callout)
                }.listRowBackground(PalmyTheme.soft)
                if let pending = model.pendingIdentity {
                    Section("Simpan kunci pemulihan") {
                        Text("Kunci ini memberi akses penuh. Palmy tidak dapat memulihkannya. Simpan di pengelola kata sandi sebelum melanjutkan.")
                        Text(pending.recovery).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).privacySensitive()
                        Toggle("Saya sudah menyimpan kunci dengan aman", isOn: $acknowledged).accessibilityIdentifier("onboarding.recoveryAcknowledged")
                        Button("Buat akun & buka") { model.create() }.disabled(!acknowledged || model.busy).accessibilityIdentifier("onboarding.create")
                        Button("Kembali") { model.cancelPrepare(); acknowledged = false }.disabled(model.busy)
                    }
                } else {
                    Section {
                        Picker("Akses", selection: $recoverMode) { Text("Buat akun").tag(false); Text("Pulihkan").tag(true) }.pickerStyle(.segmented)
                        if recoverMode {
                            SecureField("Kunci pemulihan", text: $recovery).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                            Button("Buka akun") { let value = recovery; recovery = ""; model.recover(value) }.disabled(recovery.isEmpty || model.busy)
                        } else {
                            TextField("Nama panggilan", text: $model.profile.display_name).textContentType(.name).privacySensitive().accessibilityIdentifier("onboarding.name")
                            TextField("Email (opsional)", text: $model.profile.email).textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled().privacySensitive()
                            Text("Email hanya tersimpan terenkripsi; bukan sarana login atau pemulihan.").font(.footnote)
                            Button("Siapkan akun pribadi") { model.prepare() }.disabled(model.profile.display_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy).accessibilityIdentifier("onboarding.prepare")
                        }
                    }
                }
                Section { Text("Kunci dan sesi hanya berada di memori. Berpindah aplikasi mengunci Palmy; gunakan kunci pemulihan untuk masuk lagi.").font(.footnote) }
            }.scrollContentBackground(.hidden).background(PalmyTheme.canvas).navigationTitle("Selamat datang")
        }
    }
}

struct DashboardView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Halo, \(model.profile.display_name)").font(.title2.bold()).privacySensitive().accessibilityIdentifier("dashboard.greeting")
                    Text("Keuangan yang lebih terarah, mulai hari ini.")
                }.listRowBackground(PalmyTheme.soft)
                if let summary = model.summary {
                    Section("Saldo seluruh dompet") {
                        Text(Money.display(summary.balance)).font(.largeTitle.bold()).foregroundStyle(PalmyTheme.primary)
                        LabeledContent("Pemasukan sepanjang waktu", value: Money.display(summary.income))
                        LabeledContent("Pengeluaran sepanjang waktu", value: Money.display(summary.expense))
                    }
                }
                Section("Dompet") {
                    if model.wallets.isEmpty { Text("Belum ada dompet. Buat dompet pertama di Keuangan.") }
                    ForEach(model.wallets) { wallet in LabeledContent(wallet.name, value: Money.display(wallet.balance)) }
                }
                Section("Transaksi terbaru") { EntryRows(entries: Array(model.entries.prefix(5))) }
                Button("Muat ulang") { model.run { try await model.refresh() } }.disabled(model.busy)
            }.scrollContentBackground(.hidden).background(PalmyTheme.canvas).navigationTitle("Beranda")
                .refreshable { model.run { try await model.refresh() } }
        }
    }
}

struct EntryRows: View {
    let entries: [FinanceEntry]
    var body: some View {
        if entries.isEmpty { Text("Belum ada transaksi.").foregroundStyle(.secondary) }
        ForEach(entries) { entry in
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text(entry.category).font(.headline); Text(entry.description.isEmpty ? entry.effective_on : "\(entry.description) · \(entry.effective_on)").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Text("\(entry.kind == "income" ? "+" : "−")\(Money.display(entry.amount))").foregroundStyle(entry.kind == "income" ? PalmyTheme.primary : PalmyTheme.ink).font(.subheadline.weight(.semibold))
            }.padding(.vertical, 4)
        }
    }
}

struct FinanceView: View {
    @ObservedObject var model: AppModel
    @State private var walletName = ""
    @State private var walletID = ""
    @State private var kind = "expense"
    @State private var amount = ""
    @State private var category = ""
    @State private var note = ""
    @State private var date = Date()
    var dateString: String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Asia/Jakarta"); return f.string(from: date) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Dompet baru") {
                    TextField("Nama dompet (tanpa identitas pribadi)", text: $walletName)
                    Button("Tambah dompet") { model.wallet(walletName) }.disabled(walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || walletName.count > 80 || model.busy)
                }
                Section("Catat transaksi") {
                    Text("Nominal, kategori, dan catatan dapat dibaca layanan. Jangan isi nama orang, email, atau nomor rekening.").font(.footnote)
                    Picker("Dompet", selection: $walletID) { Text("Pilih dompet").tag(""); ForEach(model.wallets) { Text($0.name).tag($0.id) } }
                    Picker("Jenis", selection: $kind) { Text("Pengeluaran").tag("expense"); Text("Pemasukan").tag("income") }.pickerStyle(.segmented)
                    TextField("Nominal IDR, misalnya 1234.56", text: $amount).keyboardType(.decimalPad)
                    TextField("Kategori", text: $category)
                    TextField("Catatan (opsional)", text: $note, axis: .vertical)
                    DatePicker("Tanggal Jakarta", selection: $date, displayedComponents: .date).environment(\.timeZone, TimeZone(identifier: "Asia/Jakarta")!)
                    Button("Simpan transaksi") {
                        model.post(TransactionInput(wallet_id: walletID, kind: kind, amount: amount, category: category, description: note, effective_on: dateString))
                    }.disabled(walletID.isEmpty || !Money.validPositive(amount) || category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || category.count > 60 || note.count > 280 || model.busy)
                    if !amount.isEmpty && !Money.validPositive(amount) { Text("Gunakan angka positif dengan titik desimal, maksimal 2 digit desimal.").font(.caption).foregroundStyle(.red) }
                }
                Section("Riwayat transaksi") { EntryRows(entries: model.entries); if model.cursor != nil { Button("Muat lebih banyak") { model.more() }.disabled(model.busy) } }
            }.scrollContentBackground(.hidden).background(PalmyTheme.canvas).navigationTitle("Keuangan")
                .onChange(of: model.savedWallet) { _, _ in walletName = "" }
                .onChange(of: model.savedEntry) { _, _ in amount = ""; category = ""; note = "" }
        }
    }
}

struct ProfileView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        NavigationStack {
            Form {
                Section("Profil pribadi") {
                    Label("Dienkripsi sebelum dikirim", systemImage: "lock.shield").foregroundStyle(PalmyTheme.primary)
                    TextField("Nama panggilan", text: $model.profile.display_name).privacySensitive()
                    TextField("Email (opsional)", text: $model.profile.email).textInputAutocapitalization(.never).keyboardType(.emailAddress).autocorrectionDisabled().privacySensitive()
                    Button("Simpan profil terenkripsi") { model.saveProfile() }.disabled(model.busy || model.profile.display_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Muat profil terbaru") { model.reloadProfile() }.disabled(model.busy)
                }
                Section("Privasi") { Text("Palmy menyimpan profil sebagai ciphertext. Data keuangan tetap terbaca dan dapat memberi petunjuk tentang pemiliknya. Ini bukan jaminan anonimitas.") }
                Section { Button("Kunci & cabut sesi", role: .destructive) { model.lock() } }
            }.scrollContentBackground(.hidden).background(PalmyTheme.canvas).navigationTitle("Profil")
        }
    }
}
