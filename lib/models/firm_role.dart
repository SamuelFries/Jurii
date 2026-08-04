enum FirmRole {
  // 'owner' e o identificador do banco (roles && array['owner', ...] em
  // dezenas de RPCs); muda so o rotulo que o usuario le.
  owner('owner', 'Sócio(a)', 'Sócio'),
  admin('admin', 'Admin', 'Admin'),
  lawyer('lawyer', 'Advogado(a)', 'Advogado'),
  secretary('secretary', 'Secretário(a)', 'Secretaria'),
  intern('intern', 'Estagiário(a)', 'Estagiário');

  const FirmRole(this.value, this.label, this.shortLabel);

  final String value;
  final String label;
  final String shortLabel;

  static const orderedValues = [
    FirmRole.owner,
    FirmRole.admin,
    FirmRole.lawyer,
    FirmRole.secretary,
    FirmRole.intern,
  ];

  static FirmRole fromValue(String? value) {
    return switch (value?.trim()) {
      'owner' => FirmRole.owner,
      'admin' => FirmRole.admin,
      'lawyer' => FirmRole.lawyer,
      'secretary' => FirmRole.secretary,
      'intern' => FirmRole.intern,
      _ => FirmRole.lawyer,
    };
  }

  static List<FirmRole> normalize(Iterable<FirmRole> roles) {
    final uniqueRoles = roles.toSet();
    final orderedRoles = orderedValues
        .where((role) => uniqueRoles.contains(role))
        .toList(growable: false);
    return orderedRoles.isEmpty ? const [FirmRole.lawyer] : orderedRoles;
  }

  static FirmRole primaryFrom(Iterable<FirmRole> roles) {
    return normalize(roles).first;
  }
}

extension FirmRoleCollectionPermissions on Iterable<FirmRole> {
  bool get hasOwner => contains(FirmRole.owner);
  bool get hasAdmin => contains(FirmRole.admin);
  bool get hasLawyer => contains(FirmRole.lawyer);
  bool get hasSecretary => contains(FirmRole.secretary);
  bool get hasIntern => contains(FirmRole.intern);

  bool get canManageFirmMembers => hasOwner || hasAdmin;
  bool get canAssignFirmCases => hasOwner || hasAdmin || hasSecretary;

  /// Quem fala pelo escritório com o cliente e pode indicar um advogado da
  /// equipe. Estagiário não indica. (Mesmo conjunto do gate no banco,
  /// `can_recommend_law_firm_lawyer`.)
  bool get canRecommendFirmLawyers =>
      hasLawyer || hasOwner || hasAdmin || hasSecretary;
  bool get canAttendAssignedFirmCases => hasLawyer;

  String get labels =>
      FirmRole.normalize(this).map((role) => role.shortLabel).join(' / ');

  List<String> get values => FirmRole.normalize(
    this,
  ).map((role) => role.value).toList(growable: false);
}
