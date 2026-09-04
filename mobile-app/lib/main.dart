import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

const String SERVER_URL = 'http://10.245.222.24:3000';

// ====================== MAIN ======================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('patients');
  await Hive.openBox('settings');
  final isLoggedIn = Hive.box('settings').get('isLoggedIn', defaultValue: false);
  runApp(BabyCouveuseApp(isLoggedIn: isLoggedIn));
}

// ====================== APP ======================
class BabyCouveuseApp extends StatelessWidget {
  final bool isLoggedIn;
  const BabyCouveuseApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Couveuse Néonatale',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        cardTheme: const CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16))),
        ),
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      ),
      home: isLoggedIn ? const SplashRouter() : const LoginScreen(),
    );
  }
}

// ====================== SPLASH ROUTER ======================
class SplashRouter extends StatelessWidget {
  const SplashRouter({super.key});
  @override
  Widget build(BuildContext context) {
    final role = Hive.box('settings').get('userRole', defaultValue: '');
    if (role == 'Admin') return const AdminScreen();
    return const PatientsListScreen();
  }
}

// ====================== HELPER : SESSION EXPIRÉE ======================
/// Redirige vers LoginScreen et réinitialise isLoggedIn si le token est absent
/// ou si le serveur retourne 401.
Future<void> _handleSessionExpired(BuildContext context) async {
  await Hive.box('settings').put('isLoggedIn', false);
  Fluttertoast.showToast(
    msg: 'Session expirée, veuillez vous reconnecter.',
    backgroundColor: Colors.orange,
    toastLength: Toast.LENGTH_LONG,
  );
  if (context.mounted) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}

// ====================== LOGIN ======================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  bool isLoading = false;

  Future<void> _login() async {
    setState(() => isLoading = true);
    final email = _emailController.text.trim().toLowerCase();
    try {
      final response = await http.post(
        Uri.parse('$SERVER_URL/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': _passwordController.text}),
      );
      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final user  = body['user'];
        final token = body['token'];
        await Hive.box('settings').putAll({
          'isLoggedIn': true,
          'userEmail':  email,
          'userRole':   user['role'],
          'userName':   user['name'],
          'token':      token,
        });
        Fluttertoast.showToast(msg: "Connexion réussie", backgroundColor: Colors.green);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => user['role'] == 'Admin'
                  ? const AdminScreen()
                  : const PatientsListScreen(),
            ),
          );
        }
      } else if (response.statusCode == 403) {
        Fluttertoast.showToast(
          msg: body['error'] ?? "Compte non actif",
          backgroundColor: Colors.orange,
          toastLength: Toast.LENGTH_LONG,
        );
      } else {
        Fluttertoast.showToast(
          msg: body['error'] ?? "Email ou mot de passe incorrect",
          backgroundColor: Colors.red,
        );
      }
    } on SocketException {
      Fluttertoast.showToast(
        msg: "Impossible de contacter le serveur.",
        backgroundColor: Colors.red,
        toastLength: Toast.LENGTH_LONG,
      );
    } catch (e) {
      Fluttertoast.showToast(msg: "Erreur: $e", backgroundColor: Colors.red);
    }
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 10,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.medical_services, size: 60, color: Colors.blue),
                  ),
                  const SizedBox(height: 20),
                  Text("Bienvenue",
                      style: GoogleFonts.poppins(
                          fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blue[800])),
                  Text("Service Néonatologie",
                      style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 14)),
                  const SizedBox(height: 40),
                  _buildTextField(_emailController, "Email", Icons.email_outlined,
                      TextInputType.emailAddress),
                  const SizedBox(height: 15),
                  _buildTextField(_passwordController, "Mot de passe", Icons.lock_outline,
                      null, true),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                      child: isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text("SE CONNECTER",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const RequestAccountScreen())),
                    child: const Text("Créer un compte", style: TextStyle(color: Colors.blue)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController c, String label, IconData icon,
      [TextInputType? type, bool obscure = false]) {
    return TextField(
      controller: c,
      keyboardType: type,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.blue),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
      ),
    );
  }
}

// ====================== CREATION DE COMPTE ======================
class RequestAccountScreen extends StatefulWidget {
  const RequestAccountScreen({super.key});
  @override
  State<RequestAccountScreen> createState() => _RequestAccountScreenState();
}

class _RequestAccountScreenState extends State<RequestAccountScreen> {
  final _nameController            = TextEditingController();
  final _emailController           = TextEditingController();
  final _cinController             = TextEditingController();
  final _passwordController        = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String selectedRole = 'Infirmier';
  bool isLoading = false;

  Future<void> _createAccount() async {
    if (_nameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _cinController.text.isEmpty) {
      Fluttertoast.showToast(
          msg: "Nom, Email et CIN sont obligatoires", backgroundColor: Colors.orange);
      return;
    }
    if (_passwordController.text.length < 6) {
      Fluttertoast.showToast(
          msg: "Le mot de passe doit contenir au moins 6 caractères",
          backgroundColor: Colors.orange);
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      Fluttertoast.showToast(
          msg: "Les mots de passe ne correspondent pas", backgroundColor: Colors.red);
      return;
    }
    setState(() => isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$SERVER_URL/api/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name':     _nameController.text.trim(),
          'email':    _emailController.text.trim().toLowerCase(),
          'password': _passwordController.text,
          'role':     selectedRole,
          'cin':      _cinController.text.trim(),
        }),
      );
      final body = jsonDecode(response.body);
      if (response.statusCode == 201) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            icon: const Icon(Icons.hourglass_empty, color: Colors.orange, size: 48),
            title: const Text('Demande envoyée'),
            content: const Text(
              'Votre demande a été soumise.\n\nUn administrateur va examiner votre compte.',
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () { Navigator.pop(context); Navigator.pop(context); },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        Fluttertoast.showToast(
            msg: body['error'] ?? 'Erreur lors de la création', backgroundColor: Colors.red);
      }
    } on SocketException {
      Fluttertoast.showToast(
          msg: "Impossible de contacter le serveur.", backgroundColor: Colors.red);
    } catch (e) {
      Fluttertoast.showToast(msg: "Erreur: $e", backgroundColor: Colors.red);
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text("Inscription"),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const Icon(Icons.person_add, size: 70, color: Colors.blue),
              const SizedBox(height: 10),
              Text("Bienvenue à l'inscription !",
                  style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold)),
              Text("Renseignez vos informations",
                  style: GoogleFonts.poppins(color: Colors.grey)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Votre compte sera activé après approbation par un administrateur.',
                        style: TextStyle(color: Colors.orange, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildTextField(_nameController, "Nom et prénom", Icons.person_outline),
              const SizedBox(height: 15),
              _buildTextField(_emailController, "Email", Icons.email_outlined,
                  TextInputType.emailAddress),
              const SizedBox(height: 15),
              _buildTextField(_cinController, "CIN", Icons.badge_outlined,
                  TextInputType.number),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: InputDecoration(
                  labelText: "Métier",
                  prefixIcon: const Icon(Icons.work_outline, color: Colors.blue),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: const [
                  DropdownMenuItem(value: 'Infirmier', child: Text("Infirmier(ère)")),
                  DropdownMenuItem(value: 'Medecin',   child: Text("Médecin")),
                ],
                onChanged: (v) => setState(() => selectedRole = v!),
              ),
              const SizedBox(height: 15),
              _buildTextField(_passwordController, "Mot de passe (min. 6 caractères)",
                  Icons.lock_outline, null, true),
              const SizedBox(height: 15),
              _buildTextField(_confirmPasswordController, "Confirmer le mot de passe",
                  Icons.lock_outline, null, true),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _createAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("S'INSCRIRE",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController c, String label, IconData icon,
      [TextInputType? type, bool obscure = false]) {
    return TextField(
      controller: c,
      keyboardType: type,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.blue),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
      ),
    );
  }
}

// ====================== MODELE PATIENT ======================
class Patient {
  final String id;
  final String name;
  final String litId;
  final String? poids;
  final String? dateNaissance;
  final DateTime createdAt;
  final bool isCritical;
  final bool hasCardiacAlert;
  final bool hasTempAlert;

  Patient({
    required this.id,
    required this.name,
    required this.litId,
    this.poids,
    this.dateNaissance,
    required this.createdAt,
    this.isCritical       = false,
    this.hasCardiacAlert  = false,
    this.hasTempAlert     = false,
  });

  Map<String, dynamic> toMap() => {
        'id':              id,
        'name':            name,
        'litId':           litId,
        'poids':           poids,
        'dateNaissance':   dateNaissance,
        'createdAt':       createdAt.toIso8601String(),
        'isCritical':      isCritical,
        'hasCardiacAlert': hasCardiacAlert,
        'hasTempAlert':    hasTempAlert,
      };

  factory Patient.fromMap(Map<String, dynamic> map) => Patient(
        id:              map['id'],
        name:            map['name'],
        litId:           map['litId'],
        poids:           map['poids'],
        dateNaissance:   map['dateNaissance'],
        createdAt:       DateTime.parse(map['createdAt']),
        isCritical:      map['isCritical']      ?? false,
        hasCardiacAlert: map['hasCardiacAlert'] ?? false,
        hasTempAlert:    map['hasTempAlert']    ?? false,
      );

  Patient copyWith({bool? hasCardiacAlert, bool? hasTempAlert, bool? isCritical}) =>
      Patient(
        id:              id,
        name:            name,
        litId:           litId,
        poids:           poids,
        dateNaissance:   dateNaissance,
        createdAt:       createdAt,
        isCritical:      isCritical      ?? this.isCritical,
        hasCardiacAlert: hasCardiacAlert ?? this.hasCardiacAlert,
        hasTempAlert:    hasTempAlert    ?? this.hasTempAlert,
      );
}

// ====================== LISTE PATIENTS ======================
class PatientsListScreen extends StatefulWidget {
  const PatientsListScreen({super.key});
  @override
  State<PatientsListScreen> createState() => _PatientsListScreenState();
}

class _PatientsListScreenState extends State<PatientsListScreen> {
  late Box patientsBox;

  @override
  void initState() {
    super.initState();
    patientsBox = Hive.box('patients');
    _initDefaultPatients();
  }

  void _initDefaultPatients() {
    if (patientsBox.isEmpty) {
      final defaults = [
        Patient(id: '1', name: "Ayari Salma",      litId: "lit6",  createdAt: DateTime.now()),
        Patient(id: '2', name: "Khamesi Samir",     litId: "lit8",  createdAt: DateTime.now()),
        Patient(id: '3', name: "Ben Salah Badii",   litId: "lit9",  createdAt: DateTime.now()),
        Patient(id: '4', name: "Mansouri Sameh",    litId: "lit11", createdAt: DateTime.now()),
      ];
      for (var p in defaults) {
        patientsBox.put(p.id, p.toMap());
      }
    }
  }

  List<Patient> get patients => patientsBox.values
      .map((v) => Patient.fromMap(Map<String, dynamic>.from(v)))
      .toList();

  int get criticalCount => patients.where((p) => p.isCritical).length;

  Future<void> _addPatient() async {
    final result = await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const AddPatientScreen()));
    if (result == true) setState(() {});
  }

  Future<void> _deletePatient(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Supprimer le patient ?"),
        content: Text("Voulez-vous supprimer $name ?\n\nCette action est irréversible."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("Supprimer"),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await patientsBox.delete(id);
      setState(() {});
      Fluttertoast.showToast(msg: "Patient supprimé", backgroundColor: Colors.green);
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientList = patients;
    final critical    = criticalCount;
    final userRole    = Hive.box('settings').get('userRole', defaultValue: 'Infirmier');

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (userRole == 'Admin')
                    IconButton(
                      icon: const Icon(Icons.admin_panel_settings, color: Colors.blue),
                      tooltip: 'Panneau Admin',
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const AdminScreen())),
                    ),
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.blue),
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  ),
                ],
              ),
              _buildUserInfoCard(),
              const SizedBox(height: 12),
              if (critical > 0) ...[
                Card(
                  color: Colors.red[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber, color: Colors.red, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "$critical patient(s) en état critique",
                            style: const TextStyle(
                                color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Expanded(
                child: patientList.isEmpty
                    ? const Center(
                        child: Text("Aucun patient", style: TextStyle(color: Colors.grey)))
                    : GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.82,
                        children: patientList.map((p) => _buildPatientCard(p)).toList(),
                      ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: _addPatient,
                icon: const Icon(Icons.add),
                label: const Text("Ajouter"),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () async {
                  await Hive.box('settings').put('isLoggedIn', false);
                  if (context.mounted) {
                    Navigator.pushReplacement(context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()));
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Déconnexion"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserInfoCard() {
    final userName = Hive.box('settings').get('userName', defaultValue: 'Utilisateur');
    final userRole = Hive.box('settings').get('userRole', defaultValue: 'Infirmier');
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.blue,
              child: Text(userName[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(userRole, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientCard(Patient patient) {
    Color? borderColor;
    if (patient.hasCardiacAlert)      borderColor = Colors.red;
    else if (patient.hasTempAlert)    borderColor = Colors.orange;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PatientDetailScreen(
              name:      patient.name,
              litId:     patient.litId,
              patientId: patient.id,
            ),
          ),
        );
        setState(() {});
      },
      child: Card(
        elevation: borderColor != null ? 6 : 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: borderColor != null
              ? BorderSide(color: borderColor, width: 2.5)
              : BorderSide.none,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: borderColor != null
                ? LinearGradient(
                    colors: [borderColor.withOpacity(0.08), Colors.white],
                    begin: Alignment.topCenter, end: Alignment.bottomCenter)
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.baby_changing_station,
                          size: 36, color: Colors.blue),
                    ),
                    if (patient.hasCardiacAlert)
                      Positioned(
                        right: -4, top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                              color: Colors.red, shape: BoxShape.circle),
                          child: const Icon(Icons.favorite, color: Colors.white, size: 11),
                        ),
                      ),
                    if (patient.hasTempAlert && !patient.hasCardiacAlert)
                      Positioned(
                        right: -4, top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                              color: Colors.orange, shape: BoxShape.circle),
                          child: const Icon(Icons.thermostat, color: Colors.white, size: 11),
                        ),
                      ),
                  ],
                ),
                Text(patient.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                Text(patient.litId,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                    textAlign: TextAlign.center),
                if (patient.poids != null)
                  Text("${patient.poids} kg",
                      style: TextStyle(color: Colors.blue[700], fontSize: 11)),
                if (patient.hasCardiacAlert || patient.hasTempAlert)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                    decoration: BoxDecoration(
                      color: patient.hasCardiacAlert
                          ? Colors.red.withOpacity(0.12)
                          : Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          patient.hasCardiacAlert ? Icons.warning_amber : Icons.thermostat,
                          size: 12,
                          color: patient.hasCardiacAlert ? Colors.red : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          patient.hasCardiacAlert ? "Alerte cardiaque" : "Alerte temp.",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: patient.hasCardiacAlert ? Colors.red : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => _deletePatient(patient.id, patient.name),
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                    label: const Text("Supprimer",
                        style: TextStyle(fontSize: 11, color: Colors.red)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      backgroundColor: Colors.red.withOpacity(0.07),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ====================== AJOUTER PATIENT ======================
class AddPatientScreen extends StatefulWidget {
  const AddPatientScreen({super.key});
  @override
  State<AddPatientScreen> createState() => _AddPatientScreenState();
}

class _AddPatientScreenState extends State<AddPatientScreen> {
  final _nameController          = TextEditingController();
  final _poidsController         = TextEditingController();
  final _dateNaissanceController = TextEditingController();

  final List<String> availableLitIds = [
    'lit1','lit2','lit3','lit4','lit5',
    'lit6','lit7','lit8','lit9','lit10','lit11',
  ];
  String selectedLitId = 'lit6';

  Future<void> _savePatient() async {
    if (_nameController.text.isEmpty) {
      Fluttertoast.showToast(msg: "Le nom est obligatoire", backgroundColor: Colors.orange);
      return;
    }
    final patientsBox = Hive.box('patients');
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final patient = Patient(
      id:            id,
      name:          _nameController.text.trim(),
      litId:         selectedLitId,
      poids:         _poidsController.text.isEmpty ? null : _poidsController.text.trim(),
      dateNaissance: _dateNaissanceController.text.isEmpty
          ? null : _dateNaissanceController.text.trim(),
      createdAt: DateTime.now(),
    );
    await patientsBox.put(id, patient.toMap());
    Fluttertoast.showToast(msg: "Patient ajouté !", backgroundColor: Colors.green);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text("Nouveau Patient"),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.person_add_alt_1, size: 60, color: Colors.blue),
            const SizedBox(height: 20),
            _buildTextField(_nameController, "Nom et prénom", Icons.person),
            const SizedBox(height: 15),
            DropdownButtonFormField<String>(
              value: selectedLitId,
              decoration: InputDecoration(
                labelText: "Identifiant du lit (ESP32)",
                prefixIcon: const Icon(Icons.bed, color: Colors.blue),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: availableLitIds
                  .map((lit) => DropdownMenuItem(value: lit, child: Text(lit)))
                  .toList(),
              onChanged: (v) => setState(() => selectedLitId = v!),
            ),
            const SizedBox(height: 15),
            _buildTextField(_poidsController, "Poids (kg)", Icons.scale, TextInputType.number),
            const SizedBox(height: 15),
            _buildTextField(_dateNaissanceController,
                "Date de naissance (JJ/MM/AAAA)", Icons.cake),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _savePatient,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("ENREGISTRER",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController c, String label, IconData icon,
      [TextInputType? type]) {
    return TextField(
      controller: c,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.blue),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// ====================== DETAIL PATIENT ======================
class PatientDetailScreen extends StatefulWidget {
  final String name;
  final String litId;
  final String patientId;

  const PatientDetailScreen({
    super.key,
    required this.name,
    required this.litId,
    required this.patientId,
  });

  @override
  State<PatientDetailScreen> createState() => _PatientDetailScreenState();
}

class _PatientDetailScreenState extends State<PatientDetailScreen> {
  late IO.Socket socket;

  double bpm      = 0;
  double spo2     = 0;
  double tempBody = 0;
  double tempEnv  = 0;
  double hum      = 0;
  double ecgVal   = 0;
  bool   crying   = false;
  bool   isConnected = false;
  String lastUpdate  = "Jamais";

  final List<FlSpot> ecgSpots = List.generate(100, (i) => FlSpot(i.toDouble(), 0));
  int ecgIndex = 0;

  final List<FlSpot> bpmHistory  = [];
  final List<FlSpot> spo2History = [];
  final List<FlSpot> tempHistory = [];
  int historyIndex = 0;

  final List<Map<String, dynamic>> alerts = [];

  @override
  void initState() {
    super.initState();
    _connectSocket();
  }

  void _connectSocket() {
    socket = IO.io(
      SERVER_URL,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(2000)
          .build(),
    );
    socket.connect();

    socket.onConnect((_) {
      socket.emit('join_lit', widget.litId);
      setState(() => isConnected = true);
    });

    socket.on('vitals', (data) {
      setState(() {
        bpm      = (data['bpm']       ?? 0).toDouble();
        spo2     = (data['spo2']      ?? 0).toDouble();
        tempBody = (data['temp_body'] ?? 0).toDouble();
        tempEnv  = (data['temp_env']  ?? 0).toDouble();
        hum      = (data['humidite']  ?? 0).toDouble();
        ecgVal   = (data['ecg']       ?? 0).toDouble();
        crying   = data['crying'] == true;

        final now = DateTime.now();
        lastUpdate =
            "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";

        final idx = ecgIndex % 100;
        ecgSpots[idx] = FlSpot(idx.toDouble(),
            ecgVal != 0 ? ((ecgVal - 512) / 512).clamp(-2, 2) : 0);
        ecgIndex++;

        if (bpm > 0) {
          bpmHistory.add(FlSpot(historyIndex.toDouble(), bpm));
          if (bpmHistory.length > 50) bpmHistory.removeAt(0);
        }
        if (spo2 > 0) {
          spo2History.add(FlSpot(historyIndex.toDouble(), spo2));
          if (spo2History.length > 50) spo2History.removeAt(0);
        }
        if (tempBody > 0) {
          tempHistory.add(FlSpot(historyIndex.toDouble(), tempBody));
          if (tempHistory.length > 50) tempHistory.removeAt(0);
        }
        historyIndex++;
        _updatePatientAlerts();
      });
    });

    socket.on('alert', (data) {
      final message = data['message'] ?? 'Valeur critique détectée';
      setState(() {
        alerts.insert(0, {
          'message': message,
          'time':    DateTime.now(),
          'type':    _detectAlertType(message),
        });
        if (alerts.length > 20) alerts.removeLast();
      });
      Fluttertoast.showToast(
        msg: "${widget.litId} : $message",
        backgroundColor:
            _detectAlertType(message) == 'cardiac' ? Colors.red : Colors.orange,
        toastLength: Toast.LENGTH_LONG,
      );
    });

    socket.onDisconnect((_) => setState(() => isConnected = false));
  }

  String _detectAlertType(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('bpm')       || lower.contains('cardiaque') ||
        lower.contains('spo2')      || lower.contains('ecg')       ||
        lower.contains('oxygène')   || lower.contains('fréquence')) {
      return 'cardiac';
    }
    return 'temp';
  }

  void _updatePatientAlerts() {
    final bool hasCardiac = (_bpmColor() == Colors.red || _spo2Color() == Colors.red);
    final bool hasTemp    = (_tempColor() == Colors.orange || _tempColor() == Colors.red);
    final patientsBox = Hive.box('patients');
    final data = patientsBox.get(widget.patientId);
    if (data != null) {
      final patient = Patient.fromMap(Map<String, dynamic>.from(data));
      patientsBox.put(widget.patientId, patient.copyWith(
        hasCardiacAlert: hasCardiac,
        hasTempAlert:    hasTemp,
        isCritical:      hasCardiac || hasTemp,
      ).toMap());
    }
  }

  Color _bpmColor() {
    if (bpm == 0)                    return Colors.grey;
    if (bpm < 80 || bpm > 180)       return Colors.red;
    if (bpm < 100 || bpm > 160)      return Colors.orange;
    return Colors.green;
  }
  String _bpmStatus() {
    if (bpm == 0)               return "Non connecté";
    if (bpm < 80 || bpm > 180)  return "CRITIQUE";
    if (bpm < 100 || bpm > 160) return "Attention";
    return "Normal";
  }

  Color _spo2Color() {
    if (spo2 == 0)  return Colors.grey;
    if (spo2 < 90)  return Colors.red;
    if (spo2 < 95)  return Colors.orange;
    return Colors.green;
  }
  String _spo2Status() {
    if (spo2 == 0) return "Non connecté";
    if (spo2 < 90) return "CRITIQUE";
    if (spo2 < 95) return "Attention";
    return "Normal";
  }

  Color _tempColor() {
    if (tempBody == 0)                         return Colors.grey;
    if (tempBody < 36.0 || tempBody > 38.0)    return Colors.red;
    if (tempBody < 36.5 || tempBody > 37.5)    return Colors.orange;
    return Colors.green;
  }
  String _tempStatus() {
    if (tempBody == 0)                        return "Non connecté";
    if (tempBody < 36.0 || tempBody > 38.0)   return "CRITIQUE";
    if (tempBody < 36.5 || tempBody > 37.5)   return "Attention";
    return "Normal";
  }

  @override
  void dispose() {
    socket.disconnect();
    socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sortedSpots = List<FlSpot>.from(ecgSpots)
      ..sort((a, b) => a.x.compareTo(b.x));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(Icons.circle, size: 12,
                    color: isConnected ? Colors.greenAccent : Colors.redAccent),
                const SizedBox(width: 6),
                Text(isConnected ? 'En direct' : 'Déconnecté',
                    style: const TextStyle(fontSize: 12, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 35,
                      backgroundColor: Colors.blue,
                      child: Icon(Icons.baby_changing_station, size: 40, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.name,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          Text(widget.litId, style: const TextStyle(color: Colors.grey)),
                          Text("Dernière màj: $lastUpdate",
                              style: TextStyle(color: Colors.blue[700], fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            _buildSectionTitle("Fréquence Cardiaque", Icons.favorite, Colors.red),
            _buildVitalCard(
              value: bpm == 0 ? '--' : bpm.toStringAsFixed(0),
              unit: " bpm",
              color: _bpmColor(), status: _bpmStatus(),
              icon: Icons.favorite, iconColor: Colors.red,
              chart: bpmHistory.length > 1
                  ? _buildMiniChart(bpmHistory, _bpmColor(), 60, 200) : null,
            ),
            const SizedBox(height: 16),

            _buildSectionTitle("Saturation en Oxygène (SpO2)", Icons.water_drop, Colors.blue),
            _buildVitalCard(
              value: spo2 == 0 ? '--' : spo2.toStringAsFixed(0),
              unit: " %",
              color: _spo2Color(), status: _spo2Status(),
              icon: Icons.water_drop, iconColor: Colors.blue,
              chart: spo2History.length > 1
                  ? _buildMiniChart(spo2History, _spo2Color(), 80, 100) : null,
            ),
            const SizedBox(height: 16),

            _buildSectionTitle("ECG", Icons.monitor_heart, Colors.red),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    SizedBox(
                      height: 150,
                      child: LineChart(LineChartData(
                        lineBarsData: [
                          LineChartBarData(
                            spots: sortedSpots,
                            isCurved: false,
                            color: Colors.red,
                            barWidth: 1.5,
                            dotData: const FlDotData(show: false),
                          ),
                        ],
                        gridData: const FlGridData(show: true, drawVerticalLine: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        minY: -2, maxY: 2,
                      )),
                    ),
                    Text("Valeur brute: ${ecgVal.toStringAsFixed(0)}",
                        style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            _buildSectionTitle("Température Corporelle", Icons.thermostat, Colors.orange),
            _buildVitalCard(
              value: tempBody == 0 ? '--' : tempBody.toStringAsFixed(1),
              unit: " °C",
              color: _tempColor(), status: _tempStatus(),
              icon: Icons.thermostat, iconColor: Colors.orange,
              chart: tempHistory.length > 1
                  ? _buildMiniChart(tempHistory, _tempColor(), 35, 40) : null,
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _buildSmallCard(
                    icon: Icons.device_thermostat, iconColor: Colors.blueGrey,
                    label: "Temp. environnement",
                    value: tempEnv == 0 ? '--' : "${tempEnv.toStringAsFixed(1)} °C",
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSmallCard(
                    icon: Icons.water, iconColor: Colors.lightBlue,
                    label: "Humidité",
                    value: hum == 0 ? '--' : "${hum.toStringAsFixed(0)} %",
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _buildCryingCard(crying),
            const SizedBox(height: 20),

            if (alerts.isNotEmpty) ...[
              _buildSectionTitle("Alertes Récentes", Icons.warning, Colors.red),
              Card(
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: alerts.length > 5 ? 5 : alerts.length,
                  itemBuilder: (context, index) {
                    final alert     = alerts[index];
                    final isCardiac = alert['type'] == 'cardiac';
                    final alertColor = isCardiac ? Colors.red : Colors.orange;
                    final alertIcon  = isCardiac ? Icons.favorite : Icons.thermostat;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: alertColor.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: alertColor.withOpacity(0.3)),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                              color: alertColor.withOpacity(0.15), shape: BoxShape.circle),
                          child: Icon(alertIcon, color: alertColor, size: 18),
                        ),
                        title: Text(alert['message'],
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600, color: alertColor)),
                        subtitle: Text(
                          "${alert['time'].hour.toString().padLeft(2, '0')}:${alert['time'].minute.toString().padLeft(2, '0')}",
                          style: TextStyle(color: Colors.grey[600], fontSize: 11),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: alertColor, borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            isCardiac ? "CARDIAQUE" : "TEMP.",
                            style: const TextStyle(
                                color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HistoriqueScreen(
                          patientName: widget.name,
                          litId:       widget.litId,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.history),
                    label: const Text("Historique"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => DossierMedicalScreen(patientId: widget.patientId)),
                    ),
                    icon: const Icon(Icons.folder_open),
                    label: const Text("Dossier"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniChart(List<FlSpot> data, Color color, double minY, double maxY) =>
      SizedBox(
        height: 60,
        child: LineChart(LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: data, isCurved: true, color: color, barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: color.withOpacity(0.1)),
            ),
          ],
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          minY: minY, maxY: maxY,
        )),
      );

  Widget _buildSectionTitle(String title, IconData icon, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _buildVitalCard({
    required String value, required String unit,
    required Color color,  required String status,
    required IconData icon, required Color iconColor,
    Widget? chart,
  }) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Text(value,
                      style: TextStyle(
                          fontSize: 36, fontWeight: FontWeight.bold, color: color)),
                  Text(unit, style: const TextStyle(fontSize: 18, color: Colors.grey)),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Icon(icon, color: iconColor, size: 32),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(status,
                            style: TextStyle(
                                color: color, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
              if (chart != null) ...[const SizedBox(height: 10), chart],
            ],
          ),
        ),
      );

  Widget _buildSmallCard({
    required IconData icon, required Color iconColor,
    required String label,  required String value,
  }) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Icon(icon, color: iconColor, size: 28),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      );

  Widget _buildCryingCard(bool isCrying) => Card(
        elevation: isCrying ? 6 : 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isCrying
              ? const BorderSide(color: Colors.deepPurple, width: 2)
              : BorderSide.none,
        ),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isCrying
                ? Colors.deepPurple.withOpacity(0.08)
                : Colors.grey.withOpacity(0.04),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isCrying
                      ? Colors.deepPurple.withOpacity(0.15)
                      : Colors.grey.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCrying ? Icons.record_voice_over : Icons.mic_off,
                  color: isCrying ? Colors.deepPurple : Colors.grey,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Pleurs bébé",
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(
                      isCrying ? "Bébé pleure" : "Bébé calme",
                      style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold,
                        color: isCrying ? Colors.deepPurple : Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isCrying ? Colors.deepPurple : Colors.green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isCrying ? "ALERTE" : "OK",
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
}

// ====================== HISTORIQUE (tableau InfluxDB) ======================
class _HistRow {
  final String time;
  final double? bpm;
  final double? spo2;
  final double? tempBody;
  final double? tempEnv;
  final double? humidite;

  const _HistRow({
    required this.time,
    this.bpm,
    this.spo2,
    this.tempBody,
    this.tempEnv,
    this.humidite,
  });
}

class HistoriqueScreen extends StatefulWidget {
  final String patientName;
  final String litId;

  const HistoriqueScreen({
    super.key,
    required this.patientName,
    required this.litId,
  });

  @override
  State<HistoriqueScreen> createState() => _HistoriqueScreenState();
}

class _HistoriqueScreenState extends State<HistoriqueScreen> {
  List<_HistRow> rows      = [];
  bool   isLoading         = false;
  String selectedRange     = '1h';

  final List<Map<String, String>> ranges = [
    {'label': '1h',  'value': '1h'},
    {'label': '6h',  'value': '6h'},
    {'label': '24h', 'value': '24h'},
    {'label': '7j',  'value': '7d'},
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  // ══════════════════════════════════════════════════════════════
  //  CORRECTION PRINCIPALE : gestion 401 + token null
  // ══════════════════════════════════════════════════════════════
  Future<void> _loadHistory() async {
    setState(() => isLoading = true);

    try {
      // ── 1. Vérification token avant la requête ────────────────
      final token = Hive.box('settings').get('token');

      if (token == null || token.toString().trim().isEmpty) {
        await _handleSessionExpired(context);
        return;
      }

      // ── 2. Requête avec le token ──────────────────────────────
      final response = await http.get(
        Uri.parse('$SERVER_URL/api/history/${widget.litId}?range=$selectedRange'),
        headers: {'Authorization': 'Bearer $token'},
      );

      // ── 3. Token expiré ou invalide → backend retourne 401 ────
      if (response.statusCode == 401) {
        await _handleSessionExpired(context);
        return;
      }

      // ── 4. Autres erreurs serveur ─────────────────────────────
      if (response.statusCode != 200) {
        Fluttertoast.showToast(
          msg: 'Erreur serveur ${response.statusCode}',
          backgroundColor: Colors.red,
        );
        setState(() => isLoading = false);
        return;
      }

      // ── 5. Parsing et fusion des données ─────────────────────
      final body = jsonDecode(response.body);

      final Map<String, Map<String, double>> byTime = {};

      void ingest(List<dynamic> list, String field) {
        for (final pt in list) {
          final t = _roundToMinute(pt['t'] as String);
          byTime.putIfAbsent(t, () => {})[field] =
              (pt['v'] as num).toDouble();
        }
      }

      ingest(body['bpm']       ?? [], 'bpm');
      ingest(body['spo2']      ?? [], 'spo2');
      ingest(body['temp_body'] ?? [], 'temp_body');
      ingest(body['temp_env']  ?? [], 'temp_env');
      ingest(body['humidite']  ?? [], 'humidite');

      final sortedKeys = byTime.keys.toList()
        ..sort((a, b) => b.compareTo(a));

      setState(() {
        rows = sortedKeys.map((t) {
          final m = byTime[t]!;
          return _HistRow(
            time:     t,
            bpm:      m['bpm'],
            spo2:     m['spo2'],
            tempBody: m['temp_body'],
            tempEnv:  m['temp_env'],
            humidite: m['humidite'],
          );
        }).toList();
      });

    } on SocketException {
      Fluttertoast.showToast(
        msg: 'Serveur inaccessible',
        backgroundColor: Colors.red,
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Erreur: $e',
        backgroundColor: Colors.red,
      );
    }

    setState(() => isLoading = false);
  }

  String _roundToMinute(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return "${dt.year.toString().padLeft(4, '0')}-"
             "${dt.month.toString().padLeft(2, '0')}-"
             "${dt.day.toString().padLeft(2, '0')} "
             "${dt.hour.toString().padLeft(2, '0')}:"
             "${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return iso;
    }
  }

  String _fmt(double? v, int decimals, String unit) {
    if (v == null || v == 0) return '--';
    return '${v.toStringAsFixed(decimals)} $unit';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Historique — ${widget.patientName}"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Text('Période :',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                ...ranges.map((r) {
                  final selected = r['value'] == selectedRange;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(r['label']!),
                      selected: selected,
                      selectedColor: Colors.blue,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                      onSelected: (_) {
                        setState(() => selectedRange = r['value']!);
                        _loadHistory();
                      },
                    ),
                  );
                }),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.blue),
                  onPressed: _loadHistory,
                  tooltip: 'Actualiser',
                ),
              ],
            ),
          ),

          if (!isLoading && rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.table_rows, size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  Text('${rows.length} mesures',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
            ),

          const SizedBox(height: 8),
          _buildTableHeader(),

          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox, size: 56, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text(
                              'Aucune donnée sur cette période',
                              style: TextStyle(color: Colors.grey[500], fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) => _buildTableRow(rows[i], i),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    const headerStyle = TextStyle(
        fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white);
    return Container(
      color: Colors.blue[700],
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          _hCell('Heure',    flex: 3, style: headerStyle),
          _hCell('BPM',      flex: 2, style: headerStyle),
          _hCell('SpO2',     flex: 2, style: headerStyle),
          _hCell('T. Corp.', flex: 2, style: headerStyle),
          _hCell('T. Env.',  flex: 2, style: headerStyle),
          _hCell('Humidité', flex: 2, style: headerStyle),
        ],
      ),
    );
  }

  Widget _hCell(String text, {required int flex, required TextStyle style}) =>
      Expanded(
        flex: flex,
        child: Text(text, style: style, textAlign: TextAlign.center),
      );

  Widget _buildTableRow(_HistRow row, int index) {
    final bg = index.isEven ? Colors.white : Colors.grey[50]!;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              row.time.length > 16 ? row.time.substring(5) : row.time,
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
          ),
          _valueCell(_fmt(row.bpm,      0, 'bpm')),
          _valueCell(_fmt(row.spo2,     0, '%')),
          _valueCell(_fmt(row.tempBody, 1, '°C')),
          _valueCell(_fmt(row.tempEnv,  1, '°C')),
          _valueCell(_fmt(row.humidite, 0, '%')),
        ],
      ),
    );
  }

  Widget _valueCell(String text) =>
      Expanded(
        flex: 2,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.normal,
            color: text == '--' ? Colors.grey[400] : Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
      );
}

// ====================== DOSSIER MEDICAL ======================
class DossierMedicalScreen extends StatefulWidget {
  final String patientId;
  const DossierMedicalScreen({super.key, required this.patientId});
  @override
  State<DossierMedicalScreen> createState() => _DossierMedicalScreenState();
}

class _DossierMedicalScreenState extends State<DossierMedicalScreen> {
  final _notesController = TextEditingController();
  late Box patientsBox;
  Patient? patient;
  List<Map<String, dynamic>> notes = [];

  @override
  void initState() {
    super.initState();
    patientsBox = Hive.box('patients');
    _loadPatient();
    _loadNotes();
  }

  void _loadPatient() {
    final data = patientsBox.get(widget.patientId);
    if (data != null) patient = Patient.fromMap(Map<String, dynamic>.from(data));
  }

  void _loadNotes() {
    final saved = Hive.box('settings')
        .get('notes_${widget.patientId}', defaultValue: []);
    notes = List<Map<String, dynamic>>.from(saved);
  }

  Future<void> _saveNote() async {
    if (_notesController.text.isEmpty) return;
    notes.insert(0, {
      'text':   _notesController.text.trim(),
      'date':   DateTime.now().toIso8601String(),
      'author': Hive.box('settings').get('userName', defaultValue: 'Inconnu'),
    });
    await Hive.box('settings').put('notes_${widget.patientId}', notes);
    _notesController.clear();
    setState(() {});
    Fluttertoast.showToast(msg: "Note ajoutée", backgroundColor: Colors.green);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Dossier — ${patient?.name ?? 'Patient'}"),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (patient != null)
              Card(
                color: Colors.teal[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow("Nom",      patient!.name),
                      _infoRow("Lit ID",   patient!.litId),
                      if (patient!.poids != null)
                        _infoRow("Poids",  "${patient!.poids} kg"),
                      if (patient!.dateNaissance != null)
                        _infoRow("Né(e) le", patient!.dateNaissance!),
                      _infoRow("Admis le",
                          "${patient!.createdAt.day}/${patient!.createdAt.month}/${patient!.createdAt.year}"),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Text("Nouvelle note médicale",
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: "Entrez votre observation...",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _saveNote,
              icon: const Icon(Icons.save),
              label: const Text("Enregistrer la note"),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal, foregroundColor: Colors.white),
            ),
            const SizedBox(height: 20),
            Text("Historique des notes",
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: notes.isEmpty
                  ? const Center(
                      child: Text("Aucune note", style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: notes.length,
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        final date = DateTime.parse(note['date']);
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.note, color: Colors.teal),
                            title: Text(note['text'],
                                style: const TextStyle(fontSize: 14)),
                            subtitle: Text(
                              "Par ${note['author']} — ${date.day}/${date.month}/${date.year} "
                              "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}",
                              style: TextStyle(color: Colors.grey[600], fontSize: 11),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Text("$label: ",
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
            Text(value),
          ],
        ),
      );
}

// ====================== ADMIN SCREEN ======================
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> pendingUsers = [];
  List<dynamic> allUsers     = [];
  bool    isLoading    = true;
  String? errorMessage;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { isLoading = true; errorMessage = null; });
    await Future.wait([_loadPendingUsers(), _loadAllUsers()]);
    setState(() => isLoading = false);
  }

  Future<void> _loadPendingUsers() async {
    try {
      final token = Hive.box('settings').get('token');
      if (token == null) { setState(() => errorMessage = "Non connecté"); return; }
      final response = await http.get(
        Uri.parse('$SERVER_URL/api/admin/pending'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        setState(() => pendingUsers = body is List ? body : []);
      } else if (response.statusCode == 401) {
        await _handleSessionExpired(context);
      } else if (response.statusCode == 403) {
        setState(() => errorMessage = "Accès refusé");
      } else {
        setState(() => errorMessage = "Erreur serveur: ${response.statusCode}");
      }
    } on SocketException {
      setState(() => errorMessage = "Serveur hors ligne");
    } catch (e) {
      setState(() => errorMessage = "Erreur: $e");
    }
  }

  Future<void> _loadAllUsers() async {
    try {
      final token = Hive.box('settings').get('token');
      if (token == null) return;
      final response = await http.get(
        Uri.parse('$SERVER_URL/api/admin/users'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        setState(() => allUsers = body is List ? body : []);
      } else if (response.statusCode == 401) {
        await _handleSessionExpired(context);
      }
    } catch (_) {}
  }

  Future<void> _approveUser(int userId) async {
    try {
      final token = Hive.box('settings').get('token');
      final response = await http.post(
        Uri.parse('$SERVER_URL/api/admin/approve/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        Fluttertoast.showToast(
            msg: jsonDecode(response.body)['message'] ?? "Approuvé",
            backgroundColor: Colors.green);
        _loadData();
      } else if (response.statusCode == 401) {
        await _handleSessionExpired(context);
      } else {
        Fluttertoast.showToast(
            msg: "Erreur: ${response.statusCode}", backgroundColor: Colors.red);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Erreur réseau", backgroundColor: Colors.orange);
    }
  }

  Future<void> _rejectUser(int userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmer le rejet'),
        content: const Text('Rejeter cette demande de compte ?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rejeter', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final token = Hive.box('settings').get('token');
      final response = await http.post(
        Uri.parse('$SERVER_URL/api/admin/reject/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        Fluttertoast.showToast(
            msg: jsonDecode(response.body)['message'] ?? "Rejeté",
            backgroundColor: Colors.orange);
        _loadData();
      } else if (response.statusCode == 401) {
        await _handleSessionExpired(context);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: "Erreur réseau", backgroundColor: Colors.orange);
    }
  }

  Future<void> _logout() async {
    await Hive.box('settings').put('isLoggedIn', false);
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Panneau Administrateur"),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          IconButton(icon: const Icon(Icons.logout),  onPressed: _logout),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          tabs: [
            Tab(icon: const Icon(Icons.pending_actions),
                text: "En attente (${pendingUsers.length})"),
            Tab(icon: const Icon(Icons.people),
                text: "Tous (${allUsers.length})"),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? _buildErrorWidget()
              : TabBarView(
                  controller: _tabController,
                  children: [_buildPendingList(), _buildAllUsersList()],
                ),
    );
  }

  Widget _buildErrorWidget() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadData, child: const Text("Réessayer")),
          ],
        ),
      );

  Widget _buildPendingList() {
    if (pendingUsers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text("Aucune demande en attente",
                style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: pendingUsers.length,
        itemBuilder: (context, index) {
          final user = pendingUsers[index];
          return Card(
            elevation: 4,
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.orange,
                        child: Text((user['name'] as String)[0].toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user['name'],
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                            Text(user['email'],
                                style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12)),
                        child: const Text("EN ATTENTE",
                            style: TextStyle(
                                color: Colors.orange,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _adminInfoRow("Rôle", user['role']),
                  _adminInfoRow("CIN",  user['cin'] ?? 'Non renseigné'),
                  _adminInfoRow("Date", user['created_at']?.toString().split('T')[0] ?? 'Inconnue'),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _approveUser(user['id']),
                          icon: const Icon(Icons.check, color: Colors.white),
                          label: const Text("Approuver",
                              style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _rejectUser(user['id']),
                          icon: const Icon(Icons.close, color: Colors.white),
                          label: const Text("Refuser",
                              style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAllUsersList() {
    if (allUsers.isEmpty) {
      return const Center(
          child: Text("Aucun utilisateur", style: TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: allUsers.length,
        itemBuilder: (context, index) {
          final user = allUsers[index];
          final Color statusColor = switch (user['status']) {
            'active'   => Colors.green,
            'pending'  => Colors.orange,
            'rejected' => Colors.red,
            _          => Colors.grey,
          };
          final String statusLabel = switch (user['status']) {
            'active'   => 'ACTIF',
            'pending'  => 'EN ATTENTE',
            'rejected' => 'REFUSÉ',
            _          => user['status'].toString().toUpperCase(),
          };
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: statusColor,
                child: Text((user['name'] as String)[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white)),
              ),
              title: Text(user['name'],
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("${user['email']} · ${user['role']}"),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12)),
                child: Text(statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _adminInfoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text("$label: ", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      );
}

// ====================== PARAMETRES ======================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text("Paramètres"),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("URL du serveur",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(SERVER_URL, style: TextStyle(color: Colors.grey[600])),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () async {
                await Hive.box('patients').clear();
                await Hive.box('settings').clear();
                Fluttertoast.showToast(
                    msg: "Toutes les données ont été effacées",
                    backgroundColor: Colors.orange);
                // Redirection vers LoginScreen après effacement
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (_) => false,
                  );
                }
              },
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text("Effacer toutes les données",
                  style: TextStyle(color: Colors.red)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.red[50],
              ),
            ),
          ],
        ),
      ),
    );
  }
}