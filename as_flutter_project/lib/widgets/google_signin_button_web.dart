import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as google_sign_in_web;

class GoogleSignInWebButton extends StatelessWidget {
  const GoogleSignInWebButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: google_sign_in_web.renderButton(
        configuration: google_sign_in_web.GSIButtonConfiguration(
          type: google_sign_in_web.GSIButtonType.standard,
          theme: google_sign_in_web.GSIButtonTheme.outline,
          size: google_sign_in_web.GSIButtonSize.large,
          text: google_sign_in_web.GSIButtonText.continueWith,
          shape: google_sign_in_web.GSIButtonShape.rectangular,
          minimumWidth: 320,
        ),
      ),
    );
  }
}
