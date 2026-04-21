/// Represents the result of an API call, containing either successful data or an error.
class ApiResponse<T> {
  /// Indicates if the API call was successful.
  final bool success;

  /// The data returned by the API on success. Null if the call failed.
  final T? data;

  /// The error message returned by the API or generated during the call. Null if the call was successful.
  final String? error;

  /// The HTTP status code of the response. Null for network errors (like no internet).
  final int? statusCode;

  /// Private constructor to create an ApiResponse instance.
  ApiResponse._({
    required this.success,
    this.data,
    this.error,
    this.statusCode,
  });

  /// Factory constructor for a successful API response.
  factory ApiResponse.success(T data) {
    return ApiResponse._(
      success: true,
      data: data,
      error: null,
      // Status code is typically handled within _handleResponse for success cases
      // and not stored in the ApiResponse itself unless it's an error case.
      statusCode: null,
    );
  }

  /// Factory constructor for a failed API response.
  factory ApiResponse.error(String message, {int? statusCode}) {
    return ApiResponse._(
      success: false,
      data: null,
      error: message,
      statusCode: statusCode,
    );
  }

  @override
  String toString() {
    if (success) {
      return 'ApiResponse(success: true, data: $data)';
    } else {
      return 'ApiResponse(success: false, error: $error, statusCode: $statusCode)';
    }
  }
}
