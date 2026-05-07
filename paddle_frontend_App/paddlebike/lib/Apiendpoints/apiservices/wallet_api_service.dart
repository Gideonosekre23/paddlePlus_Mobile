import 'package:paddlebike/Apiendpoints/models/api_response.dart';
import 'base_api_service.dart';

class WalletApiService {
  static Future<ApiResponse<Map<String, dynamic>>> getWalletBalance() {
    return BaseApiService.requestWithRetry(
      () => BaseApiService.get<Map<String, dynamic>>('/owner/wallet/', auth: true),
    );
  }

  static Future<ApiResponse<Map<String, dynamic>>> requestWithdrawal() {
    return BaseApiService.requestWithRetry(
      () => BaseApiService.post<Map<String, dynamic>>(
        '/owner/wallet/',
        body: {},
        auth: true,
      ),
    );
  }

  static Future<ApiResponse<Map<String, dynamic>>> getPayoutHistory() {
    return BaseApiService.requestWithRetry(
      () => BaseApiService.get<Map<String, dynamic>>('/owner/wallet/history/', auth: true),
    );
  }
}
