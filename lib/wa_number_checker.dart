/// `wa_number_checker` — cek nomor WhatsApp via sync Contacts Provider.
///
/// Android-only. Platform lain selalu [WaCheckStatus.unsupported].
library;

export 'src/data/phone_normalizer.dart';
export 'src/domain/wa_app.dart';
export 'src/domain/wa_check_result.dart';
export 'src/domain/wa_check_status.dart';
export 'src/domain/wa_checker_config.dart';
export 'src/domain/wa_device_info.dart';
export 'src/presentation/wa_input_validator.dart';
export 'src/presentation/wa_permission_gate.dart';
export 'src/wa_number_checker.dart';
