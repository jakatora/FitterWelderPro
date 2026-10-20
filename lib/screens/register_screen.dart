import 'package:flutter/material.dart';
import 'account_screen.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const AccountScreen(initialRegister: true);
}
