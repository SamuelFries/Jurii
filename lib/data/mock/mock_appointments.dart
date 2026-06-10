import '../../models/appointment.dart';

const mockClientAppointments = [
  Appointment(
    id: 'client_agenda_01',
    role: AppointmentRole.client,
    title: 'Consulta inicial',
    counterpartName: 'Fries Advogados',
    area: 'Direito Trabalhista',
    dateLabel: 'Hoje',
    timeLabel: '15:30',
    location: 'Videochamada',
    status: AppointmentStatus.confirmed,
  ),
  Appointment(
    id: 'client_agenda_02',
    role: AppointmentRole.client,
    title: 'Envio de documentos',
    counterpartName: 'Silva & Associados',
    area: 'Direito de Família',
    dateLabel: 'Amanhã',
    timeLabel: '10:00',
    location: 'Pelo app',
    status: AppointmentStatus.pending,
  ),
];

const mockLawyerAppointments = [
  Appointment(
    id: 'lawyer_agenda_01',
    role: AppointmentRole.lawyer,
    title: 'Reunião inicial',
    counterpartName: 'Ana Pereira',
    area: 'Direito de Família',
    dateLabel: 'Hoje',
    timeLabel: '09:30',
    location: 'Videochamada',
    status: AppointmentStatus.confirmed,
  ),
  Appointment(
    id: 'lawyer_agenda_02',
    role: AppointmentRole.lawyer,
    title: 'Análise de documentos',
    counterpartName: 'João Silva',
    area: 'Trabalhista',
    dateLabel: 'Hoje',
    timeLabel: '14:00',
    location: 'Painel do caso',
    status: AppointmentStatus.pending,
  ),
  Appointment(
    id: 'lawyer_agenda_03',
    role: AppointmentRole.lawyer,
    title: 'Retorno ao cliente',
    counterpartName: 'Carlos Oliveira',
    area: 'Previdenciário',
    dateLabel: 'Amanhã',
    timeLabel: '16:30',
    location: 'Telefone',
    status: AppointmentStatus.confirmed,
  ),
];
