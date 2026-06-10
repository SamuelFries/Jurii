import '../../models/lawyer_status.dart';
import '../../models/user_profile.dart';

const mockCurrentUser = UserProfile(
  id: 'user_joao_silva',
  name: 'João Silva',
  email: 'joao.silva@email.com',
  initials: 'JS',
  memberSince: 'Cliente desde Junho de 2026',
  lawyerStatus: LawyerStatus.approved,
  oabNumber: 'OAB/SP 123456',
);
