import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';

const _loginKey = 'is_admin_logged_in';
const _adminIdKey = 'admin_id';
const _adminEmailKey = 'admin_email';
const _adminNameKey = 'admin_name';
const _adminRoleKey = 'admin_role';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );
    firebaseReady = true;
  } catch (_) {
    firebaseReady = false;
  }

  runApp(AdminApp(firebaseReady: firebaseReady));
}

class AdminSession {
  const AdminSession({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
  });

  final String id;
  final String email;
  final String name;
  final String role;

  factory AdminSession.fromPrefs(SharedPreferences prefs) {
    return AdminSession(
      id: prefs.getString(_adminIdKey) ?? '',
      email: prefs.getString(_adminEmailKey) ?? '',
      name: prefs.getString(_adminNameKey) ?? 'Admin',
      role: prefs.getString(_adminRoleKey) ?? 'admin',
    );
  }

  factory AdminSession.fromAdminDoc({
    required String uid,
    required String fallbackEmail,
    required Map<String, dynamic> data,
  }) {
    final email = data['email']?.toString().trim().toLowerCase();
    final name = data['name']?.toString().trim();
    final role = data['role']?.toString().trim();
    return AdminSession(
      id: uid,
      email: email?.isNotEmpty == true ? email! : fallbackEmail,
      name: name?.isNotEmpty == true ? name! : fallbackEmail,
      role: role?.isNotEmpty == true ? role! : 'admin',
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setBool(_loginKey, true);
    await prefs.setString(_adminIdKey, id);
    await prefs.setString(_adminEmailKey, email);
    await prefs.setString(_adminNameKey, name);
    await prefs.setString(_adminRoleKey, role);
  }

  static Future<void> clear(SharedPreferences prefs) async {
    await prefs.remove(_loginKey);
    await prefs.remove(_adminIdKey);
    await prefs.remove(_adminEmailKey);
    await prefs.remove(_adminNameKey);
    await prefs.remove(_adminRoleKey);
  }
}

class AdminApp extends StatefulWidget {
  const AdminApp({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  bool? _loggedIn;
  AdminSession? _adminSession;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (!widget.firebaseReady) {
      final loggedIn = prefs.getBool(_loginKey) ?? false;
      if (!mounted) return;
      setState(() {
        _loggedIn = loggedIn;
        _adminSession = loggedIn ? AdminSession.fromPrefs(prefs) : null;
      });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await AdminSession.clear(prefs);
      if (!mounted) return;
      setState(() {
        _loggedIn = false;
        _adminSession = null;
      });
      return;
    }

    final session = await _verifiedAdminSession(user);
    if (session == null) {
      await FirebaseAuth.instance.signOut();
      await AdminSession.clear(prefs);
      if (!mounted) return;
      setState(() {
        _loggedIn = false;
        _adminSession = null;
      });
      return;
    }

    await session.save(prefs);
    if (!mounted) return;
    setState(() {
      _loggedIn = true;
      _adminSession = session;
    });
  }

  Future<String?> _login(String email, String password) async {
    if (!widget.firebaseReady) {
      return 'Firebase is not connected. Check FlutterFire configuration.';
    }

    final normalizedEmail = email.trim().toLowerCase();
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      final user = credential.user;
      if (user == null) return 'Unable to sign in.';

      final session = await _verifiedAdminSession(user);
      if (session == null || session.email != normalizedEmail) {
        await FirebaseAuth.instance.signOut();
        return 'This admin account is disabled or does not match Firestore.';
      }

      final prefs = await SharedPreferences.getInstance();
      await session.save(prefs);
      setState(() {
        _loggedIn = true;
        _adminSession = session;
      });
      return null;
    } on FirebaseAuthException catch (error) {
      return switch (error.code) {
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' => 'Invalid admin email or password.',
        'invalid-email' => 'Enter a valid admin email.',
        _ => error.message ?? 'Unable to sign in.',
      };
    } catch (_) {
      return 'Unable to verify admin account.';
    }
  }

  Future<AdminSession?> _verifiedAdminSession(User user) async {
    final fallbackEmail = user.email?.trim().toLowerCase() ?? '';
    final adminDoc = await FirebaseFirestore.instance
        .collection('admins')
        .doc(user.uid)
        .get();
    if (!adminDoc.exists) return null;

    final data = adminDoc.data() ?? {};
    final active = data['active'] == true;
    final adminEmail = data['email']?.toString().trim().toLowerCase() ?? '';
    if (!active || adminEmail.isEmpty || adminEmail != fallbackEmail) {
      return null;
    }

    return AdminSession.fromAdminDoc(
      uid: user.uid,
      fallbackEmail: fallbackEmail,
      data: data,
    );
  }

  Future<void> _logout() async {
    if (widget.firebaseReady) {
      await FirebaseAuth.instance.signOut();
    }
    final prefs = await SharedPreferences.getInstance();
    await AdminSession.clear(prefs);
    setState(() {
      _loggedIn = false;
      _adminSession = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF006B5F),
        primary: const Color(0xFF031632),
        secondary: const Color(0xFF006B5F),
        surface: const Color(0xFFF8F9FF),
      ),
      scaffoldBackgroundColor: const Color(0xFFF8F9FF),
      fontFamily: 'Arial',
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE1E7F2)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    return MaterialApp(
      title: 'TestPrep Admin',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: _loggedIn == null
          ? const SplashPage()
          : _loggedIn!
          ? AdminShell(
              repository: FirestoreRepository(
                firebaseEnabled: widget.firebaseReady,
              ),
              firebaseReady: widget.firebaseReady,
              adminSession: _adminSession,
              onLogout: _logout,
            )
          : LoginPage(onLogin: _login, firebaseReady: widget.firebaseReady),
    );
  }
}

class FirestoreRepository {
  FirestoreRepository({required this.firebaseEnabled});

  final bool firebaseEnabled;

  CollectionReference<Map<String, dynamic>> get _exams =>
      FirebaseFirestore.instance.collection('exams');
  CollectionReference<Map<String, dynamic>> get _users =>
      FirebaseFirestore.instance.collection('users');
  CollectionReference<Map<String, dynamic>> get _questions =>
      FirebaseFirestore.instance.collection('questions');

  Stream<List<Map<String, dynamic>>> exams() {
    if (!firebaseEnabled) {
      return Stream<List<Map<String, dynamic>>>.value(const []);
    }
    return _stream(_exams.orderBy('createdAt', descending: true));
  }

  Stream<List<Map<String, dynamic>>> users() {
    if (!firebaseEnabled) {
      return Stream<List<Map<String, dynamic>>>.value(const []);
    }
    return _stream(_users.orderBy('createdAt', descending: true));
  }

  Stream<List<Map<String, dynamic>>> questions() {
    if (!firebaseEnabled) {
      return Stream<List<Map<String, dynamic>>>.value(const []);
    }
    return _stream(_questions.orderBy('createdAt', descending: true));
  }

  Stream<List<Map<String, dynamic>>> _stream(
    Query<Map<String, dynamic>> query,
  ) {
    if (!firebaseEnabled) {
      return Stream<List<Map<String, dynamic>>>.value(const []);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
          .toList();
    });
  }

  Future<void> addExam({
    required String title,
    required String category,
    required int questions,
    required int completions,
    required double passRate,
    required String status,
    List<Map<String, dynamic>> subjectBreakdown = const [],
  }) async {
    final data = _examPayload(
      title: title,
      category: category,
      questions: questions,
      completions: completions,
      passRate: passRate,
      status: status,
      subjectBreakdown: subjectBreakdown,
    )..['createdAt'] = FieldValue.serverTimestamp();
    _ensureFirebase();
    await _exams.add(data);
  }

  Future<void> saveExam({
    String? id,
    required String title,
    required String category,
    required int questions,
    required int completions,
    required double passRate,
    required String status,
    required List<Map<String, dynamic>> subjectBreakdown,
    String? questionPrompt,
    List<String> questionOptions = const [],
    int answerIndex = 0,
    String difficulty = 'Medium',
  }) async {
    _ensureFirebase();

    final data = _examPayload(
      title: title,
      category: category,
      questions: questions,
      completions: completions,
      passRate: passRate,
      status: status,
      subjectBreakdown: subjectBreakdown,
    );

    if (id == null || id.isEmpty) {
      final doc = await _exams.add({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      });
      id = doc.id;
    } else {
      await _exams.doc(id).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    final cleanPrompt = questionPrompt?.trim() ?? '';
    if (cleanPrompt.isNotEmpty &&
        questionOptions.every((text) => text.trim().isNotEmpty)) {
      await addQuestion(
        exam: title,
        prompt: cleanPrompt,
        options: questionOptions.map((text) => text.trim()).toList(),
        answerIndex: answerIndex,
        difficulty: difficulty,
      );
    }
  }

  Map<String, dynamic> _examPayload({
    required String title,
    required String category,
    required int questions,
    required int completions,
    required double passRate,
    required String status,
    required List<Map<String, dynamic>> subjectBreakdown,
  }) {
    return {
      'title': title,
      'category': category,
      'questions': questions,
      'completions': completions,
      'passRate': passRate,
      'status': status,
      'subjectBreakdown': subjectBreakdown,
      'totalMcqs': questions,
    };
  }

  Future<void> addUser({
    required String name,
    required String email,
    required String plan,
    required int tests,
    required double score,
    required String status,
  }) async {
    final data = {
      'name': name,
      'email': email,
      'plan': plan,
      'tests': tests,
      'score': score,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(),
    };
    _ensureFirebase();
    await _users.add(data);
  }

  Future<void> addQuestion({
    required String exam,
    required String prompt,
    required List<String> options,
    required int answerIndex,
    required String difficulty,
    String? subject,
  }) async {
    final data = {
      'exam': exam,
      if (subject != null && subject.trim().isNotEmpty)
        'subject': subject.trim(),
      'prompt': prompt,
      'options': options,
      'answerIndex': answerIndex,
      'difficulty': difficulty,
      'createdAt': FieldValue.serverTimestamp(),
    };
    _ensureFirebase();
    await _questions.add(data);
  }

  Future<void> addQuestions(List<McqDraft> questions) async {
    _ensureFirebase();
    if (questions.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final question in questions) {
      batch.set(_questions.doc(), {
        'exam': question.exam,
        'subject': question.subject,
        'prompt': question.prompt,
        'options': question.options,
        'answerIndex': question.answerIndex,
        'difficulty': question.difficulty,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> updateStatus(String collection, String id, String status) async {
    _ensureFirebase();
    if (id.isEmpty) return;
    await FirebaseFirestore.instance.collection(collection).doc(id).update({
      'status': status,
    });
  }

  Future<void> deleteExam(String id) async {
    _ensureFirebase();
    if (id.isEmpty) return;
    await _exams.doc(id).delete();
  }

  void _ensureFirebase() {
    if (!firebaseEnabled) {
      throw StateError('Firebase is not connected.');
    }
  }
}

const _dailyPracticeSubjects = <Map<String, dynamic>>[
  {'subject': 'English', 'mcqs': 30},
  {'subject': 'Pedagogy', 'mcqs': 20},
  {'subject': 'General Knowledge', 'mcqs': 10},
  {'subject': 'Pakistan Studies', 'mcqs': 10},
  {'subject': 'Islamic Studies', 'mcqs': 10},
  {'subject': 'Current Affairs', 'mcqs': 5},
  {'subject': 'Everyday Science', 'mcqs': 5},
  {'subject': 'Computer', 'mcqs': 5},
  {'subject': 'Mathematics', 'mcqs': 5},
  {'subject': 'IQ', 'mcqs': 5},
];

const _dailyPracticeTotal = 100;

const _examFilterCategories = [
  'All Exams',
  'SST Preparation',
  'PST Training',
  'Computer Operator',
  'General Knowledge',
  'Daily Practice',
];

const _mcqSubjects = [
  'English',
  'General Knowledge',
  'Computer',
  'Mathematics',
  'Current Affairs',
  'Pakistan Studies',
  'Islamic Studies',
  'Everyday Science',
  'Pedagogy',
  'IQ',
];

class McqDraft {
  const McqDraft({
    required this.exam,
    required this.subject,
    required this.prompt,
    required this.options,
    required this.answerIndex,
    required this.difficulty,
  });

  final String exam;
  final String subject;
  final String prompt;
  final List<String> options;
  final int answerIndex;
  final String difficulty;
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.onLogin,
    required this.firebaseReady,
  });

  final Future<String?> Function(String email, String password) onLogin;
  final bool firebaseReady;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  var _loading = false;
  var _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final error = await widget.onLogin(_email.text, _password.text);
    if (mounted) {
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 520,
                    padding: const EdgeInsets.all(36),
                    decoration: BoxDecoration(
                      color: const Color(0xFF031632),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(
                          Icons.school_outlined,
                          color: Color(0xFF71F8E4),
                          size: 56,
                        ),
                        SizedBox(height: 28),
                        Text(
                          'TestPrep Admin',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Manage exams, learners, MCQs, and analytics from one Firebase-powered web console.',
                          style: TextStyle(
                            color: Color(0xFFB6C7EB),
                            fontSize: 17,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Admin Login',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF0B1C30),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.firebaseReady
                                  ? 'Sign in with your authorized admin account.'
                                  : 'Firebase is not connected. Login is disabled.',
                              style: const TextStyle(color: Color(0xFF5E6878)),
                            ),
                            const SizedBox(height: 28),
                            TextFormField(
                              controller: _email,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                hintText: 'Enter email',
                                prefixIcon: Icon(Icons.mail_outline),
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Email is required'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _password,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                hintText: 'Enter password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) =>
                                  value == null || value.isEmpty
                                  ? 'Password is required'
                                  : null,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFFBA1A1A),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: _loading ? null : _submit,
                              icon: _loading
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.login),
                              label: const Text('Sign in'),
                            ),
                          ],
                        ),
                      ),
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

class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    required this.repository,
    required this.firebaseReady,
    required this.adminSession,
    required this.onLogout,
  });

  final FirestoreRepository repository;
  final bool firebaseReady;
  final AdminSession? adminSession;
  final Future<void> Function() onLogout;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  var _index = 0;

  final _items = const [
    _NavItem('Overview', Icons.dashboard_outlined),
    _NavItem('Exams', Icons.quiz_outlined),
    _NavItem('Users', Icons.group_outlined),
    _NavItem('Content', Icons.description_outlined),
    _NavItem('Settings', Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final page = switch (_index) {
      0 => OverviewPage(repository: widget.repository),
      1 => ExamsPage(repository: widget.repository),
      2 => UsersPage(repository: widget.repository),
      3 => ContentPage(repository: widget.repository),
      _ => SettingsPage(
        firebaseReady: widget.firebaseReady,
        adminSession: widget.adminSession,
        onLogout: widget.onLogout,
      ),
    };

    return Scaffold(
      drawer: wide ? null : Drawer(child: _buildSidebar()),
      appBar: wide
          ? null
          : AppBar(title: Text(_items[_index].label), actions: _topActions()),
      body: Row(
        children: [
          if (wide) SizedBox(width: 264, child: _buildSidebar()),
          Expanded(
            child: Column(
              children: [
                if (wide)
                  Container(
                    height: 72,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE1E7F2)),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 360,
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Search analytics...',
                              prefixIcon: const Icon(Icons.search),
                              contentPadding: EdgeInsets.zero,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(999),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        ..._topActions(),
                      ],
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: page,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _topActions() => [
    if (widget.adminSession != null)
      Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE0FFF9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFBDEEE5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF006B5F),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.adminSession!.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF006B5F),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    const SizedBox(width: 8),
    IconButton(
      tooltip: 'Notifications',
      onPressed: () {},
      icon: const Icon(Icons.notifications_none),
    ),
    IconButton(
      tooltip: 'Help',
      onPressed: () {},
      icon: const Icon(Icons.help_outline),
    ),
    const SizedBox(width: 8),
    OutlinedButton.icon(
      onPressed: () {},
      icon: const Icon(Icons.download_outlined),
      label: const Text('Export'),
    ),
  ];

  Widget _buildSidebar() => _Sidebar(
    items: _items,
    selectedIndex: _index,
    onSelected: (index) => setState(() => _index = index),
    adminSession: widget.adminSession,
    onLogout: widget.onLogout,
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.adminSession,
    required this.onLogout,
  });

  final List<_NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final AdminSession? adminSession;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF031632),
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TestPrep Admin',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Management Portal',
                    style: TextStyle(color: Color(0xFF8293B5)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            for (var i = 0; i < items.length; i++)
              _NavButton(
                item: items[i],
                active: selectedIndex == i,
                onTap: () {
                  onSelected(i);
                  if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                    Navigator.pop(context);
                  }
                },
              ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2B48),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFF006B5F),
                    child: Icon(
                      Icons.admin_panel_settings,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          adminSession?.name ?? 'Admin',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          adminSession?.role ?? 'admin',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF8293B5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Logout',
                    color: Colors.white,
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final _NavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        selected: active,
        selectedTileColor: const Color(0xFF6DF5E1),
        iconColor: active ? const Color(0xFF006F64) : const Color(0xFF8293B5),
        textColor: active ? const Color(0xFF006F64) : const Color(0xFF8293B5),
        leading: Icon(item.icon),
        title: Text(
          item.label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        onTap: onTap,
      ),
    );
  }
}

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.repository});

  final FirestoreRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: repository.exams(),
      builder: (context, examsSnapshot) {
        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: repository.users(),
          builder: (context, usersSnapshot) {
            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: repository.questions(),
              builder: (context, questionsSnapshot) {
                final exams =
                    examsSnapshot.data ?? const <Map<String, dynamic>>[];
                final users =
                    usersSnapshot.data ?? const <Map<String, dynamic>>[];
                final questions =
                    questionsSnapshot.data ?? const <Map<String, dynamic>>[];
                final tests = exams.fold<int>(
                  0,
                  (total, exam) => total + _asInt(exam['completions']),
                );
                final passRate = exams.isEmpty
                    ? 0.0
                    : exams.fold<double>(
                            0,
                            (total, exam) =>
                                total + _asDouble(exam['passRate']),
                          ) /
                          exams.length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PageHeader(
                      title: 'Platform Performance Analytics',
                      subtitle:
                          'Monitor pass rates, learner engagement, and content difficulty across all academic tracks.',
                      action: DropdownButton<String>(
                        value: 'Last 30 Days',
                        items: const [
                          DropdownMenuItem(
                            value: 'Last 30 Days',
                            child: Text('Last 30 Days'),
                          ),
                          DropdownMenuItem(
                            value: 'Last Quarter',
                            child: Text('Last Quarter'),
                          ),
                        ],
                        onChanged: (_) {},
                      ),
                    ),
                    const SizedBox(height: 24),
                    _ResponsiveGrid(
                      children: [
                        _MetricCard(
                          label: 'Daily Active Users',
                          value: _formatNumber(users.length),
                          trend: 'Live',
                          positive: true,
                          icon: Icons.groups_outlined,
                        ),
                        _MetricCard(
                          label: 'Avg. Pass Rate',
                          value: '${passRate.toStringAsFixed(1)}%',
                          trend: 'Live',
                          positive: true,
                          icon: Icons.trending_up,
                          progress: passRate / 100,
                        ),
                        _MetricCard(
                          label: 'Exams Completed',
                          value: _formatNumber(tests),
                          trend: 'Live',
                          positive: true,
                          icon: Icons.assignment_turned_in_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _ResponsiveGrid(
                      wideSpan: 2,
                      children: [
                        _ChartCard(exams: exams),
                        _DifficultyCard(questions: questions),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SectionCard(
                      title: 'Recent Exams',
                      child: exams.isEmpty
                          ? const _EmptyState(
                              icon: Icons.quiz_outlined,
                              title: 'No exams yet',
                              message: 'Create an exam to see it here.',
                            )
                          : Column(
                              children: exams
                                  .take(5)
                                  .map(
                                    (exam) => _DataRowTile(
                                      icon: Icons.quiz_outlined,
                                      title: exam['title'].toString(),
                                      subtitle:
                                          '${exam['category']} • ${_asInt(exam['questions'])} questions',
                                      trailing:
                                          '${_asDouble(exam['passRate']).toStringAsFixed(1)}%',
                                    ),
                                  )
                                  .toList(),
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class ExamsPage extends StatefulWidget {
  const ExamsPage({super.key, required this.repository});

  final FirestoreRepository repository;

  @override
  State<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends State<ExamsPage> {
  var _filter = 'All Exams';
  var _query = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.repository.exams(),
      builder: (context, snapshot) {
        final allExams = snapshot.data ?? const <Map<String, dynamic>>[];
        final exams = allExams.where((exam) {
          final category = exam['category']?.toString() ?? '';
          final title = exam['title']?.toString().toLowerCase() ?? '';
          final query = _query.trim().toLowerCase();
          final matchesFilter = _filter == 'All Exams' || category == _filter;
          final matchesSearch =
              query.isEmpty ||
              title.contains(query) ||
              category.toLowerCase().contains(query);
          return matchesFilter && matchesSearch;
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 16,
              runSpacing: 16,
              children: [
                const SizedBox(
                  width: 560,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Dashboard',
                            style: TextStyle(color: Color(0xFF5E6878)),
                          ),
                          Icon(Icons.chevron_right, size: 18),
                          Text(
                            'Exams',
                            style: TextStyle(
                              color: Color(0xFF031632),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Exam Management',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0B1C30),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Create, manage, and monitor academic mock tests from Firebase.',
                        style: TextStyle(color: Color(0xFF5E6878)),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          _showBulkMcqDialog(context, widget.repository),
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Bulk MCQs'),
                    ),
                    FilledButton.icon(
                      onPressed: () =>
                          _showExamDialog(context, widget.repository),
                      icon: const Icon(Icons.add),
                      label: const Text('Create New Exam'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Search exams by title or category...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _examFilterCategories
                  .map(
                    (category) => ChoiceChip(
                      label: Text(category),
                      selected: _filter == category,
                      onSelected: (_) => setState(() => _filter = category),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            _ExamManagementTable(exams: exams, repository: widget.repository),
          ],
        );
      },
    );
  }
}

class UsersPage extends StatelessWidget {
  const UsersPage({super.key, required this.repository});

  final FirestoreRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: repository.users(),
      builder: (context, snapshot) {
        final users = snapshot.data ?? const <Map<String, dynamic>>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(
              title: 'User Management',
              subtitle:
                  'Track learner plans, progress, and account status dynamically.',
              action: FilledButton.icon(
                onPressed: () => _showUserDialog(context, repository),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add User'),
              ),
            ),
            const SizedBox(height: 24),
            _SectionCard(
              title: 'Learners',
              child: users.isEmpty
                  ? const _EmptyState(
                      icon: Icons.group_outlined,
                      title: 'No users in Firebase',
                      message: 'Users will appear here after they are saved.',
                    )
                  : Column(
                      children: users
                          .map(
                            (user) => _DataRowTile(
                              icon: Icons.person_outline,
                              title: user['name'].toString(),
                              subtitle:
                                  '${user['email']} • ${user['plan']} • ${_asInt(user['tests'])} tests',
                              trailing:
                                  '${_asDouble(user['score']).toStringAsFixed(1)}%',
                              chipColor: user['status'] == 'Active'
                                  ? const Color(0xFFE0FFF9)
                                  : const Color(0xFFFFDAD6),
                              onTap: () => repository.updateStatus(
                                'users',
                                user['id']?.toString() ?? '',
                                user['status'] == 'Active'
                                    ? 'Suspended'
                                    : 'Active',
                              ),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class ContentPage extends StatelessWidget {
  const ContentPage({super.key, required this.repository});

  final FirestoreRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: repository.questions(),
      builder: (context, snapshot) {
        final questions = snapshot.data ?? const <Map<String, dynamic>>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeader(
              title: 'Content Library',
              subtitle:
                  'Add MCQ questions and save them to the questions collection.',
              action: FilledButton.icon(
                onPressed: () => _showQuestionDialog(context, repository),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add MCQ'),
              ),
            ),
            const SizedBox(height: 24),
            _SectionCard(
              title: 'MCQ Questions',
              child: questions.isEmpty
                  ? const _EmptyState(
                      icon: Icons.description_outlined,
                      title: 'No questions in Firebase',
                      message: 'Add MCQs to populate the question bank.',
                    )
                  : Column(
                      children: questions
                          .map(
                            (question) => _DataRowTile(
                              icon: Icons.description_outlined,
                              title: question['prompt'].toString(),
                              subtitle:
                                  '${question['exam']} • Answer: ${_answerText(question)}',
                              trailing: question['difficulty'].toString(),
                              chipColor: const Color(0xFFDCE9FF),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.firebaseReady,
    required this.adminSession,
    required this.onLogout,
  });

  final bool firebaseReady;
  final AdminSession? adminSession;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PageHeader(
          title: 'Settings',
          subtitle:
              'Firebase Web settings and admin session behavior for the portal.',
        ),
        const SizedBox(height: 24),
        _SectionCard(
          title: 'Admin Account',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DataRowTile(
                icon: Icons.admin_panel_settings,
                title: adminSession?.name ?? 'No admin session',
                subtitle: adminSession?.email ?? 'Sign in to view admin email',
                trailing: adminSession?.role ?? 'Signed out',
                chipColor: const Color(0xFFE0FFF9),
              ),
              const SizedBox(height: 8),
              _DataRowTile(
                icon: adminSession == null
                    ? Icons.lock_outline
                    : Icons.verified_user_outlined,
                title: adminSession == null ? 'Signed out' : 'Signed in',
                subtitle: adminSession == null
                    ? 'No active admin session'
                    : 'Admin permissions loaded from Firestore',
                trailing: adminSession == null ? 'Inactive' : 'Active',
                chipColor: adminSession == null
                    ? const Color(0xFFFFDAD6)
                    : const Color(0xFFE0FFF9),
              ),
              const SizedBox(height: 12),
              SelectableText(
                'UID: ${adminSession?.id.isNotEmpty == true ? adminSession!.id : 'Not available'}',
                style: const TextStyle(color: Color(0xFF5E6878)),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _SectionCard(
          title: 'Firebase Status',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DataRowTile(
                icon: firebaseReady ? Icons.cloud_done : Icons.cloud_off,
                title: firebaseReady
                    ? 'Connected to Firestore'
                    : 'Firebase is not connected',
                subtitle: firebaseReady
                    ? 'Reads and writes are using Firebase Cloud Firestore.'
                    : 'Check the FlutterFire CLI configuration and Firebase project access.',
                trailing: firebaseReady ? 'Online' : 'Offline',
                chipColor: firebaseReady
                    ? const Color(0xFFE0FFF9)
                    : const Color(0xFFFFF5D8),
              ),
              const SizedBox(height: 16),
              const Text(
                'Firebase is configured through lib/firebase_options.dart generated by FlutterFire CLI.',
                style: TextStyle(color: Color(0xFF5E6878)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.title, required this.subtitle, this.action});

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 16,
      runSpacing: 16,
      children: [
        SizedBox(
          width: 680,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0B1C30),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.45,
                  color: Color(0xFF44474D),
                ),
              ),
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

class _ResponsiveGrid extends StatelessWidget {
  const _ResponsiveGrid({required this.children, this.wideSpan = 3});

  final List<Widget> children;
  final int wideSpan;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width > 1180
        ? wideSpan
        : width > 760
        ? 2
        : 1;
    return GridView.count(
      crossAxisCount: columns,
      childAspectRatio: columns == 1 ? 1.35 : 1,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: children,
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.trend,
    required this.positive,
    required this.icon,
    this.progress,
  });

  final String label;
  final String value;
  final String trend;
  final bool positive;
  final IconData icon;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF006B5F)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(color: Color(0xFF44474D)),
                  ),
                ),
                Text(
                  trend,
                  style: TextStyle(
                    color: positive
                        ? const Color(0xFF006B5F)
                        : const Color(0xFFBA1A1A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0B1C30),
              ),
            ),
            const SizedBox(height: 16),
            if (progress == null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [40, 55, 45, 70, 60, 85, 75]
                    .map(
                      (height) => Expanded(
                        child: Container(
                          height: height / 1.8,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: const BoxDecoration(
                            color: Color(0xFF4FDBC8),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              )
            else
              LinearProgressIndicator(
                value: progress!.clamp(0, 1),
                minHeight: 9,
                borderRadius: BorderRadius.circular(999),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.exams});

  final List<Map<String, dynamic>> exams;

  @override
  Widget build(BuildContext context) {
    if (exams.isEmpty) {
      return const _SectionCard(
        title: 'Completion Volume',
        child: _EmptyState(
          icon: Icons.bar_chart_outlined,
          title: 'No completion data',
          message: 'Exam completions from Firebase will appear here.',
        ),
      );
    }

    final maxValue = exams.fold<int>(
      1,
      (max, exam) =>
          _asInt(exam['completions']) > max ? _asInt(exam['completions']) : max,
    );
    return _SectionCard(
      title: 'Completion Volume',
      child: SizedBox(
        height: 180,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: exams
              .map(
                (exam) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor:
                                  (_asInt(exam['completions']) / maxValue)
                                      .clamp(.08, 1),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF006B5F),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          exam['category'].toString(),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({required this.questions});

  final List<Map<String, dynamic>> questions;

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return const _SectionCard(
        title: 'Question Difficulty',
        child: _EmptyState(
          icon: Icons.insights_outlined,
          title: 'No difficulty data',
          message: 'Question difficulty totals will appear here.',
        ),
      );
    }

    final counts = <String, int>{'Easy': 0, 'Medium': 0, 'Hard': 0};
    for (final question in questions) {
      final difficulty = question['difficulty']?.toString() ?? 'Medium';
      counts[difficulty] = (counts[difficulty] ?? 0) + 1;
    }
    return _SectionCard(
      title: 'Question Difficulty',
      child: Column(
        children: counts.entries
            .map(
              (entry) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    SizedBox(width: 74, child: Text(entry.key)),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: questions.isEmpty
                            ? 0
                            : entry.value / questions.length,
                        minHeight: 12,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${entry.value}'),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FF),
        border: Border.all(color: const Color(0xFFE1E7F2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: const Color(0xFF8293B5)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0B1C30),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF5E6878)),
          ),
        ],
      ),
    );
  }
}

class _DataRowTile extends StatelessWidget {
  const _DataRowTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.chipColor,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final Color? chipColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFDCE9FF),
        child: Icon(icon, color: const Color(0xFF031632)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: chipColor ?? const Color(0xFFEFF4FF),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          trailing,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
      ),
      onTap: onTap,
    );
  }
}

class _ExamManagementTable extends StatelessWidget {
  const _ExamManagementTable({required this.exams, required this.repository});

  final List<Map<String, dynamic>> exams;
  final FirestoreRepository repository;

  @override
  Widget build(BuildContext context) {
    if (exams.isEmpty) {
      return const _SectionCard(
        title: 'All Exams',
        child: _EmptyState(
          icon: Icons.quiz_outlined,
          title: 'No exams in Firebase',
          message: 'Create an exam or change the filter to see tests here.',
        ),
      );
    }

    return Card(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFEFF4FF)),
            columns: const [
              DataColumn(label: Text('Exam Title')),
              DataColumn(label: Text('Category')),
              DataColumn(numeric: true, label: Text('Questions')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Last Updated')),
              DataColumn(label: Text('Actions')),
            ],
            rows: exams
                .map(
                  (exam) => _ExamTableRow(
                    context: context,
                    exam: exam,
                    repository: repository,
                  ).build(),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _ExamTableRow {
  const _ExamTableRow({
    required this.context,
    required this.exam,
    required this.repository,
  });

  final BuildContext context;

  final Map<String, dynamic> exam;
  final FirestoreRepository repository;

  DataRow build() {
    final status = exam['status']?.toString() ?? 'Draft';
    final disabled = status == 'Disabled';
    final id = exam['id']?.toString() ?? '';

    return DataRow(
      cells: [
        DataCell(
          SizedBox(
            width: 280,
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: disabled
                        ? const Color(0xFFFFDAD6)
                        : const Color(0xFFD7E2FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    disabled ? Icons.pause_circle_outline : Icons.menu_book,
                    color: const Color(0xFF031632),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exam['title']?.toString() ?? 'Untitled Exam',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${_subjectBreakdown(exam).length} subject groups',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF5E6878),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        DataCell(
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text(exam['category']?.toString() ?? 'Uncategorized'),
          ),
        ),
        DataCell(Text(_asInt(exam['questions']).toString())),
        DataCell(_StatusLine(status: status)),
        DataCell(
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_formatTimestamp(exam['updatedAt'] ?? exam['createdAt'])),
              const Text(
                'Firestore',
                style: TextStyle(color: Color(0xFF5E6878), fontSize: 11),
              ),
            ],
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Add MCQs',
                onPressed: () => _showBulkMcqDialog(
                  context,
                  repository,
                  initialExam: exam['title']?.toString(),
                ),
                icon: const Icon(Icons.playlist_add),
              ),
              IconButton(
                tooltip: 'Edit',
                onPressed: () =>
                    _showExamDialog(context, repository, existingExam: exam),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: disabled ? 'Enable' : 'Disable',
                onPressed: () => repository.updateStatus(
                  'exams',
                  id,
                  disabled ? 'Published' : 'Disabled',
                ),
                icon: Icon(disabled ? Icons.play_arrow : Icons.block),
              ),
              IconButton(
                tooltip: 'Delete',
                color: const Color(0xFFBA1A1A),
                onPressed: () => _confirmDeleteExam(context, repository, exam),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'Published' => const Color(0xFF006B5F),
      'Disabled' => const Color(0xFFBA1A1A),
      _ => const Color(0xFF806000),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          status,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

Future<void> _showExamDialog(
  BuildContext context,
  FirestoreRepository repository, {
  Map<String, dynamic>? existingExam,
}) async {
  final editing = existingExam != null;
  final breakdown = _subjectBreakdown(existingExam);
  final totalMcqs = _asInt(existingExam?['questions'] ?? _dailyPracticeTotal);
  final title = TextEditingController(
    text: existingExam?['title']?.toString() ?? 'Daily Practice',
  );
  final category = TextEditingController(
    text: existingExam?['category']?.toString() ?? 'Daily Practice',
  );
  final questions = TextEditingController(
    text: _asInt(existingExam?['questions'] ?? totalMcqs).toString(),
  );
  final completions = TextEditingController(
    text: _asInt(existingExam?['completions']).toString(),
  );
  final passRate = TextEditingController(
    text: _asDouble(existingExam?['passRate'] ?? 70).toStringAsFixed(1),
  );
  final prompt = TextEditingController();
  final optionA = TextEditingController();
  final optionB = TextEditingController();
  final optionC = TextEditingController();
  final optionD = TextEditingController();
  var answerIndex = 0;
  var difficulty = 'Medium';
  var status = existingExam?['status']?.toString() ?? 'Draft';
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        insetPadding: const EdgeInsets.all(24),
        contentPadding: EdgeInsets.zero,
        titlePadding: EdgeInsets.zero,
        actionsPadding: EdgeInsets.zero,
        content: SizedBox(
          width: 980,
          height: MediaQuery.sizeOf(context).height * .86,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Exams', style: TextStyle(color: Color(0xFF5E6878))),
                    Icon(Icons.chevron_right, size: 18),
                    Text(
                      'Daily Practice',
                      style: TextStyle(
                        color: Color(0xFF031632),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF4FF),
                    border: Border.all(color: const Color(0xFFE1E7F2)),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2B48),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.post_add,
                          color: Color(0xFF71F8E4),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              editing ? 'Edit Exam' : 'Create New Exam',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Daily Practice uses the required 100 MCQ subject pattern. Add an optional first MCQ below.',
                              style: TextStyle(color: Color(0xFF5E6878)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFE1E7F2)),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(8),
                    ),
                  ),
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stacked = constraints.maxWidth < 760;
                          final details = _ExamDetailsForm(
                            title: title,
                            category: category,
                            questions: questions,
                            completions: completions,
                            passRate: passRate,
                            status: status,
                            onStatusChanged: (value) =>
                                setDialogState(() => status = value ?? status),
                          );
                          final subjectTable = _DailyPracticeTable(
                            subjects: breakdown,
                            total: totalMcqs,
                          );
                          if (stacked) {
                            return Column(
                              children: [
                                details,
                                const SizedBox(height: 20),
                                subjectTable,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: details),
                              const SizedBox(width: 24),
                              Expanded(child: subjectTable),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      _InlineQuestionEditor(
                        prompt: prompt,
                        optionA: optionA,
                        optionB: optionB,
                        optionC: optionC,
                        optionD: optionD,
                        answerIndex: answerIndex,
                        difficulty: difficulty,
                        onAnswerChanged: (value) => setDialogState(
                          () => answerIndex = value ?? answerIndex,
                        ),
                        onDifficultyChanged: (value) => setDialogState(
                          () => difficulty = value ?? difficulty,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () async {
                        try {
                          await repository.saveExam(
                            id: existingExam?['id']?.toString(),
                            title: title.text.trim().isEmpty
                                ? 'Daily Practice'
                                : title.text.trim(),
                            category: category.text.trim().isEmpty
                                ? 'Daily Practice'
                                : category.text.trim(),
                            questions:
                                int.tryParse(questions.text) ?? totalMcqs,
                            completions: int.tryParse(completions.text) ?? 0,
                            passRate: double.tryParse(passRate.text) ?? 0,
                            status: status,
                            subjectBreakdown: breakdown,
                            questionPrompt: prompt.text,
                            questionOptions: [
                              optionA.text,
                              optionB.text,
                              optionC.text,
                              optionD.text,
                            ],
                            answerIndex: answerIndex,
                            difficulty: difficulty,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          _showSnack(
                            context,
                            editing ? 'Exam updated.' : 'Exam saved.',
                          );
                        } catch (error) {
                          if (!context.mounted) return;
                          _showSnack(
                            context,
                            'Save failed: $error',
                            error: true,
                          );
                        }
                      },
                      icon: Icon(editing ? Icons.save_outlined : Icons.add),
                      label: Text(editing ? 'Save Changes' : 'Create Exam'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ExamDetailsForm extends StatelessWidget {
  const _ExamDetailsForm({
    required this.title,
    required this.category,
    required this.questions,
    required this.completions,
    required this.passRate,
    required this.status,
    required this.onStatusChanged,
  });

  final TextEditingController title;
  final TextEditingController category;
  final TextEditingController questions;
  final TextEditingController completions;
  final TextEditingController passRate;
  final String status;
  final ValueChanged<String?> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FormSectionLabel('Exam Details*'),
        const SizedBox(height: 12),
        TextField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Exam title'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: category,
          decoration: const InputDecoration(labelText: 'Category'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: questions,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Total MCQs'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'Draft', child: Text('Draft')),
                  DropdownMenuItem(
                    value: 'Published',
                    child: Text('Published'),
                  ),
                  DropdownMenuItem(value: 'Disabled', child: Text('Disabled')),
                ],
                onChanged: onStatusChanged,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: completions,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Completions'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: passRate,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Pass rate'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DailyPracticeTable extends StatelessWidget {
  const _DailyPracticeTable({required this.subjects, required this.total});

  final List<Map<String, dynamic>> subjects;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FormSectionLabel('Daily Practice (100 MCQs)'),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE1E7F2)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _SubjectRow(subject: 'Subject', mcqs: 'MCQs', header: true),
              for (final subject in subjects)
                _SubjectRow(
                  subject: subject['subject']?.toString() ?? '',
                  mcqs: _asInt(subject['mcqs']).toString(),
                ),
              _SubjectRow(
                subject: 'Total',
                mcqs: total.toString(),
                header: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({
    required this.subject,
    required this.mcqs,
    this.header = false,
  });

  final String subject;
  final String mcqs;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: header ? const Color(0xFFEFF4FF) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              subject,
              style: TextStyle(
                fontWeight: header ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            mcqs,
            style: TextStyle(
              fontWeight: header ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineQuestionEditor extends StatelessWidget {
  const _InlineQuestionEditor({
    required this.prompt,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    required this.optionD,
    required this.answerIndex,
    required this.difficulty,
    required this.onAnswerChanged,
    required this.onDifficultyChanged,
  });

  final TextEditingController prompt;
  final TextEditingController optionA;
  final TextEditingController optionB;
  final TextEditingController optionC;
  final TextEditingController optionD;
  final int answerIndex;
  final String difficulty;
  final ValueChanged<int?> onAnswerChanged;
  final ValueChanged<String?> onDifficultyChanged;

  @override
  Widget build(BuildContext context) {
    final options = [
      ('A', optionA),
      ('B', optionB),
      ('C', optionC),
      ('D', optionD),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 22),
        const _FormSectionLabel('Add Question'),
        const SizedBox(height: 12),
        TextField(
          controller: prompt,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Question Text',
            hintText: 'Enter the MCQ question here...',
          ),
        ),
        const SizedBox(height: 18),
        const _FormSectionLabel('Answer Options*'),
        const SizedBox(height: 12),
        for (var i = 0; i < options.length; i++) ...[
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFD7E2FF),
                child: Text(
                  options[i].$1,
                  style: const TextStyle(
                    color: Color(0xFF031632),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: options[i].$2,
                  decoration: InputDecoration(
                    labelText: 'Option ${options[i].$1}',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: 'Mark option ${options[i].$1} as correct',
                child: IconButton.filledTonal(
                  isSelected: answerIndex == i,
                  onPressed: () => onAnswerChanged(i),
                  icon: const Icon(Icons.check_circle_outline),
                  selectedIcon: const Icon(Icons.check_circle),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: difficulty,
                decoration: const InputDecoration(labelText: 'Difficulty'),
                items: const [
                  DropdownMenuItem(value: 'Easy', child: Text('Easy')),
                  DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'Hard', child: Text('Hard')),
                ],
                onChanged: onDifficultyChanged,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Leave this section empty if you only want to create the exam.',
                style: TextStyle(color: Color(0xFF5E6878)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FormSectionLabel extends StatelessWidget {
  const _FormSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF0B1C30),
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: .6,
      ),
    );
  }
}

Future<void> _confirmDeleteExam(
  BuildContext context,
  FirestoreRepository repository,
  Map<String, dynamic> exam,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete exam?'),
      content: Text(
        'This will permanently delete "${exam['title'] ?? 'this exam'}" from Firestore.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFBA1A1A),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed ?? false) {
    await repository.deleteExam(exam['id']?.toString() ?? '');
  }
}

Future<void> _showBulkMcqDialog(
  BuildContext context,
  FirestoreRepository repository, {
  String? initialExam,
}) async {
  final exam = TextEditingController(text: initialExam ?? '');
  final raw = TextEditingController();
  var subject = _mcqSubjects.first;
  var difficulty = 'Medium';
  var parsed = const <McqDraft>[];
  String? error;

  void refreshPreview(void Function(void Function()) setDialogState) {
    setDialogState(() {
      parsed = _parseBulkMcqs(
        raw.text,
        exam: exam.text.trim(),
        subject: subject,
        difficulty: difficulty,
      );
      error = parsed.isEmpty
          ? 'Paste MCQs with A/B/C/D options and a checked answer or answer key.'
          : null;
    });
  }

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        insetPadding: const EdgeInsets.all(24),
        title: const Text('Bulk Add MCQs'),
        content: SizedBox(
          width: 860,
          height: MediaQuery.sizeOf(context).height * .76,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: exam,
                      decoration: const InputDecoration(labelText: 'Exam name'),
                      onChanged: (_) => refreshPreview(setDialogState),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: subject,
                      decoration: const InputDecoration(labelText: 'Subject'),
                      items: _mcqSubjects
                          .map(
                            (name) => DropdownMenuItem(
                              value: name,
                              child: Text(name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        subject = value ?? subject;
                        refreshPreview(setDialogState);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: difficulty,
                      decoration: const InputDecoration(
                        labelText: 'Difficulty',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Easy', child: Text('Easy')),
                        DropdownMenuItem(
                          value: 'Medium',
                          child: Text('Medium'),
                        ),
                        DropdownMenuItem(value: 'Hard', child: Text('Hard')),
                      ],
                      onChanged: (value) {
                        difficulty = value ?? difficulty;
                        refreshPreview(setDialogState);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: TextField(
                  controller: raw,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    alignLabelWithHint: true,
                    labelText: 'Paste MCQs with answer key',
                    hintText:
                        'Choose the correct spelling:\nA) Accomodation\nB) Accommodation ✅\nC) Acommodation\nD) Accommadation\n\nAnswer Key: 1-B, 2-C',
                  ),
                  onChanged: (_) => refreshPreview(setDialogState),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Chip(
                    avatar: const Icon(Icons.fact_check_outlined, size: 18),
                    label: Text('${parsed.length} MCQs parsed'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      error ??
                          'Ready to save to Firebase questions collection.',
                      style: TextStyle(
                        color: error == null
                            ? const Color(0xFF006B5F)
                            : const Color(0xFFBA1A1A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: parsed.isEmpty || exam.text.trim().isEmpty
                ? null
                : () async {
                    try {
                      await repository.addQuestions(parsed);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      _showSnack(context, '${parsed.length} MCQs saved.');
                    } catch (error) {
                      if (!context.mounted) return;
                      _showSnack(
                        context,
                        'MCQ save failed: $error',
                        error: true,
                      );
                    }
                  },
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Save MCQs'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showUserDialog(
  BuildContext context,
  FirestoreRepository repository,
) async {
  final name = TextEditingController();
  final email = TextEditingController();
  final tests = TextEditingController(text: '0');
  final score = TextEditingController(text: '0');
  var plan = 'Free';
  var status = 'Active';
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Add User'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Full name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: plan,
                  decoration: const InputDecoration(labelText: 'Plan'),
                  items: const [
                    DropdownMenuItem(value: 'Free', child: Text('Free')),
                    DropdownMenuItem(value: 'Premium', child: Text('Premium')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => plan = value ?? plan),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tests,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Tests taken'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: score,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Average score'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'Active', child: Text('Active')),
                    DropdownMenuItem(
                      value: 'Suspended',
                      child: Text('Suspended'),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => status = value ?? status),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await repository.addUser(
                name: name.text.trim(),
                email: email.text.trim(),
                plan: plan,
                tests: int.tryParse(tests.text) ?? 0,
                score: double.tryParse(score.text) ?? 0,
                status: status,
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showQuestionDialog(
  BuildContext context,
  FirestoreRepository repository,
) async {
  final exam = TextEditingController();
  final prompt = TextEditingController();
  final optionA = TextEditingController();
  final optionB = TextEditingController();
  final optionC = TextEditingController();
  final optionD = TextEditingController();
  var answerIndex = 0;
  var difficulty = 'Medium';
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Add MCQ Question'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: exam,
                  decoration: const InputDecoration(labelText: 'Exam name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: prompt,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Question'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: optionA,
                  decoration: const InputDecoration(labelText: 'Option A'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: optionB,
                  decoration: const InputDecoration(labelText: 'Option B'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: optionC,
                  decoration: const InputDecoration(labelText: 'Option C'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: optionD,
                  decoration: const InputDecoration(labelText: 'Option D'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: answerIndex,
                        decoration: const InputDecoration(
                          labelText: 'Correct answer',
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('A')),
                          DropdownMenuItem(value: 1, child: Text('B')),
                          DropdownMenuItem(value: 2, child: Text('C')),
                          DropdownMenuItem(value: 3, child: Text('D')),
                        ],
                        onChanged: (value) => setDialogState(
                          () => answerIndex = value ?? answerIndex,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: difficulty,
                        decoration: const InputDecoration(
                          labelText: 'Difficulty',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Easy', child: Text('Easy')),
                          DropdownMenuItem(
                            value: 'Medium',
                            child: Text('Medium'),
                          ),
                          DropdownMenuItem(value: 'Hard', child: Text('Hard')),
                        ],
                        onChanged: (value) => setDialogState(
                          () => difficulty = value ?? difficulty,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await repository.addQuestion(
                  exam: exam.text.trim(),
                  prompt: prompt.text.trim(),
                  options: [
                    optionA.text.trim(),
                    optionB.text.trim(),
                    optionC.text.trim(),
                    optionD.text.trim(),
                  ],
                  answerIndex: answerIndex,
                  difficulty: difficulty,
                );
                if (!context.mounted) return;
                Navigator.pop(context);
                _showSnack(context, 'MCQ saved.');
              } catch (error) {
                if (!context.mounted) return;
                _showSnack(context, 'MCQ save failed: $error', error: true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

void _showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? const Color(0xFFBA1A1A) : null,
    ),
  );
}

List<McqDraft> _parseBulkMcqs(
  String text, {
  required String exam,
  required String subject,
  required String difficulty,
}) {
  final answersByNumber = <int, int>{};
  final answerPattern = RegExp(r'(\d+)\s*[-–]\s*([A-D])', caseSensitive: false);
  for (final match in answerPattern.allMatches(text)) {
    final number = int.tryParse(match.group(1) ?? '');
    final answer = match.group(2)?.toUpperCase();
    if (number != null && answer != null) {
      answersByNumber[number] = answer.codeUnitAt(0) - 'A'.codeUnitAt(0);
    }
  }

  final drafts = <McqDraft>[];
  String? prompt;
  final options = <String>[];
  int? checkedAnswer;

  void commit() {
    if (prompt == null || options.length != 4) return;
    final answerIndex =
        checkedAnswer ?? answersByNumber[drafts.length + 1] ?? 0;
    drafts.add(
      McqDraft(
        exam: exam,
        subject: subject,
        prompt: prompt.trim(),
        options: List<String>.from(options),
        answerIndex: answerIndex.clamp(0, 3).toInt(),
        difficulty: difficulty,
      ),
    );
  }

  final optionPattern = RegExp(r'^([A-D])[\).]\s*(.+)$', caseSensitive: false);
  for (final rawLine in text.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line.toLowerCase().startsWith('answer key')) break;
    if (RegExp(r'mcqs\s*\(\d+', caseSensitive: false).hasMatch(line)) {
      continue;
    }

    final optionMatch = optionPattern.firstMatch(line);
    if (optionMatch != null && prompt != null) {
      final optionLetter = optionMatch.group(1)!.toUpperCase();
      final hasCheck = line.contains('✅');
      final optionText = optionMatch.group(2)!.replaceAll('✅', '').trim();
      options.add(optionText);
      if (hasCheck) {
        checkedAnswer = optionLetter.codeUnitAt(0) - 'A'.codeUnitAt(0);
      }
      if (options.length == 4) {
        commit();
        prompt = null;
        options.clear();
        checkedAnswer = null;
      }
      continue;
    }

    if (prompt != null && options.isNotEmpty) {
      commit();
      options.clear();
      checkedAnswer = null;
    }
    prompt = line;
  }

  return drafts;
}

String _formatNumber(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final reverseIndex = text.length - i;
    buffer.write(text[i]);
    if (reverseIndex > 1 && reverseIndex % 3 == 1) buffer.write(',');
  }
  return buffer.toString();
}

String _formatTimestamp(Object? value) {
  DateTime? date;
  if (value is Timestamp) {
    date = value.toDate();
  } else if (value is DateTime) {
    date = value;
  }
  if (date == null) return 'Not saved';
  final month = const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][date.month - 1];
  return '$month ${date.day}, ${date.year}';
}

List<Map<String, dynamic>> _subjectBreakdown(Map<String, dynamic>? exam) {
  final raw = exam?['subjectBreakdown'];
  if (raw is List) {
    final parsed = raw
        .whereType<Map>()
        .map(
          (subject) => <String, dynamic>{
            'subject': subject['subject']?.toString() ?? '',
            'mcqs': _asInt(subject['mcqs']),
          },
        )
        .where((subject) => subject['subject'].toString().isNotEmpty)
        .toList();
    if (parsed.isNotEmpty) return parsed;
  }
  return _dailyPracticeSubjects
      .map((subject) => <String, dynamic>{...subject})
      .toList();
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _answerText(Map<String, dynamic> question) {
  final options = question['options'];
  final answerIndex = _asInt(question['answerIndex']);
  if (options is List && answerIndex >= 0 && answerIndex < options.length) {
    return options[answerIndex].toString();
  }
  return 'Not set';
}
