import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import '../Apiendpoints/apiservices/auth_api_service.dart';
import '../Apiendpoints/apiservices/user_session_manager.dart';

class PaymentSetupPage extends StatefulWidget {
  const PaymentSetupPage({super.key});

  @override
  State<PaymentSetupPage> createState() => _PaymentSetupPageState();
}

class _PaymentSetupPageState extends State<PaymentSetupPage> {
  static const _blue = Color(0xFF76ACC6);

  bool _isLoading = false;
  bool _isLoadingCards = true;
  String? _error;
  String? _setupIntentClientSecret;
  List<Map<String, dynamic>> _savedCards = [];

  static const _stripePublishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  @override
  void initState() {
    super.initState();
    if (_stripePublishableKey.isNotEmpty) {
      Stripe.publishableKey = _stripePublishableKey;
    }
    _loadSavedCards();
  }

  Future<void> _loadSavedCards() async {
    setState(() => _isLoadingCards = true);
    final resp = await AuthApiService.listPaymentMethods();
    if (!mounted) return;
    if (resp.success && resp.data != null) {
      final rawList = resp.data!['payment_methods'] as List<dynamic>? ?? [];
      setState(() {
        _savedCards = rawList
            .map((e) => e as Map<String, dynamic>)
            .toList();
        _isLoadingCards = false;
      });
    } else {
      setState(() => _isLoadingCards = false);
    }
  }

  Future<void> _deleteCard(String pmId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove card?'),
        content: const Text('This card will be removed from your account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final resp = await AuthApiService.deletePaymentMethod(pmId);
    if (!mounted) return;
    if (resp.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Card removed'), backgroundColor: Colors.green),
      );
      _loadSavedCards();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resp.error ?? 'Failed to remove card'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _addCard() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final setupResp = await AuthApiService.setupPaymentMethod();
    if (!setupResp.success || setupResp.data == null) {
      setState(() {
        _isLoading = false;
        _error = setupResp.error ?? 'Failed to initialize payment setup';
      });
      return;
    }

    final data = setupResp.data!;
    final clientSecret = data['setup_intent_client_secret'] as String?;
    final ephemeralKey = data['ephemeral_key'] as String?;
    final customerId = data['customer_id'] as String?;

    if (clientSecret == null || ephemeralKey == null || customerId == null) {
      setState(() {
        _isLoading = false;
        _error = 'Invalid response from server';
      });
      return;
    }

    _setupIntentClientSecret = clientSecret;

    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          setupIntentClientSecret: clientSecret,
          merchantDisplayName: 'PaddlePlus',
          customerId: customerId,
          customerEphemeralKeySecret: ephemeralKey,
          style: ThemeMode.system,
        ),
      );

      await Stripe.instance.presentPaymentSheet();

      final confirmResp = await AuthApiService.confirmPaymentMethod(
        setupIntentClientSecret: _setupIntentClientSecret,
      );

      if (confirmResp.success) {
        final profileResp = await AuthApiService.getProfile();
        if (profileResp.success && profileResp.data != null) {
          await UserSessionManager().updateUser(profileResp.data!);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Card added successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadSavedCards();
        }
      } else {
        setState(() {
          _error = confirmResp.error ?? 'Failed to save payment method';
        });
      }
    } on StripeException catch (e) {
      setState(() {
        _error = e.error.localizedMessage ?? e.error.message ?? 'Payment setup cancelled';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _brandIcon(String brand) {
    switch (brand.toLowerCase()) {
      case 'visa': return 'Visa';
      case 'mastercard': return 'MC';
      case 'amex': return 'Amex';
      case 'discover': return 'Disc';
      default: return brand.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Methods'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            const Text(
              'Saved Cards',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            if (_isLoadingCards)
              const Center(child: CircularProgressIndicator(color: _blue))
            else if (_savedCards.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Text(
                  'No payment method saved yet.\nAdd a card to start riding.',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _savedCards.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final card = _savedCards[i];
                  final isDefault = card['is_default'] == true;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 44,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _brandIcon(card['brand'] ?? ''),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _blue),
                      ),
                    ),
                    title: Text('•••• ${card['last4']}'),
                    subtitle: Text(
                      'Expires ${card['exp_month']}/${card['exp_year']}${isDefault ? ' · Default' : ''}',
                      style: TextStyle(fontSize: 12, color: isDefault ? _blue : Colors.grey),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _deleteCard(card['id'] as String),
                    ),
                  );
                },
              ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _addCard,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_card),
                label: Text(_isLoading ? 'Loading...' : 'Add New Card'),
              ),
            ),

            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 14, color: Colors.grey),
                SizedBox(width: 4),
                Text('Secured by Stripe', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),

            const Spacer(),

            const Text('Accepted payment methods', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            const Wrap(
              spacing: 8,
              children: [
                Chip(label: Text('Visa')),
                Chip(label: Text('Mastercard')),
                Chip(label: Text('Amex')),
                Chip(label: Text('Google Pay')),
                Chip(label: Text('Apple Pay')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
