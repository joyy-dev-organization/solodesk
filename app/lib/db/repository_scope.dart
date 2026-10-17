import 'package:flutter/widgets.dart';
import 'preference_repository.dart';
import 'client_repository.dart';
import 'project_repository.dart';
import 'scope_repository.dart';
import 'demo_data_repository.dart';

class RepositoryScope extends InheritedWidget {
  final IPreferenceRepository preferenceRepo;
  final IClientRepository clientRepo;
  final IProjectRepository projectRepo;
  final IScopeRepository scopeRepo;
  final IDemoDataRepository demoDataRepo;

  const RepositoryScope({
    super.key,
    required this.preferenceRepo,
    required this.clientRepo,
    required this.projectRepo,
    required this.scopeRepo,
    required this.demoDataRepo,
    required super.child,
  });

  static RepositoryScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RepositoryScope>();
    if (scope == null) {
      throw StateError('No RepositoryScope found in BuildContext widget tree');
    }
    return scope;
  }

  @override
  bool updateShouldNotify(RepositoryScope oldWidget) => false;
}
