import '../../models/law_firm_license.dart';

/// Espelho do seed de `law_firm_license_plans` (migration 20260821120000) —
/// usado no modo demo, onde a paywall precisa ser atravessável para o fluxo
/// inteiro ser demonstrável.
const mockLicensePlans = [
  LicensePlan(
    code: 'essencial',
    name: 'Essencial',
    maxLawyers: 3,
    monthlyPriceCents: 14900,
    annualPriceCents: 148800,
    sortOrder: 10,
  ),
  LicensePlan(
    code: 'escritorio',
    name: 'Escritório',
    maxLawyers: 10,
    monthlyPriceCents: 34900,
    annualPriceCents: 348000,
    sortOrder: 20,
  ),
  LicensePlan(
    code: 'banca',
    name: 'Banca',
    maxLawyers: 25,
    monthlyPriceCents: 69900,
    annualPriceCents: 696000,
    sortOrder: 30,
  ),
];
