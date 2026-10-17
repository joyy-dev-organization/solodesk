import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app_shell.dart';
import 'db/database_service.dart';
import 'db/client_repository.dart';
import 'db/demo_data_repository.dart';
import 'db/preference_repository.dart';
import 'db/project_repository.dart';
import 'db/repository_scope.dart';
import 'db/scope_repository.dart';
import 'db/invoice_repository.dart';
import 'services/service_health.dart';
import 'theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite FFI for Windows desktop
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Open default local SQLite database
  final dbService = await DatabaseService.openDefault();

  final preferenceRepo = PreferenceRepository(dbService.db);
  final clientRepo = ClientRepository(dbService.db);
  final projectRepo = ProjectRepository(dbService.db);
  final scopeRepo = ScopeRepository(dbService.db);
  final demoDataRepo = DemoDataRepository(dbService.db);
  final invoiceRepo = InvoiceRepository(dbService.db);

  runApp(
    SoloDeskApp(
      preferenceRepo: preferenceRepo,
      clientRepo: clientRepo,
      projectRepo: projectRepo,
      scopeRepo: scopeRepo,
      demoDataRepo: demoDataRepo,
      invoiceRepo: invoiceRepo,
    ),
  );
}

class SoloDeskApp extends StatelessWidget {
  final IPreferenceRepository preferenceRepo;
  final IClientRepository clientRepo;
  final IProjectRepository projectRepo;
  final IScopeRepository scopeRepo;
  final IDemoDataRepository demoDataRepo;
  final IInvoiceRepository invoiceRepo;
  final ServiceHealthClient? healthClient;
  final bool enableHealthPolling;

  const SoloDeskApp({
    super.key,
    required this.preferenceRepo,
    required this.clientRepo,
    required this.projectRepo,
    required this.scopeRepo,
    required this.demoDataRepo,
    required this.invoiceRepo,
    this.healthClient,
    this.enableHealthPolling = true,
  });

  @override
  Widget build(BuildContext context) {
    return RepositoryScope(
      preferenceRepo: preferenceRepo,
      clientRepo: clientRepo,
      projectRepo: projectRepo,
      scopeRepo: scopeRepo,
      demoDataRepo: demoDataRepo,
      invoiceRepo: invoiceRepo,
      child: MaterialApp(
        title: 'SoloDesk',
        debugShowCheckedModeBanner: false,
        theme: SoloDeskTheme.lightTheme,
        home: AppShell(
          healthClient: healthClient ?? ServiceHealthClient(),
          enableHealthPolling: enableHealthPolling,
        ),
      ),
    );
  }
}
