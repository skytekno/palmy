package com.palmy.app

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import java.time.LocalDate
import java.time.ZoneId

private val Canvas = Color(0xFFF5F7F2)
private val Primary = Color(0xFF214E3B)
private val Soft = Color(0xFFE5EDE5)
private val Ink = Color(0xFF15291F)
private val Muted = Color(0xFF68776E)

class MainActivity: ComponentActivity() {
    private val model by viewModels<PalmyModel> {
        viewModelFactory { initializer { (application as PalmyApplication).createModel() } }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        enableEdgeToEdge()
        setContent {
            MaterialTheme(colorScheme = lightColorScheme(primary = Primary, onPrimary = Color.White, primaryContainer = Soft, secondary = Primary, tertiary = Color(0xFFD6F078), background = Canvas, surface = Color.White, onSurface = Ink, onBackground = Ink, outline = Color(0xFFDFE6DF), error = Color(0xFFA63434))) { Palmy(model) }
        }
    }
    override fun onStop() {
        super.onStop()
        // Keep pending onboarding in memory while the user saves recovery in a password manager.
        model.onBackground(isChangingConfigurations)
    }
}

@Composable private fun Palmy(model: PalmyModel) {
    var tab by remember { mutableIntStateOf(0) }
    Scaffold(containerColor = Canvas, bottomBar = {
        if (model.identity != null) NavigationBar(containerColor = Color.White) {
            listOf("Beranda", "Keuangan", "Profil").forEachIndexed { index, name ->
                NavigationBarItem(selected = tab == index, onClick = { tab = index }, icon = { Text(listOf("⌂", "Rp", "○")[index], fontWeight = FontWeight.Bold) }, label = { Text(name) })
            }
        }
    }) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            if (model.busy) { LinearProgressIndicator(Modifier.fillMaxWidth()); Text("Memuat…", Modifier.padding(horizontal = 20.dp), style = MaterialTheme.typography.labelMedium) }
            if (model.message.isNotEmpty()) Text(model.message, Modifier.fillMaxWidth().background(Soft).padding(16.dp), color = if (model.error) MaterialTheme.colorScheme.error else Primary, style = MaterialTheme.typography.bodyMedium)
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                if (model.identity == null) Welcome(model)
                else when (tab) { 0 -> Home(model); 1 -> Finance(model); else -> ProfileScreen(model) }
                Spacer(Modifier.height(16.dp))
            }
        }
    }
}

@Composable private fun CardSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(24.dp), colors = CardDefaults.cardColors(containerColor = Color.White)) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) { Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold); content() }
    }
}
@Composable private fun Field(label: String, value: String, enabled: Boolean = true, keyboard: KeyboardType = KeyboardType.Text, onValue: (String) -> Unit) {
    OutlinedTextField(value = value, onValueChange = onValue, label = { Text(label) }, enabled = enabled, modifier = Modifier.fillMaxWidth(), keyboardOptions = KeyboardOptions(keyboardType = keyboard), shape = RoundedCornerShape(14.dp), singleLine = true)
}
@Composable private fun Heading(title: String, subtitle: String) { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { Text(title, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold, color = Primary); Text(subtitle, color = Muted) } }
@Composable private fun FullButton(label: String, enabled: Boolean = true, action: () -> Unit) { Button(onClick = action, enabled = enabled, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp), shape = RoundedCornerShape(16.dp)) { Text(label) } }

@Composable private fun Welcome(model: PalmyModel) {
    var recoverMode by remember { mutableStateOf(false) }
    var recovery by remember { mutableStateOf("") }
    var acknowledged by remember { mutableStateOf(false) }
    Heading("Palmy", "Ruang tenang untuk keuangan Anda")
    Text("Profil dienkripsi di perangkat. Data keuangan tetap dapat dibaca layanan. Hindari informasi pribadi dalam nama dompet dan catatan.")
    val pending = model.pending
    if (pending != null) CardSection("Simpan kunci pemulihan") {
        Text("Kunci ini memberi akses penuh. Palmy tidak dapat memulihkannya. Simpan di pengelola kata sandi sebelum melanjutkan.")
        SelectionContainer { Text(pending.recovery, style = MaterialTheme.typography.bodySmall) }
        Row(verticalAlignment = Alignment.CenterVertically) { Checkbox(checked = acknowledged, onCheckedChange = { acknowledged = it }); Text("Saya sudah menyimpan kunci dengan aman", Modifier.weight(1f)) }
        FullButton("Buat akun & buka", acknowledged && !model.busy) { model.create() }
        TextButton(onClick = { model.cancelPrepare(); acknowledged = false }, enabled = !model.busy) { Text("Kembali") }
    } else CardSection(if (recoverMode) "Pulihkan akun" else "Buat akun pribadi") {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { FilterChip(selected = !recoverMode, onClick = { recoverMode = false }, label = { Text("Buat akun") }); FilterChip(selected = recoverMode, onClick = { recoverMode = true }, label = { Text("Pulihkan") }) }
        if (recoverMode) {
            OutlinedTextField(value = recovery, onValueChange = { recovery = it }, label = { Text("Kunci pemulihan") }, visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth(), enabled = !model.busy, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
            FullButton("Buka akun", recovery.isNotBlank() && !model.busy) { val key = recovery; recovery = ""; model.recover(key) }
        } else {
            Field("Nama panggilan", model.profile.display_name, !model.busy) { model.profile = model.profile.copy(display_name = it) }
            Field("Email (opsional)", model.profile.email, !model.busy, KeyboardType.Email) { model.profile = model.profile.copy(email = it) }
            Text("Email hanya tersimpan terenkripsi; bukan sarana login atau pemulihan.", style = MaterialTheme.typography.bodySmall)
            FullButton("Siapkan akun pribadi", model.profile.display_name.isNotBlank() && !model.busy) { model.prepare() }
        }
    }
    Text("Kunci dan sesi hanya berada di memori. Setelah masuk, berpindah aplikasi mengunci Palmy. Simpan kunci pemulihan dengan aman.", style = MaterialTheme.typography.bodySmall, color = Muted)
}

@Composable private fun Home(model: PalmyModel) {
    Heading("Halo, ${model.profile.display_name}", "Keuangan yang lebih terarah, mulai hari ini.")
    model.summary?.let { summary ->
        Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = Primary), shape = RoundedCornerShape(24.dp)) {
            Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Saldo seluruh dompet", color = Soft)
                Text(Money.display(summary.balance), style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold, color = Color.White)
                Text("Pemasukan sepanjang waktu  ${Money.display(summary.income)}", color = Color.White)
                Text("Pengeluaran sepanjang waktu  ${Money.display(summary.expense)}", color = Color.White)
            }
        }
    }
    CardSection("Dompet") {
        if (model.wallets.isEmpty()) Text("Belum ada dompet. Buat dompet pertama di Keuangan.", color = Muted)
        model.wallets.forEach { wallet -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(wallet.name, Modifier.weight(1f)); Text(Money.display(wallet.balance), fontWeight = FontWeight.SemiBold) } }
    }
    CardSection("Transaksi terbaru") { Entries(model.entries.take(5)) }
    FullButton("Muat ulang", !model.busy) { model.reload() }
}

@Composable private fun Entries(entries: List<FinanceEntry>) {
    if (entries.isEmpty()) Text("Belum ada transaksi.", color = Muted)
    entries.forEach { entry ->
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(entry.category, Modifier.weight(1f), fontWeight = FontWeight.SemiBold); Text((if (entry.kind == "income") "+" else "−") + Money.display(entry.amount), fontWeight = FontWeight.SemiBold, color = if (entry.kind == "income") Primary else Ink) }
            Text(entry.effective_on + if (entry.description.isNotEmpty()) " · ${entry.description}" else "", style = MaterialTheme.typography.bodySmall, color = Muted)
        }
        HorizontalDivider(color = Soft)
    }
}

@Composable private fun Finance(model: PalmyModel) {
    var name by remember { mutableStateOf("") }
    var wallet by remember { mutableStateOf("") }
    var kind by remember { mutableStateOf("expense") }
    var amount by remember { mutableStateOf("") }
    var category by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }
    var date by remember { mutableStateOf(LocalDate.now(ZoneId.of("Asia/Jakarta")).toString()) }
    var walletPicker by remember { mutableStateOf(false) }
    LaunchedEffect(model.savedWallet) { name = "" }
    LaunchedEffect(model.savedEntry) { amount = ""; category = ""; description = "" }
    Heading("Keuangan", "Catatan yang jelas untuk setiap langkah.")
    CardSection("Dompet baru") {
        Field("Nama dompet (tanpa identitas pribadi)", name, !model.busy) { name = it }
        FullButton("Tambah dompet", name.isNotBlank() && name.trim().length <= 80 && !model.busy) { model.wallet(name) }
    }
    CardSection("Catat transaksi") {
        Text("Nominal, kategori, dan catatan dapat dibaca layanan. Jangan isi nama orang, email, atau nomor rekening.", style = MaterialTheme.typography.bodySmall)
        Box {
            OutlinedButton(onClick = { walletPicker = true }, enabled = !model.busy, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text(model.wallets.find { it.id == wallet }?.name ?: "Pilih dompet") }
            DropdownMenu(expanded = walletPicker, onDismissRequest = { walletPicker = false }) { model.wallets.forEach { item -> DropdownMenuItem(text = { Text(item.name) }, onClick = { wallet = item.id; walletPicker = false }) } }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) { FilterChip(selected = kind == "expense", onClick = { kind = "expense" }, label = { Text("Pengeluaran") }); FilterChip(selected = kind == "income", onClick = { kind = "income" }, label = { Text("Pemasukan") }) }
        Field("Nominal IDR, misalnya 1234.56", amount, !model.busy, KeyboardType.Decimal) { amount = it }
        if (amount.isNotEmpty() && !Money.validPositive(amount)) Text("Gunakan angka positif dengan titik desimal, maksimal 2 digit desimal.", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        Field("Kategori", category, !model.busy) { category = it }
        Field("Catatan (opsional)", description, !model.busy) { description = it }
        Field("Tanggal Jakarta (YYYY-MM-DD)", date, !model.busy) { date = it }
        val validDate = runCatching { LocalDate.parse(date).toString() == date }.getOrDefault(false)
        FullButton("Simpan transaksi", wallet.isNotEmpty() && Money.validPositive(amount) && category.isNotBlank() && category.length <= 60 && description.length <= 280 && validDate && !model.busy) { model.post(TransactionInput(wallet, kind, amount, category, description, date)) }
    }
    CardSection("Riwayat transaksi") { Entries(model.entries); if (model.cursor != null) FullButton("Muat lebih banyak", !model.busy) { model.more() } }
}

@Composable private fun ProfileScreen(model: PalmyModel) {
    Heading("Profil", "Identitas Anda, kunci Anda.")
    CardSection("Dienkripsi sebelum dikirim") {
        Field("Nama panggilan", model.profile.display_name, !model.busy) { model.profile = model.profile.copy(display_name = it) }
        Field("Email (opsional)", model.profile.email, !model.busy, KeyboardType.Email) { model.profile = model.profile.copy(email = it) }
        FullButton("Simpan profil terenkripsi", model.profile.display_name.isNotBlank() && !model.busy) { model.saveProfile() }
        OutlinedButton(onClick = { model.reloadProfile() }, enabled = !model.busy, modifier = Modifier.fillMaxWidth()) { Text("Muat profil terbaru") }
    }
    CardSection("Privasi") { Text("Palmy menyimpan profil sebagai ciphertext. Data keuangan tetap terbaca dan dapat memberi petunjuk tentang pemiliknya. Ini bukan jaminan anonimitas.") }
    FullButton("Kunci & cabut sesi") { model.lock() }
}
